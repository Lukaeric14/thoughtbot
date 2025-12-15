import express from 'express';
import cors from 'cors';
import path from 'path';
import { config, validateConfig } from './config.js';
import { pool } from './db/client.js';
import capturesRouter from './routes/captures.js';
import thoughtsRouter from './routes/thoughts.js';
import tasksRouter from './routes/tasks.js';

// Validate environment
try {
  validateConfig();
} catch (error) {
  console.error('Configuration error:', error);
  process.exit(1);
}

// Auto-migrate on startup
async function migrate() {
  const schema = `
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    CREATE EXTENSION IF NOT EXISTS "pg_trgm";

    CREATE TABLE IF NOT EXISTS captures (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      created_at TIMESTAMPTZ DEFAULT NOW(),
      audio_url TEXT,
      transcript TEXT,
      classification VARCHAR(20),
      raw_llm_output JSONB
    );

    CREATE TABLE IF NOT EXISTS thoughts (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      created_at TIMESTAMPTZ DEFAULT NOW(),
      text TEXT NOT NULL,
      canonical_text TEXT,
      capture_id UUID REFERENCES captures(id) ON DELETE SET NULL
    );

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

    CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
    CREATE INDEX IF NOT EXISTS idx_tasks_due_date ON tasks(due_date);
    CREATE INDEX IF NOT EXISTS idx_tasks_canonical ON tasks(canonical_title);
    CREATE INDEX IF NOT EXISTS idx_captures_created ON captures(created_at);
  `;

  try {
    await pool.query(schema);
    console.log('Database migration completed');
  } catch (error) {
    console.error('Migration error:', error);
  }
}

const app = express();

// Middleware
app.use(cors());
app.use(express.json());

// Serve uploaded audio files
app.use('/uploads', express.static(path.join(process.cwd(), 'uploads')));

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// API routes
app.use('/api/captures', capturesRouter);
app.use('/api/thoughts', thoughtsRouter);
app.use('/api/tasks', tasksRouter);

// Error handling
app.use((err: Error, req: express.Request, res: express.Response, next: express.NextFunction) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ error: 'Internal server error' });
});

// Start server
migrate().then(() => {
  app.listen(config.port, () => {
    console.log(`Server running on port ${config.port}`);
    console.log(`Environment: ${config.nodeEnv}`);
  });
});
