import dotenv from 'dotenv';

dotenv.config();

export const config = {
  port: parseInt(process.env.PORT || '3000', 10),
  nodeEnv: process.env.NODE_ENV || 'development',
  databaseUrl: process.env.DATABASE_URL || '',
  openaiApiKey: process.env.OPENAI_API_KEY || '',
};

export function validateConfig(): void {
  if (!config.databaseUrl) {
    throw new Error('DATABASE_URL is required');
  }
  if (!config.openaiApiKey) {
    throw new Error('OPENAI_API_KEY is required');
  }
}
