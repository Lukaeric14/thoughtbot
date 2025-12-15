-- Enable UUID generation and trigram similarity
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Captures: raw audio input log
CREATE TABLE IF NOT EXISTS captures (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  audio_url TEXT,
  transcript TEXT,
  classification VARCHAR(20),
  raw_llm_output JSONB
);

-- Thoughts: non-actionable ideas
CREATE TABLE IF NOT EXISTS thoughts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  text TEXT NOT NULL,
  canonical_text TEXT,
  capture_id UUID REFERENCES captures(id) ON DELETE SET NULL
);

-- Tasks: actionable commitments
CREATE TABLE IF NOT EXISTS tasks (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  title TEXT NOT NULL,
  canonical_title TEXT,
  due_date DATE NOT NULL,
  status VARCHAR(20) DEFAULT 'open',
  last_updated_at TIMESTAMPTZ DEFAULT NOW(),
  capture_id UUID REFERENCES captures(id) ON DELETE SET NULL
);

-- Indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_due_date ON tasks(due_date);
CREATE INDEX IF NOT EXISTS idx_tasks_canonical ON tasks(canonical_title);
CREATE INDEX IF NOT EXISTS idx_tasks_canonical_trgm ON tasks USING gin (canonical_title gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_captures_created ON captures(created_at);
