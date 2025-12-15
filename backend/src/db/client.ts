import pg from 'pg';
import { config } from '../config.js';

const { Pool } = pg;

// Railway proxy doesn't need SSL - only internal connections do
const isLocalhost = config.databaseUrl.includes('localhost') || config.databaseUrl.includes('127.0.0.1');
const isRailwayProxy = config.databaseUrl.includes('proxy.rlwy.net');
const useSSL = !isLocalhost && !isRailwayProxy;

console.log('Database URL host:', config.databaseUrl.split('@')[1]?.split('/')[0] || 'unknown');
console.log('Using SSL:', useSSL);

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
