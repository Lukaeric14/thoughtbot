import { openai } from './openaiClient.js';
import { query } from '../db/client.js';
import type { Task, Thought, Category } from '../types/index.js';

interface MatchResult {
  matched_id: string | null;
  confidence: number;
  reason?: string;
}

/**
 * Use OpenAI to find a semantically matching active task
 * Checks ALL active tasks regardless of category to prevent duplicates
 */
export async function findSemanticTaskMatch(
  newTitle: string,
  category: Category
): Promise<Task | null> {
  // Get active tasks across ALL categories to catch duplicates
  const activeTasks = await query<Task>(
    `SELECT * FROM tasks
     WHERE status = 'open'
     ORDER BY mention_count DESC, created_at DESC
     LIMIT 30`,
    []
  );

  if (activeTasks.length === 0) {
    return null;
  }

  // Build a prompt for OpenAI to find semantic matches
  const taskList = activeTasks.map((t, i) => `${i + 1}. "${t.title}" (id: ${t.id})`).join('\n');

  const response = await openai.chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [
      {
        role: 'user',
        content: `You are checking if a new task/reminder is semantically the same as an existing one.

New input: "${newTitle}"

Existing active tasks:
${taskList}

Does the new input refer to the SAME task/commitment as any existing task? Consider:
- Different phrasings of the same action (e.g., "email John" = "send email to John")
- Follow-ups or reminders about the same thing (e.g., "don't forget to call mom" = "call mom")
- Variations in wording that mean the same action

Reply with ONLY valid JSON:
{
  "matched_id": "the id of the matching task, or null if no match",
  "confidence": 0.0 to 1.0,
  "reason": "brief explanation"
}

Only match if confidence >= 0.7. If unsure, return null.`,
      },
    ],
    response_format: { type: 'json_object' },
    temperature: 0.1,
  });

  const content = response.choices[0]?.message?.content;
  if (!content) {
    return null;
  }

  try {
    const result = JSON.parse(content) as MatchResult;
    console.log(`Semantic matcher response for "${newTitle}":`, result);

    if (result.matched_id && result.confidence >= 0.5) {
      const matchedTask = activeTasks.find(t => t.id === result.matched_id);
      if (matchedTask) {
        console.log(`Semantic match found: "${newTitle}" matches "${matchedTask.title}" (confidence: ${result.confidence}, reason: ${result.reason})`);
        return matchedTask;
      }
    } else {
      console.log(`No semantic match for "${newTitle}" (confidence: ${result.confidence})`);
    }
  } catch (error) {
    console.error('Error parsing semantic match result:', error, 'content:', content);
  }

  return null;
}

/**
 * Use OpenAI to find a semantically matching active thought
 * Checks ALL thoughts regardless of category to prevent duplicates
 */
export async function findSemanticThoughtMatch(
  newText: string,
  category: Category
): Promise<Thought | null> {
  // Get recent thoughts across ALL categories to catch duplicates
  const activeThoughts = await query<Thought>(
    `SELECT * FROM thoughts
     ORDER BY mention_count DESC, created_at DESC
     LIMIT 30`,
    []
  );

  if (activeThoughts.length === 0) {
    return null;
  }

  // Build a prompt for OpenAI to find semantic matches
  const thoughtList = activeThoughts.map((t, i) => `${i + 1}. "${t.text}" (id: ${t.id})`).join('\n');

  const response = await openai.chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [
      {
        role: 'user',
        content: `You are checking if a new thought/idea is semantically the same as an existing one.

New input: "${newText}"

Existing thoughts:
${thoughtList}

Does the new input express the SAME thought/idea/reflection as any existing thought? Consider:
- Different phrasings of the same idea
- Elaborations or restatements of the same thought
- The user expressing the same concern/reflection again

Reply with ONLY valid JSON:
{
  "matched_id": "the id of the matching thought, or null if no match",
  "confidence": 0.0 to 1.0,
  "reason": "brief explanation"
}

Only match if confidence >= 0.7. If unsure, return null.`,
      },
    ],
    response_format: { type: 'json_object' },
    temperature: 0.1,
  });

  const content = response.choices[0]?.message?.content;
  if (!content) {
    return null;
  }

  try {
    const result = JSON.parse(content) as MatchResult;
    console.log(`Semantic matcher response for "${newText}":`, result);

    if (result.matched_id && result.confidence >= 0.5) {
      const matchedThought = activeThoughts.find(t => t.id === result.matched_id);
      if (matchedThought) {
        console.log(`Semantic match found: "${newText}" matches "${matchedThought.text}" (confidence: ${result.confidence}, reason: ${result.reason})`);
        return matchedThought;
      }
    } else {
      console.log(`No semantic match for "${newText}" (confidence: ${result.confidence})`);
    }
  } catch (error) {
    console.error('Error parsing semantic match result:', error, 'content:', content);
  }

  return null;
}
