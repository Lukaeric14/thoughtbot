import type { Task, Thought, Category } from '../types/index.js';
import {
  findSemanticTaskMatchByEmbedding,
  findSemanticThoughtMatchByEmbedding,
  invalidateEmbeddingCache,
} from './embeddings.js';

/**
 * Find a semantically matching active task using embeddings
 * Much faster than GPT-based matching (~5-15ms vs 1-3s)
 * Cost: ~$0.000002 per match vs ~$0.00011 with GPT-4o-mini
 */
export async function findSemanticTaskMatch(
  newTitle: string,
  category: Category
): Promise<Task | null> {
  return findSemanticTaskMatchByEmbedding(newTitle);
}

/**
 * Find a semantically matching thought using embeddings
 * Much faster than GPT-based matching (~5-15ms vs 1-3s)
 */
export async function findSemanticThoughtMatch(
  newText: string,
  category: Category
): Promise<Thought | null> {
  return findSemanticThoughtMatchByEmbedding(newText);
}

/**
 * Invalidate embedding cache (call after adding/updating items)
 */
export { invalidateEmbeddingCache };
