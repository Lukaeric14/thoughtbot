import OpenAI from 'openai';
import { config } from '../config.js';
import type { ClassificationResult } from '../types/index.js';

const openai = new OpenAI({
  apiKey: config.openaiApiKey,
});

function getTodayDate(): string {
  return new Date().toISOString().split('T')[0];
}

function buildPrompt(transcript: string): string {
  return `You are a classifier for a voice capture system. Given a transcript, classify it as exactly ONE of: thought, task_create, task_update.

Rules:
- thought: Non-actionable observations, ideas, reflections. Things like "I think...", "Maybe we should...", "It would be nice if..."
- task_create: Commitments to do something specific. Has an action verb and implies obligation. Examples: "I need to...", "Remind me to...", "I have to..."
- task_update: References completing, canceling, postponing, or rescheduling an existing task. Examples: "Done with...", "Cancel the...", "Postpone... to tomorrow"

For task_create:
- Extract a concise, imperative title (e.g., "Post LinkedIn update" not "I need to post a LinkedIn update")
- Extract due_date if mentioned, otherwise set to null (backend will default to today)
- Dates like "tomorrow", "next Monday" should be converted to YYYY-MM-DD format

For task_update:
- operation: "complete" (done/finished), "cancel" (no longer needed), "postpone" (move to later date), "set_due_date" (change date)
- target_hint: key phrase to match against existing tasks
- new_due_date: the new date if rescheduling, otherwise null

Category classification (always required):
- "personal": Personal life, family, friends, hobbies, health, home, errands, personal finance, self-improvement
- "business": Work, clients, projects, meetings, professional tasks, company matters, business communications

Today's date is: ${getTodayDate()}

Output ONLY valid JSON with no additional text. Use this exact schema:
{
  "type": "thought" | "task_create" | "task_update",
  "category": "personal" | "business",
  "thought": { "text": "the original thought text" },
  "task_create": { "title": "imperative task title", "due_date": "YYYY-MM-DD or null" },
  "task_update": { "operation": "complete|cancel|postpone|set_due_date", "target_hint": "phrase to match task", "new_due_date": "YYYY-MM-DD or null" }
}

Only include the relevant field based on type (thought, task_create, or task_update). Always include category.

Transcript: "${transcript}"`;
}

export async function classifyTranscript(transcript: string): Promise<ClassificationResult> {
  const response = await openai.chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [
      {
        role: 'user',
        content: buildPrompt(transcript),
      },
    ],
    response_format: { type: 'json_object' },
    temperature: 0.1,
  });

  const content = response.choices[0]?.message?.content;
  if (!content) {
    throw new Error('No response from classification model');
  }

  const result = JSON.parse(content) as ClassificationResult;

  // Validate the result structure
  if (!result.type || !['thought', 'task_create', 'task_update'].includes(result.type)) {
    throw new Error(`Invalid classification type: ${result.type}`);
  }

  return result;
}
