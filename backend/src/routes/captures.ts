import { Router, Response } from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import { v4 as uuidv4 } from 'uuid';
import { queryOne } from '../db/client.js';
import { transcribeAudio } from '../services/transcription.js';
import { classifyTranscript } from '../services/classification.js';
import { createThought, createTask, updateTask } from '../services/taskMatcher.js';
import type { Capture, ClassificationResult, Category } from '../types/index.js';

const router = Router();

// SSE subscribers waiting for capture completion
const captureSubscribers = new Map<string, Set<Response>>();

/**
 * Notify all SSE subscribers that a capture has completed
 */
function notifyCaptureComplete(captureId: string, classification: string, category: string): void {
  const subscribers = captureSubscribers.get(captureId);
  if (subscribers) {
    const data = JSON.stringify({ classification, category });
    subscribers.forEach(res => {
      res.write(`data: ${data}\n\n`);
      res.end();
    });
    captureSubscribers.delete(captureId);
    console.log(`[${captureId}] Notified ${subscribers.size} SSE subscribers`);
  }
}

// Ensure uploads directory exists
const uploadsDir = path.join(process.cwd(), 'uploads');
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
}

// Configure multer for audio file uploads
const storage = multer.diskStorage({
  destination: uploadsDir,
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname) || '.m4a';
    cb(null, `${uuidv4()}${ext}`);
  },
});

const upload = multer({
  storage,
  limits: {
    fileSize: 25 * 1024 * 1024, // 25MB max (Whisper limit)
  },
  fileFilter: (req, file, cb) => {
    const allowedTypes = ['audio/m4a', 'audio/mp4', 'audio/mpeg', 'audio/wav', 'audio/webm', 'audio/x-m4a'];
    if (allowedTypes.includes(file.mimetype) || file.originalname.match(/\.(m4a|mp3|wav|webm|mp4)$/i)) {
      cb(null, true);
    } else {
      cb(new Error('Invalid audio file type'));
    }
  },
});

// Known empty/invalid transcripts from Whisper when there's silence or noise
const INVALID_TRANSCRIPTS = new Set([
  'you',
  'you.',
  'bye.',
  'bye',
  'thanks.',
  'thanks',
  'thank you.',
  'thank you',
  '',
  '.',
  '..',
  '. .',
  '...',
  'hmm',
  'hmm.',
  'uh',
  'um',
]);

function isInvalidTranscript(transcript: string): boolean {
  const normalized = transcript.trim().toLowerCase();
  // Check exact matches
  if (INVALID_TRANSCRIPTS.has(normalized)) return true;
  // Check if too short (less than 2 chars excluding punctuation/spaces)
  const alphanumeric = normalized.replace(/[^a-z0-9]/g, '');
  if (alphanumeric.length < 2) return true;
  return false;
}

