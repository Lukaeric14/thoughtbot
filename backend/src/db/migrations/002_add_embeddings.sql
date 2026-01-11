-- Add embedding column for semantic task matching (deduplication)
-- Embeddings are stored as JSON arrays (compatible with all PostgreSQL versions)
-- Note: Only tasks have embeddings - thoughts don't use deduplication

ALTER TABLE tasks ADD COLUMN IF NOT EXISTS embedding TEXT;

-- Note: Embeddings are generated on-demand and cached
-- For large datasets, consider using pgvector extension:
-- CREATE EXTENSION IF NOT EXISTS vector;
-- ALTER TABLE tasks ADD COLUMN embedding vector(1536);
