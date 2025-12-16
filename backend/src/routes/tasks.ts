import { Router } from 'express';
import { query, queryOne } from '../db/client.js';
import type { Task, TaskStatus } from '../types/index.js';

const router = Router();

// Extended task type with transcript
interface TaskWithTranscript extends Task {
  transcript: string | null;
  category: string;
}

// GET /api/tasks - List all tasks (optionally filtered by status and category)
router.get('/', async (req, res) => {
  try {
    const status = req.query.status as TaskStatus | undefined;
    const category = req.query.category as string | undefined;

    let sql = `
      SELECT t.*, c.transcript
      FROM tasks t
      LEFT JOIN captures c ON t.capture_id = c.id
    `;
    const params: unknown[] = [];
    const conditions: string[] = [];

    if (status) {
      conditions.push(`t.status = $${params.length + 1}`);
      params.push(status);
    }

    if (category) {
      conditions.push(`t.category = $${params.length + 1}`);
      params.push(category);
    }

    if (conditions.length > 0) {
      sql += ` WHERE ${conditions.join(' AND ')}`;
    }

    sql += ` ORDER BY t.created_at DESC`;

    const tasks = await query<TaskWithTranscript>(sql, params);
    res.json(tasks);
  } catch (error) {
    console.error('Get tasks error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /api/tasks/:id - Get single task
router.get('/:id', async (req, res) => {
  try {
    const task = await queryOne<TaskWithTranscript>(
      `SELECT t.*, c.transcript
       FROM tasks t
       LEFT JOIN captures c ON t.capture_id = c.id
       WHERE t.id = $1`,
      [req.params.id]
    );

    if (!task) {
      return res.status(404).json({ error: 'Task not found' });
    }

    res.json(task);
  } catch (error) {
    console.error('Get task error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// PATCH /api/tasks/:id - Update task
router.patch('/:id', async (req, res) => {
  try {
    const { status, title, due_date } = req.body;

    // Build dynamic update query
    const updates: string[] = [];
    const params: unknown[] = [];
    let paramIndex = 1;

    if (status !== undefined) {
      updates.push(`status = $${paramIndex++}`);
      params.push(status);
    }

    if (title !== undefined) {
      updates.push(`title = $${paramIndex++}`);
      params.push(title);
    }

    if (due_date !== undefined) {
      updates.push(`due_date = $${paramIndex++}`);
      params.push(due_date);
    }

    if (updates.length === 0) {
      return res.status(400).json({ error: 'No updates provided' });
    }

    updates.push(`last_updated_at = NOW()`);
    params.push(req.params.id);

    const task = await queryOne<Task>(
      `UPDATE tasks
       SET ${updates.join(', ')}
       WHERE id = $${paramIndex}
       RETURNING *`,
      params
    );

    if (!task) {
      return res.status(404).json({ error: 'Task not found' });
    }

    res.json(task);
  } catch (error) {
    console.error('Update task error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// DELETE /api/tasks/:id - Delete task
router.delete('/:id', async (req, res) => {
  try {
    const task = await queryOne<Task>(
      `DELETE FROM tasks WHERE id = $1 RETURNING *`,
      [req.params.id]
    );

    if (!task) {
      return res.status(404).json({ error: 'Task not found' });
    }

    res.json({ success: true });
  } catch (error) {
    console.error('Delete task error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
