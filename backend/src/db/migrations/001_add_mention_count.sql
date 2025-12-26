-- Migration: Add mention_count column to tasks and thoughts tables
-- Run this on production database before deploying the new code

-- Add mention_count to thoughts table (default to 1 for existing rows)
ALTER TABLE thoughts ADD COLUMN IF NOT EXISTS mention_count INT DEFAULT 1;

-- Add mention_count to tasks table (default to 1 for existing rows)
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS mention_count INT DEFAULT 1;

-- Update existing rows to have mention_count = 1
UPDATE thoughts SET mention_count = 1 WHERE mention_count IS NULL;
UPDATE tasks SET mention_count = 1 WHERE mention_count IS NULL;
