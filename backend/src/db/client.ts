import pg from 'pg';
import { config } from '../config.js';

const { Pool } = pg;

// Always use SSL for remote databases (Railway, etc.)
const useSSL = config.databaseUrl.includes('railway.app') ||
               config.databaseUrl.includes('amazonaws.com') ||
               config.nodeEnv === 'production';

export const pool = new Pool({
  connectionString: config.databaseUrl,
  ssl: useSSL ? { rejectUnauthorized: false } : false,
});

pool.on('error', (err) => {
  console.error('Unexpected database error:', err);
});

export async function query<T>(text: string, params?: unknown[]): Promise<T[]> {
  const result = await pool.query(text, params);
  return result.rows as T[];
}

export async function queryOne<T>(text: string, params?: unknown[]): Promise<T | null> {
  const rows = await query<T>(text, params);
  return rows[0] || null;
}
