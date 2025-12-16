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
      category VARCHAR(20) DEFAULT 'personal',
      capture_id UUID REFERENCES captures(id) ON DELETE SET NULL
    );

    CREATE TABLE IF NOT EXISTS tasks (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      created_at TIMESTAMPTZ DEFAULT NOW(),
      title TEXT NOT NULL,
      canonical_title TEXT,
      due_date DATE NOT NULL,
      status VARCHAR(20) DEFAULT 'open',
      category VARCHAR(20) DEFAULT 'personal',
      last_updated_at TIMESTAMPTZ DEFAULT NOW(),
      capture_id UUID REFERENCES captures(id) ON DELETE SET NULL
    );

    CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
    CREATE INDEX IF NOT EXISTS idx_tasks_due_date ON tasks(due_date);
    CREATE INDEX IF NOT EXISTS idx_tasks_canonical ON tasks(canonical_title);
    CREATE INDEX IF NOT EXISTS idx_captures_created ON captures(created_at);
    CREATE INDEX IF NOT EXISTS idx_thoughts_category ON thoughts(category);
    CREATE INDEX IF NOT EXISTS idx_tasks_category ON tasks(category);

    -- Add category columns if they don't exist (for existing databases)
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'thoughts' AND column_name = 'category') THEN
        ALTER TABLE thoughts ADD COLUMN category VARCHAR(20) DEFAULT 'personal';
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'category') THEN
        ALTER TABLE tasks ADD COLUMN category VARCHAR(20) DEFAULT 'personal';
      END IF;
    END $$;

    -- Set default category for existing data (thoughts to personal, tasks to business)
    UPDATE thoughts SET category = 'personal' WHERE category IS NULL;
    UPDATE tasks SET category = 'business' WHERE category IS NULL;
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

// Admin: Run category migration manually
app.post('/admin/migrate-categories', async (req, res) => {
  try {
    // Add category columns if missing
    await pool.query(`
      DO $$
      BEGIN
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'thoughts' AND column_name = 'category') THEN
          ALTER TABLE thoughts ADD COLUMN category VARCHAR(20) DEFAULT 'personal';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'category') THEN
          ALTER TABLE tasks ADD COLUMN category VARCHAR(20) DEFAULT 'personal';
        END IF;
      END $$;
    `);

    // Set defaults for existing data
    const thoughtsResult = await pool.query(`UPDATE thoughts SET category = 'personal' WHERE category IS NULL`);
    const tasksResult = await pool.query(`UPDATE tasks SET category = 'business' WHERE category IS NULL`);

    // Get counts
    const thoughtCounts = await pool.query(`SELECT category, COUNT(*) as count FROM thoughts GROUP BY category`);
    const taskCounts = await pool.query(`SELECT category, COUNT(*) as count FROM tasks GROUP BY category`);

    res.json({
      success: true,
      thoughtsUpdated: thoughtsResult.rowCount,
      tasksUpdated: tasksResult.rowCount,
      thoughtCounts: thoughtCounts.rows,
      taskCounts: taskCounts.rows
    });
  } catch (error) {
    console.error('Category migration error:', error);
    res.status(500).json({ error: 'Migration failed', details: String(error) });
  }
});

// Admin: Set all tasks to business (one-time fix)
app.post('/admin/set-tasks-business', async (req, res) => {
  try {
    const tasksResult = await pool.query(`UPDATE tasks SET category = 'business'`);
    const taskCounts = await pool.query(`SELECT category, COUNT(*) as count FROM tasks GROUP BY category`);
    res.json({
      success: true,
      tasksUpdated: tasksResult.rowCount,
      taskCounts: taskCounts.rows
    });
  } catch (error) {
    console.error('Set tasks business error:', error);
    res.status(500).json({ error: 'Failed', details: String(error) });
  }
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