// Process capture asynchronously
async function processCapture(captureId: string, audioPath: string): Promise<void> {
  try {
    // Step 1: Transcribe audio
    console.log(`[${captureId}] Transcribing audio...`);
    const transcript = await transcribeAudio(audioPath);
    console.log(`[${captureId}] Transcript: "${transcript}"`);

    await queryOne(
      `UPDATE captures SET transcript = $1 WHERE id = $2`,
      [transcript, captureId]
    );

    // Check for invalid/empty transcripts (silence produces "you" from Whisper)
    if (isInvalidTranscript(transcript)) {
      console.log(`[${captureId}] Invalid transcript detected, marking as error`);
      await queryOne(
        `UPDATE captures SET classification = $1 WHERE id = $2`,
        ['error', captureId]
      );
      notifyCaptureComplete(captureId, 'error', 'unknown');
      return;
    }

    // Step 2: Classify transcript
    console.log(`[${captureId}] Classifying...`);
    const classification = await classifyTranscript(transcript);
    console.log(`[${captureId}] Classification:`, classification);

    // Store raw LLM output but NOT classification yet (client polls for this)
    await queryOne(
      `UPDATE captures SET raw_llm_output = $1 WHERE id = $2`,
      [JSON.stringify(classification), captureId]
    );

    // Step 3: Create/update entities based on classification
    const category = classification.category || 'personal';

    switch (classification.type) {
      case 'thought':
        if (classification.thought) {
          const { thought, isDuplicate } = await createThought(classification.thought, captureId, category);
          console.log(`[${captureId}] ${isDuplicate ? `Mention count incremented (${thought.mention_count})` : 'Created thought'}: ${thought.id} (${category})`);
        }
        break;

      case 'task_create':
        if (classification.task_create) {
          const { task, isDuplicate } = await createTask(classification.task_create, captureId, category);
          console.log(`[${captureId}] ${isDuplicate ? `Mention count incremented (${task.mention_count})` : 'Created task'}: ${task.id} - "${task.title}" (${category})`);
        }
        break;

      case 'task_update':
        if (classification.task_update) {
          const { task, matched } = await updateTask(classification.task_update, captureId, category);
          console.log(`[${captureId}] ${matched ? 'Updated' : 'Created new'} task: ${task.id} - "${task.title}" (${category})`);
        }
        break;
    }

    // Step 4: Mark classification AFTER entity is created (client polls for this)
    await queryOne(
      `UPDATE captures SET classification = $1 WHERE id = $2`,
      [classification.type, captureId]
    );

    // Notify SSE subscribers (if any) that processing is complete
    notifyCaptureComplete(captureId, classification.type, category);

    console.log(`[${captureId}] Processing complete`);
  } catch (error) {
    console.error(`[${captureId}] Processing error:`, error);
    // Notify subscribers of error
    notifyCaptureComplete(captureId, 'error', 'unknown');
  }
  // Keep audio files for playback in dashboard
}

// Process text capture (skip transcription)
async function processTextCapture(captureId: string, transcript: string, categoryHint?: Category): Promise<void> {
  try {
    console.log(`[${captureId}] Processing text capture: "${transcript}"`);

    // Classify transcript
    console.log(`[${captureId}] Classifying...`);
    const classification = await classifyTranscript(transcript);
    console.log(`[${captureId}] Classification:`, classification);

    // Store raw LLM output
    await queryOne(
      `UPDATE captures SET raw_llm_output = $1 WHERE id = $2`,
      [JSON.stringify(classification), captureId]
    );

    // Always use LLM classification for category - it analyzes the content
    const category: Category = classification.category || 'personal';

    switch (classification.type) {
      case 'thought':
        if (classification.thought) {
          const { thought, isDuplicate } = await createThought(classification.thought, captureId, category);
          console.log(`[${captureId}] ${isDuplicate ? `Mention count incremented (${thought.mention_count})` : 'Created thought'}: ${thought.id} (${category})`);
        }
        break;

      case 'task_create':
        if (classification.task_create) {
          const { task, isDuplicate } = await createTask(classification.task_create, captureId, category);
          console.log(`[${captureId}] ${isDuplicate ? `Mention count incremented (${task.mention_count})` : 'Created task'}: ${task.id} - "${task.title}" (${category})`);
        }
        break;

      case 'task_update':
        if (classification.task_update) {
          const { task, matched } = await updateTask(classification.task_update, captureId, category);
          console.log(`[${captureId}] ${matched ? 'Updated' : 'Created new'} task: ${task.id} - "${task.title}" (${category})`);
        }
        break;
    }

    // Mark classification AFTER entity is created
    await queryOne(
      `UPDATE captures SET classification = $1 WHERE id = $2`,
      [classification.type, captureId]
    );

    // Notify SSE subscribers (if any) that processing is complete
    notifyCaptureComplete(captureId, classification.type, category);

    console.log(`[${captureId}] Text capture processing complete`);
  } catch (error) {
    console.error(`[${captureId}] Text capture processing error:`, error);
    // Notify subscribers of error
    notifyCaptureComplete(captureId, 'error', 'unknown');
  }
}

