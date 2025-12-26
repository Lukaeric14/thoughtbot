import OpenAI from 'openai';
import { initLogger, wrapOpenAI } from 'braintrust';
import { config } from '../config.js';

// Initialize Braintrust logger
const logger = initLogger({
  projectName: 'Thoughtbot',
  apiKey: process.env.BRAINTRUST_API_KEY,
});

// Wrap OpenAI client with Braintrust for automatic tracing
export const openai = wrapOpenAI(
  new OpenAI({
    apiKey: config.openaiApiKey,
  })
);

export { logger };
