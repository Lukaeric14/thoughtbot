import { query, queryOne } from '../db/client.js';
import { normalizeText, findDuplicateTask, findMatchingTask } from './deduplication.js';
import type { Task, Thought, TaskCreatePayload, TaskUpdatePayload, ThoughtPayload } from '../types/index.js';

function getTodayDate(): string {
  return new Date().toISOString().split('T')[0];
}

export async function createThought(
  payload: ThoughtPayload,
  captureId: string
): Promise<Thought> {
  const canonicalText = normalizeText(payload.text);

  const result = await queryOne<Thought>(
    `INSERT INTO thoughts (text, canonical_text, capture_id)
     VALUES ($1, $2, $3)
     RETURNING *`,
    [payload.text, canonicalText, captureId]
  );

  if (!result) {
    throw new Error('Failed to create thought');
  }

  return result;
}

export async function createTask(
  payload: TaskCreatePayload,
  captureId: string
): Promise<{ task: Task; isDuplicate: boolean }> {
  const canonicalTitle = normalizeText(payload.title);
  const dueDate = payload.due_date || getTodayDate();

  // Check for duplicates
  const existingTask = await findDuplicateTask(canonicalTitle, 0.85);
  if (existingTask) {
    console.log(`Duplicate detected: "${payload.title}" matches "${existingTask.title}"`);
    return { task: existingTask, isDuplicate: true };
  }

  const result = await queryOne<Task>(
    `INSERT INTO tasks (title, canonical_title, due_date, status, capture_id)
     VALUES ($1, $2, $3, 'open', $4)
     RETURNING *`,
    [payload.title, canonicalTitle, dueDate, captureId]
  );

  if (!result) {
    throw new Error('Failed to create task');
  }

  return { task: result, isDuplicate: false };
}

export async function updateTask(
  payload: TaskUpdatePayload,
  captureId: string
): Promise<{ task: Task; matched: boolean }> {
  // Try to find matching task
  const matchingTask = await findMatchingTask(payload.target_hint);

  if (matchingTask) {
    let updatedTask: Task | null = null;

    switch (payload.operation) {
      case 'complete':
        updatedTask = await queryOne<Task>(
          `UPDATE tasks
           SET status = 'done', last_updated_at = NOW()
           WHERE id = $1
           RETURNING *`,
          [matchingTask.id]
        );
        break;

      case 'cancel':
        updatedTask = await queryOne<Task>(
          `UPDATE tasks
           SET status = 'cancelled', last_updated_at = NOW()
           WHERE id = $1
           RETURNING *`,
          [matchingTask.id]
        );
        break;

      case 'postpone':
      case 'set_due_date':
        const newDate = payload.new_due_date || getTomorrowDate();
        updatedTask = await queryOne<Task>(
          `UPDATE tasks
           SET due_date = $1, last_updated_at = NOW()
           WHERE id = $2
           RETURNING *`,
          [newDate, matchingTask.id]
        );
        break;

      case 'rename':
        // Rename is optional in v1, skip for now
        updatedTask = matchingTask;
        break;
    }

    if (updatedTask) {
      return { task: updatedTask, matched: true };
    }
  }

  // No match found - create a new task from the update intent
  // This ensures we never lose user input
  console.log(`No match found for "${payload.target_hint}", creating new task`);

  const title = payload.target_hint;
  const dueDate = payload.new_due_date || getTodayDate();
  const canonicalTitle = normalizeText(title);

  const newTask = await queryOne<Task>(
    `INSERT INTO tasks (title, canonical_title, due_date, status, capture_id)
     VALUES ($1, $2, $3, 'open', $4)
     RETURNING *`,
    [title, canonicalTitle, dueDate, captureId]
  );

  if (!newTask) {
    throw new Error('Failed to create task from update intent');
  }

  return { task: newTask, matched: false };
}

function getTomorrowDate(): string {
  const tomorrow = new Date();
  tomorrow.setDate(tomorrow.getDate() + 1);
  return tomorrow.toISOString().split('T')[0];
}
