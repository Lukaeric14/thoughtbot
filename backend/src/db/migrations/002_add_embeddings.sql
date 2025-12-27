-- Add embedding columns for semantic matching
-- Embeddings are stored as JSON arrays (compatible with all PostgreSQL versions)

ALTER TABLE tasks ADD COLUMN IF NOT EXISTS embedding TEXT;
ALTER TABLE thoughts ADD COLUMN IF NOT EXISTS embedding TEXT;

-- Note: Embeddings are generated on-demand and cached
-- For large datasets, consider using pgvector extension:
-- CREATE EXTENSION IF NOT EXISTS vector;
-- ALTER TABLE tasks ADD COLUMN embedding vector(1536);
