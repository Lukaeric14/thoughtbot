import { Router } from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import { v4 as uuidv4 } from 'uuid';
import { queryOne } from '../db/client.js';
import { transcribeAudio } from '../services/transcription.js';
import { classifyTranscript } from '../services/classification.js';
import { createThought, createTask, updateTask } from '../services/taskMatcher.js';
import type { Capture, ClassificationResult } from '../types/index.js';

const router = Router();

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

    console.log(`[${captureId}] Processing complete`);
  } catch (error) {
    console.error(`[${captureId}] Processing error:`, error);
    // Don't throw - we don't want to affect the response
  }
  // Keep audio files for playback in dashboard
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

export default router;
