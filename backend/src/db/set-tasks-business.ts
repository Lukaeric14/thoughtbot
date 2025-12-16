import { pool } from './client.js';
import { validateConfig } from '../config.js';

async function setCategoryForExistingData() {
  validateConfig();

  try {
    // Set all tasks without a category to 'business'
    const tasksResult = await pool.query(`
      UPDATE tasks
      SET category = 'business'
      WHERE category IS NULL
    `);
    console.log(`Updated ${tasksResult.rowCount} tasks to category 'business'`);

    // Set all thoughts without a category to 'personal'
    const thoughtsResult = await pool.query(`
      UPDATE thoughts
      SET category = 'personal'
      WHERE category IS NULL
    `);
    console.log(`Updated ${thoughtsResult.rowCount} thoughts to category 'personal'`);

    // Show current counts
    const taskCounts = await pool.query(`
      SELECT category, COUNT(*) as count FROM tasks GROUP BY category
    `);
    console.log('\nTask counts by category:');
    for (const row of taskCounts.rows) {
      console.log(`  ${row.category}: ${row.count}`);
    }

    const thoughtCounts = await pool.query(`
      SELECT category, COUNT(*) as count FROM thoughts GROUP BY category
    `);
    console.log('\nThought counts by category:');
    for (const row of thoughtCounts.rows) {
      console.log(`  ${row.category}: ${row.count}`);
    }
  } catch (error) {
    console.error('Migration failed:', error);
    process.exit(1);
  } finally {
    await pool.end();
  }
}

setCategoryForExistingData();
