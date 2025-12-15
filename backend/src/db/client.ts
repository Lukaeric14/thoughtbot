import pg from 'pg';
import { config } from '../config.js';

const { Pool } = pg;

// Parse SSL mode from connection string or default based on environment
const useSSL = config.nodeEnv === 'production' ||
               config.databaseUrl.includes('railway') ||
               config.databaseUrl.includes('amazonaws.com') ||
               config.databaseUrl.includes('proxy.rlwy.net');

export const pool = new Pool({
  connectionString: config.databaseUrl,
  ssl: useSSL ? { rejectUnauthorized: false } : false,
  connectionTimeoutMillis: 10000,
  idleTimeoutMillis: 30000,
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
