import Database from 'better-sqlite3';
import { mkdirSync, existsSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const dbPath = process.env.DATABASE_PATH || join(__dirname, 'data', 'grump.db');

let db;

export function getDb() {
  if (!db) {
    const dataDir = dirname(dbPath);
    if (!existsSync(dataDir)) mkdirSync(dataDir, { recursive: true });
    db = new Database(dbPath);
    db.pragma('journal_mode = WAL');
    initSchema(db);
  }
  return db;
}

function initSchema(database) {
  let needsMigration = false;
  try {
    const columns = database.prepare("PRAGMA table_info(users)").all();
    const hasGoogleId = columns.some(c => c.name === 'google_id');
    needsMigration = columns.length > 0 && !hasGoogleId;
  } catch {
    needsMigration = true;
  }

  if (needsMigration) {
    database.exec(`DROP TABLE IF EXISTS users`);
  }

  database.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      google_id TEXT UNIQUE NOT NULL,
      email TEXT NOT NULL,
      tier TEXT NOT NULL DEFAULT 'free',
      credits_balance INTEGER NOT NULL DEFAULT 0,
      credits_replenished_at INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    CREATE UNIQUE INDEX IF NOT EXISTS idx_users_google_id ON users(google_id);
  `);

  database.exec(`
    CREATE TABLE IF NOT EXISTS usage_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT NOT NULL,
      model TEXT,
      prompt_tokens INTEGER,
      completion_tokens INTEGER,
      credits_deducted INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      FOREIGN KEY (user_id) REFERENCES users(id)
    );
    CREATE INDEX IF NOT EXISTS idx_usage_log_user ON usage_log(user_id);
  `);

  migrateProfileColumns(database);
}

function migrateProfileColumns(database) {
  const columns = database.prepare("PRAGMA table_info(users)").all();
  const names = new Set(columns.map(c => c.name));
  if (!names.has('display_name')) {
    database.exec('ALTER TABLE users ADD COLUMN display_name TEXT');
  }
  if (!names.has('avatar_url')) {
    database.exec('ALTER TABLE users ADD COLUMN avatar_url TEXT');
  }
}

export const TIERS = {
  free:    { name: 'Free',    creditsPerMonth: 500,   models: ['free'] },
  starter: { name: 'Starter', creditsPerMonth: 2000,  models: ['free', 'fast'] },
  pro:     { name: 'Pro',     creditsPerMonth: 5000,  models: ['free', 'fast', 'frontier'] },
  team:    { name: 'Team',    creditsPerMonth: 25000, models: ['free', 'fast', 'frontier'] },
};

/** Credits per 1K tokens by model tier (frontier costs more) */
export const CREDITS_PER_1K_TOKENS = 1;
export const CREDITS_PER_1K_BY_MODEL_TIER = {
  free: 0,
  fast: 1,
  frontier: 3,
};
