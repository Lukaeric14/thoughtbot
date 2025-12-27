import { Router } from 'express';
import { query, queryOne } from '../db/client.js';
import type { Thought } from '../types/index.js';

const router = Router();

// Extended thought type with transcript and audio
interface ThoughtWithTranscript extends Thought {
  transcript: string | null;
  audio_url: string | null;
}

// GET /api/thoughts - List all thoughts (optionally filtered by category)
// Supports pagination: ?limit=50&offset=0 (default limit: 100)
// Use ?slim=true to skip transcript/audio_url JOIN for faster list queries
router.get('/', async (req, res) => {
  try {
    const category = req.query.category as string | undefined;
    const slim = req.query.slim === 'true';
    const limit = Math.min(parseInt(req.query.limit as string) || 100, 500);
    const offset = parseInt(req.query.offset as string) || 0;

    let sql: string;
    if (slim) {
      // Fast query without JOIN - for list views
      sql = `SELECT * FROM thoughts`;
    } else {
      // Full query with transcript - for detail views
      sql = `
        SELECT t.*, c.transcript, c.audio_url
        FROM thoughts t
        LEFT JOIN captures c ON t.capture_id = c.id
      `;
    }
    const params: unknown[] = [];
    let paramIndex = 1;

    if (category) {
      sql += slim ? ` WHERE category = $${paramIndex++}` : ` WHERE t.category = $${paramIndex++}`;
      params.push(category);
    }

    // Sort by mention_count DESC (most mentioned first), then by created_at DESC
    sql += slim ? ` ORDER BY mention_count DESC, created_at DESC` : ` ORDER BY t.mention_count DESC, t.created_at DESC`;

    // Add pagination
    sql += ` LIMIT $${paramIndex++} OFFSET $${paramIndex}`;
    params.push(limit, offset);

    const thoughts = await query<ThoughtWithTranscript>(sql, params);
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
