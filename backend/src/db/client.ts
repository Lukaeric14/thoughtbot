import pg from 'pg';
import { config } from '../config.js';

const { Pool } = pg;

// Railway proxy connections don't need SSL (proxy handles it)
const isLocalhost = config.databaseUrl.includes('localhost') || config.databaseUrl.includes('127.0.0.1');
const isProxy = config.databaseUrl.includes('.proxy.rlwy.net');

console.log('Database URL host:', config.databaseUrl.split('@')[1]?.split('/')[0] || 'unknown');
console.log('Using SSL:', !isLocalhost && !isProxy);

export const pool = new Pool({
  connectionString: config.databaseUrl,
  ssl: (isLocalhost || isProxy) ? false : {
    rejectUnauthorized: false,
  },
  connectionTimeoutMillis: 30000,
  idleTimeoutMillis: 30000,
  max: 10,
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
