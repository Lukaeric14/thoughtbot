import { openai } from './openaiClient.js';
import { query, queryOne } from '../db/client.js';
import type { Task } from '../types/index.js';

const EMBEDDING_MODEL = 'text-embedding-3-small';
const EMBEDDING_DIMENSIONS = 1536;
const SIMILARITY_THRESHOLD = 0.75; // Higher = more strict matching

// In-memory cache for embeddings (refreshed on demand)
// Note: Only tasks use embeddings - thoughts don't have deduplication
interface EmbeddingCache {
  tasks: Map<string, { task: Task; embedding: number[] }>;
  lastRefresh: Date;
}

let embeddingCache: EmbeddingCache = {
  tasks: new Map(),
  lastRefresh: new Date(0),
};

const CACHE_TTL_MS = 60_000; // 1 minute cache

/**
 * Generate embedding for a text using OpenAI text-embedding-3-small
 */
export async function generateEmbedding(text: string): Promise<number[]> {
  const response = await openai.embeddings.create({
    model: EMBEDDING_MODEL,
    input: text.slice(0, 8000), // Limit input length
  });

  return response.data[0].embedding;
}

/**
 * Compute cosine similarity between two embeddings
 */
function cosineSimilarity(a: number[], b: number[]): number {
  if (a.length !== b.length) return 0;

  let dotProduct = 0;
  let normA = 0;
  let normB = 0;

  for (let i = 0; i < a.length; i++) {
    dotProduct += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }

  const magnitude = Math.sqrt(normA) * Math.sqrt(normB);
  return magnitude === 0 ? 0 : dotProduct / magnitude;
}

/**
 * Refresh the embedding cache for active tasks
 */
async function refreshTaskEmbeddings(): Promise<void> {
  const tasks = await query<Task & { embedding: string | null }>(
    `SELECT * FROM tasks WHERE status = 'open' ORDER BY mention_count DESC, created_at DESC LIMIT 50`,
    []
  );

  const newCache = new Map<string, { task: Task; embedding: number[] }>();

  for (const task of tasks) {
    let embedding: number[];

    if (task.embedding) {
      // Use cached embedding from DB
      embedding = JSON.parse(task.embedding);
    } else {
      // Generate and store new embedding
      embedding = await generateEmbedding(task.title);
      await query(
        `UPDATE tasks SET embedding = $1 WHERE id = $2`,
        [JSON.stringify(embedding), task.id]
      );
    }

    newCache.set(task.id, { task, embedding });
  }

  embeddingCache.tasks = newCache;
}

/**
 * Ensure cache is fresh
 */
async function ensureCacheFresh(): Promise<void> {
  const now = new Date();
  if (now.getTime() - embeddingCache.lastRefresh.getTime() > CACHE_TTL_MS) {
    await refreshTaskEmbeddings();
    embeddingCache.lastRefresh = now;
  }
}

/**
 * Find a semantically matching task using embeddings
 * Returns the best matching task if similarity > threshold
 */
export async function findSemanticTaskMatchByEmbedding(
  newTitle: string
): Promise<Task | null> {
  await ensureCacheFresh();

  if (embeddingCache.tasks.size === 0) {
    return null;
  }

  // Generate embedding for new text
  const newEmbedding = await generateEmbedding(newTitle);

  let bestMatch: { task: Task; similarity: number } | null = null;

  for (const { task, embedding } of embeddingCache.tasks.values()) {
    const similarity = cosineSimilarity(newEmbedding, embedding);

    if (similarity > SIMILARITY_THRESHOLD) {
      if (!bestMatch || similarity > bestMatch.similarity) {
        bestMatch = { task, similarity };
      }
    }
  }

  if (bestMatch) {
    console.log(
      `Embedding match found: "${newTitle}" matches "${bestMatch.task.title}" (similarity: ${bestMatch.similarity.toFixed(3)})`
    );
    return bestMatch.task;
  }

  console.log(`No embedding match for "${newTitle}" (max similarity below ${SIMILARITY_THRESHOLD})`);
  return null;
}

/**
 * Invalidate cache (call after adding/updating items)
 */
export function invalidateEmbeddingCache(): void {
  embeddingCache.lastRefresh = new Date(0);
}
