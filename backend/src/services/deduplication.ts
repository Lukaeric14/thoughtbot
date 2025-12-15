import { query } from '../db/client.js';
import type { Task } from '../types/index.js';

// Normalize text for comparison: lowercase, remove punctuation, trim
export function normalizeText(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^\w\s]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

// Check for duplicate tasks in the last 14 days
export async function findDuplicateTask(
  canonicalTitle: string,
  threshold: number = 0.7
): Promise<Task | null> {
  // Query open tasks from last 14 days with similarity score
  const tasks = await query<Task & { similarity: number }>(
    `SELECT *, similarity(canonical_title, $1) as similarity
     FROM tasks
     WHERE status = 'open'
       AND created_at > NOW() - INTERVAL '14 days'
       AND similarity(canonical_title, $1) > $2
     ORDER BY similarity DESC
     LIMIT 1`,
    [canonicalTitle, threshold]
  );

  return tasks[0] || null;
}

// Find a task matching the target hint for updates
export async function findMatchingTask(
  targetHint: string,
  threshold: number = 0.5
): Promise<Task | null> {
  const canonicalHint = normalizeText(targetHint);

  // First try exact substring match
  const exactMatch = await query<Task>(
    `SELECT *
     FROM tasks
     WHERE status = 'open'
       AND canonical_title ILIKE '%' || $1 || '%'
     ORDER BY created_at DESC
     LIMIT 1`,
    [canonicalHint]
  );

  if (exactMatch[0]) {
    return exactMatch[0];
  }

  // Fall back to trigram similarity
  const similarMatch = await query<Task & { similarity: number }>(
    `SELECT *, similarity(canonical_title, $1) as similarity
     FROM tasks
     WHERE status = 'open'
       AND similarity(canonical_title, $1) > $2
     ORDER BY similarity DESC
     LIMIT 1`,
    [canonicalHint, threshold]
  );

  return similarMatch[0] || null;
}
