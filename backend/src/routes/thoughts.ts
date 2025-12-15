import { Router } from 'express';
import { query, queryOne } from '../db/client.js';
import type { Thought } from '../types/index.js';

const router = Router();

// Extended thought type with transcript and audio
interface ThoughtWithTranscript extends Thought {
  transcript: string | null;
  audio_url: string | null;
}

// GET /api/thoughts - List all thoughts
router.get('/', async (req, res) => {
  try {
    const thoughts = await query<ThoughtWithTranscript>(
      `SELECT t.*, c.transcript, c.audio_url
       FROM thoughts t
       LEFT JOIN captures c ON t.capture_id = c.id
       ORDER BY t.created_at DESC`
    );

    res.json(thoughts);
  } catch (error) {
    console.error('Get thoughts error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /api/thoughts/:id - Get single thought
router.get('/:id', async (req, res) => {
  try {
    const thought = await queryOne<ThoughtWithTranscript>(
      `SELECT t.*, c.transcript, c.audio_url
       FROM thoughts t
       LEFT JOIN captures c ON t.capture_id = c.id
       WHERE t.id = $1`,
      [req.params.id]
    );

    if (!thought) {
      return res.status(404).json({ error: 'Thought not found' });
    }

    res.json(thought);
  } catch (error) {
    console.error('Get thought error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// DELETE /api/thoughts/:id - Delete thought
router.delete('/:id', async (req, res) => {
  try {
    const thought = await queryOne<Thought>(
      `DELETE FROM thoughts WHERE id = $1 RETURNING *`,
      [req.params.id]
    );

    if (!thought) {
      return res.status(404).json({ error: 'Thought not found' });
    }

    res.json({ success: true });
  } catch (error) {
    console.error('Delete thought error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
