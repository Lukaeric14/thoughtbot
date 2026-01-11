import type { Task, Category } from '../types/index.js';
import {
  findSemanticTaskMatchByEmbedding,
  invalidateEmbeddingCache,
} from './embeddings.js';

/**
 * Find a semantically matching active task using embeddings
 * Much faster than GPT-based matching (~5-15ms vs 1-3s)
 * Cost: ~$0.000002 per match vs ~$0.00011 with GPT-4o-mini
 *
 * Note: Only matches OPEN tasks - completed tasks are excluded
 * so recurring tasks create new records after completion.
 */
export async function findSemanticTaskMatch(
  newTitle: string,
  category: Category
): Promise<Task | null> {
  return findSemanticTaskMatchByEmbedding(newTitle);
}

/**
 * Invalidate embedding cache (call after adding/updating items)
 */
export { invalidateEmbeddingCache };