// POST /api/captures - Upload and process audio capture
router.post('/', upload.single('audio'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No audio file provided' });
    }

    const audioPath = req.file.path;
    const audioUrl = `/uploads/${req.file.filename}`;

    // Create capture record
    const capture = await queryOne<Capture>(
      `INSERT INTO captures (audio_url)
       VALUES ($1)
       RETURNING *`,
      [audioUrl]
    );

    if (!capture) {
      return res.status(500).json({ error: 'Failed to create capture' });
    }

    // Return immediately (fire-and-forget)
    res.status(202).json({
      id: capture.id,
      status: 'processing',
    });

    // Process asynchronously
    processCapture(capture.id, audioPath);
  } catch (error) {
    console.error('Capture upload error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// POST /api/captures/text - Create capture from text (no audio)
router.post('/text', async (req, res) => {
  try {
    const { text, category: rawCategory } = req.body;

    if (!text || typeof text !== 'string' || text.trim().length === 0) {
      return res.status(400).json({ error: 'Text is required' });
    }

    // Validate category if provided
    const category: Category | undefined = (rawCategory === 'personal' || rawCategory === 'business')
      ? rawCategory
      : undefined;

    // Create capture record with transcript already set (no audio)
    const capture = await queryOne<Capture>(
      `INSERT INTO captures (transcript)
       VALUES ($1)
       RETURNING *`,
      [text.trim()]
    );

    if (!capture) {
      return res.status(500).json({ error: 'Failed to create capture' });
    }

    // Return immediately (fire-and-forget)
    res.status(202).json({
      id: capture.id,
      status: 'processing',
    });

    // Process asynchronously (skip transcription since we already have text)
    processTextCapture(capture.id, text.trim(), category);
  } catch (error) {
    console.error('Text capture error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /api/captures/:id - Get capture status (optional, for debugging)
router.get('/:id', async (req, res) => {
  try {
    const capture = await queryOne<Capture>(
      `SELECT * FROM captures WHERE id = $1`,
      [req.params.id]
    );

    if (!capture) {
      return res.status(404).json({ error: 'Capture not found' });
    }

    res.json(capture);
  } catch (error) {
    console.error('Get capture error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /api/captures/:id/stream - SSE endpoint for capture status
// Client connects and waits for processing to complete
// Much more efficient than polling (1 connection vs 60 requests)
router.get('/:id/stream', async (req, res) => {
  const captureId = req.params.id;

  try {
    // First check if capture exists and is already complete
    const capture = await queryOne<Capture>(
      `SELECT * FROM captures WHERE id = $1`,
      [captureId]
    );

    if (!capture) {
      return res.status(404).json({ error: 'Capture not found' });
    }

    // If already classified, return immediately
    if (capture.classification) {
      const category = capture.raw_llm_output
        ? (typeof capture.raw_llm_output === 'string'
            ? JSON.parse(capture.raw_llm_output)?.category
            : (capture.raw_llm_output as { category?: string })?.category) || 'personal'
        : 'personal';

      return res.json({
        classification: capture.classification,
        category,
      });
    }

    // Set up SSE headers
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.setHeader('X-Accel-Buffering', 'no'); // Disable nginx buffering
    res.flushHeaders();

    // Add to subscribers
    if (!captureSubscribers.has(captureId)) {
      captureSubscribers.set(captureId, new Set());
    }
    captureSubscribers.get(captureId)!.add(res);

    console.log(`[${captureId}] SSE subscriber connected (total: ${captureSubscribers.get(captureId)!.size})`);

    // Send keepalive comment every 15 seconds
    const keepalive = setInterval(() => {
      res.write(': keepalive\n\n');
    }, 15000);

    // Handle client disconnect
    req.on('close', () => {
      clearInterval(keepalive);
      const subscribers = captureSubscribers.get(captureId);
      if (subscribers) {
        subscribers.delete(res);
        if (subscribers.size === 0) {
          captureSubscribers.delete(captureId);
        }
      }
      console.log(`[${captureId}] SSE subscriber disconnected`);
    });

    // Timeout after 60 seconds (longer than processing should ever take)
    setTimeout(() => {
      const subscribers = captureSubscribers.get(captureId);
      if (subscribers && subscribers.has(res)) {
        res.write(`data: ${JSON.stringify({ classification: 'timeout', category: 'unknown' })}\n\n`);
        res.end();
        subscribers.delete(res);
      }
    }, 60000);

  } catch (error) {
    console.error('SSE stream error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
