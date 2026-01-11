import { query } from './client.js';
import dotenv from 'dotenv';

dotenv.config();

async function seed() {
  console.log('Seeding database...');

  // Personal thoughts
  await query(`
    INSERT INTO thoughts (text, canonical_text, category, mention_count)
    VALUES 
      ('Maybe I should start meditating in the mornings', 'maybe i should start meditating in the mornings', 'personal', 1),
      ('I wonder if the gym is open on weekends', 'i wonder if the gym is open on weekends', 'personal', 1),
      ('Should look into that new coffee shop downtown', 'should look into that new coffee shop downtown', 'personal', 1)
    ON CONFLICT DO NOTHING
  `, []);

  // Business thoughts
  await query(`
    INSERT INTO thoughts (text, canonical_text, category, mention_count)
    VALUES 
      ('We could improve the onboarding flow', 'we could improve the onboarding flow', 'business', 1),
      ('Might be worth exploring a mobile app', 'might be worth exploring a mobile app', 'business', 1),
      ('The API response times seem slow lately', 'the api response times seem slow lately', 'business', 1)
    ON CONFLICT DO NOTHING
  `, []);

  // Personal tasks
  await query(`
    INSERT INTO tasks (title, canonical_title, category, status, due_date, mention_count)
    VALUES 
      ('Buy groceries', 'buy groceries', 'personal', 'open', CURRENT_DATE, 1),
      ('Call mom', 'call mom', 'personal', 'open', CURRENT_DATE + 1, 1),
      ('Schedule dentist appointment', 'schedule dentist appointment', 'personal', 'open', CURRENT_DATE + 3, 1)
    ON CONFLICT DO NOTHING
  `, []);

  // Business tasks
  await query(`
    INSERT INTO tasks (title, canonical_title, category, status, due_date, mention_count)
    VALUES 
      ('Review pull request', 'review pull request', 'business', 'open', CURRENT_DATE, 1),
      ('Send weekly report', 'send weekly report', 'business', 'open', CURRENT_DATE, 1),
      ('Update project roadmap', 'update project roadmap', 'business', 'open', CURRENT_DATE + 2, 1)
    ON CONFLICT DO NOTHING
  `, []);

  console.log('Seeding complete!');
  process.exit(0);
}

seed().catch((err) => {
  console.error('Seed error:', err);
  process.exit(1);
});
