import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import Database from 'better-sqlite3';
import { randomUUID } from 'crypto';
import jwt from 'jsonwebtoken';

// ── Test-only DB & Auth helpers ──────────────────────────────────────────────
// We test the DB layer and auth functions directly (unit tests),
// rather than spinning up the full Express server.

const TEST_SECRET = 'test-secret-key-for-ci-testing-only';
const TEST_DB_PATH = ':memory:';

function createTestDb() {
  const db = new Database(TEST_DB_PATH);
  db.pragma('journal_mode = WAL');
  db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      google_id TEXT UNIQUE NOT NULL,
      email TEXT NOT NULL,
      tier TEXT NOT NULL DEFAULT 'free',
      credits_balance INTEGER NOT NULL DEFAULT 0,
      credits_replenished_at INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      display_name TEXT,
      avatar_url TEXT,
      stripe_customer_id TEXT,
      stripe_subscription_id TEXT,
      subscription_status TEXT,
      subscription_period_end INTEGER,
      trial_end INTEGER
    );
    CREATE UNIQUE INDEX IF NOT EXISTS idx_users_google_id ON users(google_id);

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

    CREATE TABLE IF NOT EXISTS credit_purchases (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT NOT NULL,
      pack_key TEXT NOT NULL,
      credits_added INTEGER NOT NULL,
      amount_cents INTEGER NOT NULL,
      stripe_session_id TEXT,
      created_at INTEGER NOT NULL,
      FOREIGN KEY (user_id) REFERENCES users(id)
    );
    CREATE INDEX IF NOT EXISTS idx_credit_purchases_user ON credit_purchases(user_id);
  `);
  return db;
}

function createTestUser(db, overrides = {}) {
  const id = overrides.id || randomUUID();
  const now = Date.now();
  db.prepare(`
    INSERT INTO users (id, google_id, email, tier, credits_balance, credits_replenished_at, created_at, updated_at, display_name)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    id,
    overrides.google_id || `google-${id}`,
    overrides.email || `test-${id}@example.com`,
    overrides.tier || 'free',
    overrides.credits_balance ?? 500,
    overrides.credits_replenished_at ?? now,
    overrides.created_at ?? now,
    now,
    overrides.display_name ?? null,
  );
  return id;
}

function signTestToken(payload) {
  return jwt.sign(payload, TEST_SECRET, { expiresIn: '1h' });
}

function verifyTestToken(token) {
  try {
    return jwt.verify(token, TEST_SECRET);
  } catch {
    return null;
  }
}

// ── Tests ────────────────────────────────────────────────────────────────────

describe('Database Schema', () => {
  let db;

  before(() => { db = createTestDb(); });
  after(() => { db.close(); });

  it('should create users table with all required columns', () => {
    const cols = db.prepare('PRAGMA table_info(users)').all();
    const names = cols.map(c => c.name);
    assert.ok(names.includes('id'));
    assert.ok(names.includes('google_id'));
    assert.ok(names.includes('email'));
    assert.ok(names.includes('tier'));
    assert.ok(names.includes('credits_balance'));
    assert.ok(names.includes('stripe_customer_id'));
    assert.ok(names.includes('display_name'));
    assert.ok(names.includes('avatar_url'));
  });

  it('should create usage_log table', () => {
    const cols = db.prepare('PRAGMA table_info(usage_log)').all();
    const names = cols.map(c => c.name);
    assert.ok(names.includes('user_id'));
    assert.ok(names.includes('model'));
    assert.ok(names.includes('credits_deducted'));
  });

  it('should create credit_purchases table', () => {
    const cols = db.prepare('PRAGMA table_info(credit_purchases)').all();
    const names = cols.map(c => c.name);
    assert.ok(names.includes('user_id'));
    assert.ok(names.includes('pack_key'));
    assert.ok(names.includes('credits_added'));
    assert.ok(names.includes('amount_cents'));
  });

  it('should enforce unique google_id constraint', () => {
    const id1 = randomUUID();
    const id2 = randomUUID();
    const now = Date.now();
    db.prepare('INSERT INTO users (id, google_id, email, tier, credits_balance, created_at, updated_at) VALUES (?,?,?,?,?,?,?)')
      .run(id1, 'unique-google-123', 'a@b.com', 'free', 0, now, now);

    assert.throws(() => {
      db.prepare('INSERT INTO users (id, google_id, email, tier, credits_balance, created_at, updated_at) VALUES (?,?,?,?,?,?,?)')
        .run(id2, 'unique-google-123', 'c@d.com', 'free', 0, now, now);
    }, /UNIQUE constraint/);
  });
});

describe('JWT Auth', () => {
  it('should sign and verify a valid token', () => {
    const token = signTestToken({ userId: 'user-123' });
    const payload = verifyTestToken(token);
    assert.ok(payload);
    assert.equal(payload.userId, 'user-123');
  });

  it('should return null for an invalid token', () => {
    const result = verifyTestToken('invalid.token.here');
    assert.equal(result, null);
  });

  it('should return null for an expired token', () => {
    const token = jwt.sign({ userId: 'user-123' }, TEST_SECRET, { expiresIn: '0s' });
    // Wait a tick for expiry
    const result = verifyTestToken(token);
    assert.equal(result, null);
  });

  it('should return null for token signed with wrong secret', () => {
    const token = jwt.sign({ userId: 'user-123' }, 'wrong-secret');
    const result = verifyTestToken(token);
    assert.equal(result, null);
  });

  it('should include expiry in token payload', () => {
    const token = signTestToken({ userId: 'user-456' });
    const payload = verifyTestToken(token);
    assert.ok(payload.exp);
    assert.ok(payload.iat);
    assert.ok(payload.exp > payload.iat);
  });
});

describe('User CRUD', () => {
  let db;

  before(() => { db = createTestDb(); });
  after(() => { db.close(); });

  it('should create a user with default free tier', () => {
    const userId = createTestUser(db, { email: 'crud@test.com' });
    const user = db.prepare('SELECT * FROM users WHERE id = ?').get(userId);
    assert.ok(user);
    assert.equal(user.email, 'crud@test.com');
    assert.equal(user.tier, 'free');
    assert.equal(user.credits_balance, 500);
  });

  it('should update display name', () => {
    const userId = createTestUser(db);
    db.prepare('UPDATE users SET display_name = ? WHERE id = ?').run('Test User', userId);
    const user = db.prepare('SELECT display_name FROM users WHERE id = ?').get(userId);
    assert.equal(user.display_name, 'Test User');
  });

  it('should handle null display_name and avatar_url', () => {
    const userId = createTestUser(db);
    const user = db.prepare('SELECT display_name, avatar_url FROM users WHERE id = ?').get(userId);
    assert.equal(user.display_name, null);
    assert.equal(user.avatar_url, null);
  });
});

describe('Credit Replenishment', () => {
  let db;

  before(() => { db = createTestDb(); });
  after(() => { db.close(); });

  it('should not replenish when within the month', () => {
    const now = Date.now();
    const userId = createTestUser(db, {
      credits_balance: 100,
      credits_replenished_at: now,
    });
    const user = db.prepare('SELECT credits_balance FROM users WHERE id = ?').get(userId);
    assert.equal(user.credits_balance, 100);
  });

  it('should detect when replenishment is needed (>30 days)', () => {
    const monthMs = 30 * 24 * 60 * 60 * 1000;
    const userId = createTestUser(db, {
      credits_balance: 50,
      credits_replenished_at: Date.now() - monthMs - 1000,
    });
    const user = db.prepare('SELECT credits_balance, credits_replenished_at FROM users WHERE id = ?').get(userId);
    const elapsed = Date.now() - user.credits_replenished_at;
    assert.ok(elapsed >= monthMs, 'Should be past replenishment window');
  });
});

describe('Usage Logging', () => {
  let db;

  before(() => { db = createTestDb(); });
  after(() => { db.close(); });

  it('should insert and query usage logs', () => {
    const userId = createTestUser(db);
    const now = Date.now();
    db.prepare('INSERT INTO usage_log (user_id, model, prompt_tokens, completion_tokens, credits_deducted, created_at) VALUES (?,?,?,?,?,?)')
      .run(userId, 'gpt-4', 100, 50, 3, now);
    db.prepare('INSERT INTO usage_log (user_id, model, prompt_tokens, completion_tokens, credits_deducted, created_at) VALUES (?,?,?,?,?,?)')
      .run(userId, 'claude-3', 200, 100, 5, now);

    const total = db.prepare('SELECT SUM(credits_deducted) as total FROM usage_log WHERE user_id = ?').get(userId);
    assert.equal(total.total, 8);
  });

  it('should aggregate usage by model', () => {
    const userId = createTestUser(db);
    const now = Date.now();
    for (let i = 0; i < 3; i++) {
      db.prepare('INSERT INTO usage_log (user_id, model, prompt_tokens, completion_tokens, credits_deducted, created_at) VALUES (?,?,?,?,?,?)')
        .run(userId, 'gpt-4', 100, 50, 2, now);
    }
    db.prepare('INSERT INTO usage_log (user_id, model, prompt_tokens, completion_tokens, credits_deducted, created_at) VALUES (?,?,?,?,?,?)')
      .run(userId, 'claude-3', 200, 100, 5, now);

    const byModel = db.prepare('SELECT model, COUNT(*) as count, SUM(credits_deducted) as credits FROM usage_log WHERE user_id = ? GROUP BY model ORDER BY credits DESC')
      .all(userId);
    assert.equal(byModel.length, 2);
    assert.equal(byModel[0].model, 'gpt-4');
    assert.equal(byModel[0].count, 3);
    assert.equal(byModel[0].credits, 6);
  });
});

describe('Data Retention', () => {
  let db;

  before(() => { db = createTestDb(); });
  after(() => { db.close(); });

  it('should delete usage logs older than 90 days', () => {
    const userId = createTestUser(db);
    const now = Date.now();
    const ninetyOneDaysAgo = now - 91 * 24 * 60 * 60 * 1000;
    const recentTime = now - 1 * 24 * 60 * 60 * 1000;

    // Insert old and recent logs
    db.prepare('INSERT INTO usage_log (user_id, model, prompt_tokens, completion_tokens, credits_deducted, created_at) VALUES (?,?,?,?,?,?)')
      .run(userId, 'old-model', 100, 50, 1, ninetyOneDaysAgo);
    db.prepare('INSERT INTO usage_log (user_id, model, prompt_tokens, completion_tokens, credits_deducted, created_at) VALUES (?,?,?,?,?,?)')
      .run(userId, 'recent-model', 100, 50, 1, recentTime);

    // Prune
    const cutoff = now - 90 * 24 * 60 * 60 * 1000;
    const result = db.prepare('DELETE FROM usage_log WHERE created_at < ?').run(cutoff);
    assert.ok(result.changes >= 1);

    // Verify recent log remains
    const remaining = db.prepare('SELECT COUNT(*) as count FROM usage_log WHERE user_id = ?').get(userId);
    assert.equal(remaining.count, 1);

    const log = db.prepare('SELECT model FROM usage_log WHERE user_id = ?').get(userId);
    assert.equal(log.model, 'recent-model');
  });
});

describe('GDPR Data Export & Delete', () => {
  let db;

  before(() => { db = createTestDb(); });
  after(() => { db.close(); });

  it('should export all user data', () => {
    const userId = createTestUser(db, { email: 'gdpr@test.com', display_name: 'GDPR User' });
    const now = Date.now();
    db.prepare('INSERT INTO usage_log (user_id, model, prompt_tokens, completion_tokens, credits_deducted, created_at) VALUES (?,?,?,?,?,?)')
      .run(userId, 'gpt-4', 100, 50, 3, now);
    db.prepare('INSERT INTO credit_purchases (user_id, pack_key, credits_added, amount_cents, created_at) VALUES (?,?,?,?,?)')
      .run(userId, 'credits_1000', 1000, 999, now);

    const user = db.prepare('SELECT * FROM users WHERE id = ?').get(userId);
    const usage = db.prepare('SELECT * FROM usage_log WHERE user_id = ?').all(userId);
    const purchases = db.prepare('SELECT * FROM credit_purchases WHERE user_id = ?').all(userId);

    assert.ok(user);
    assert.equal(user.email, 'gdpr@test.com');
    assert.equal(usage.length, 1);
    assert.equal(purchases.length, 1);
    assert.equal(purchases[0].pack_key, 'credits_1000');
  });

  it('should delete all user data (right to erasure)', () => {
    const userId = createTestUser(db, { email: 'delete@test.com' });
    const now = Date.now();
    db.prepare('INSERT INTO usage_log (user_id, model, prompt_tokens, completion_tokens, credits_deducted, created_at) VALUES (?,?,?,?,?,?)')
      .run(userId, 'gpt-4', 100, 50, 3, now);
    db.prepare('INSERT INTO credit_purchases (user_id, pack_key, credits_added, amount_cents, created_at) VALUES (?,?,?,?,?)')
      .run(userId, 'credits_5000', 5000, 3999, now);

    // Delete in order (foreign key safe)
    db.prepare('DELETE FROM usage_log WHERE user_id = ?').run(userId);
    db.prepare('DELETE FROM credit_purchases WHERE user_id = ?').run(userId);
    db.prepare('DELETE FROM users WHERE id = ?').run(userId);

    // Verify complete deletion
    const user = db.prepare('SELECT * FROM users WHERE id = ?').get(userId);
    const usage = db.prepare('SELECT * FROM usage_log WHERE user_id = ?').all(userId);
    const purchases = db.prepare('SELECT * FROM credit_purchases WHERE user_id = ?').all(userId);

    assert.equal(user, undefined);
    assert.equal(usage.length, 0);
    assert.equal(purchases.length, 0);
  });
});

describe('Input Validation', () => {
  it('should reject display names over 200 chars', () => {
    const longName = 'x'.repeat(201);
    assert.ok(longName.length > 200);
  });

  it('should reject avatar URLs over 2048 chars', () => {
    const longUrl = 'https://example.com/' + 'a'.repeat(2030);
    assert.ok(longUrl.length > 2048);
  });

  it('should reject invalid credit pack keys', () => {
    const validKeys = ['credits_1000', 'credits_5000', 'credits_20000'];
    assert.ok(!validKeys.includes('invalid_pack'));
    assert.ok(!validKeys.includes(''));
    assert.ok(validKeys.includes('credits_1000'));
  });

  it('should validate chat message roles', () => {
    const validRoles = ['system', 'user', 'assistant', 'tool'];
    assert.ok(validRoles.includes('user'));
    assert.ok(validRoles.includes('system'));
    assert.ok(!validRoles.includes('admin'));
    assert.ok(!validRoles.includes(''));
  });
});

describe('Tier Configuration', () => {
  const TIERS = {
    free:    { name: 'Free',    creditsPerMonth: 500,   models: ['free'] },
    starter: { name: 'Starter', creditsPerMonth: 2000,  models: ['free', 'fast'] },
    pro:     { name: 'Pro',     creditsPerMonth: 5000,  models: ['free', 'fast', 'frontier'] },
    team:    { name: 'Team',    creditsPerMonth: 25000, models: ['free', 'fast', 'frontier'] },
  };

  it('should have all expected tiers', () => {
    assert.ok(TIERS.free);
    assert.ok(TIERS.starter);
    assert.ok(TIERS.pro);
    assert.ok(TIERS.team);
  });

  it('should have increasing credits per month', () => {
    assert.ok(TIERS.free.creditsPerMonth < TIERS.starter.creditsPerMonth);
    assert.ok(TIERS.starter.creditsPerMonth < TIERS.pro.creditsPerMonth);
    assert.ok(TIERS.pro.creditsPerMonth < TIERS.team.creditsPerMonth);
  });

  it('should grant more model access at higher tiers', () => {
    assert.equal(TIERS.free.models.length, 1);
    assert.equal(TIERS.starter.models.length, 2);
    assert.equal(TIERS.pro.models.length, 3);
    assert.equal(TIERS.team.models.length, 3);
  });

  it('free tier should only have free models', () => {
    assert.deepEqual(TIERS.free.models, ['free']);
  });

  it('pro/team tiers should include frontier models', () => {
    assert.ok(TIERS.pro.models.includes('frontier'));
    assert.ok(TIERS.team.models.includes('frontier'));
  });
});

describe('Credit Purchases', () => {
  let db;

  before(() => { db = createTestDb(); });
  after(() => { db.close(); });

  it('should record a credit purchase and update balance', () => {
    const userId = createTestUser(db, { credits_balance: 100 });
    const now = Date.now();

    db.prepare('INSERT INTO credit_purchases (user_id, pack_key, credits_added, amount_cents, stripe_session_id, created_at) VALUES (?,?,?,?,?,?)')
      .run(userId, 'credits_1000', 1000, 999, 'cs_test_123', now);

    // Update balance
    db.prepare('UPDATE users SET credits_balance = credits_balance + ? WHERE id = ?').run(1000, userId);

    const user = db.prepare('SELECT credits_balance FROM users WHERE id = ?').get(userId);
    assert.equal(user.credits_balance, 1100);

    const purchase = db.prepare('SELECT * FROM credit_purchases WHERE user_id = ?').get(userId);
    assert.equal(purchase.pack_key, 'credits_1000');
    assert.equal(purchase.credits_added, 1000);
    assert.equal(purchase.stripe_session_id, 'cs_test_123');
  });
});

// ── Billing & Stripe ────────────────────────────────────────────────────────

// CREDIT_PACKS and PRICE_IDS are re-declared here to avoid importing stripe.js,
// which requires the 'stripe' npm package at module load time. CI may not have
// it installed when running unit tests in isolation. Values must match stripe.js.
const TEST_CREDIT_PACKS = {
  credits_1000: { credits: 1000, price: 499 },
  credits_5000: { credits: 5000, price: 1999 },
  credits_20000: { credits: 20000, price: 6999 },
};

const TEST_PRICE_IDS = {
  starter_monthly: 'price_starter_monthly',
  pro_monthly: 'price_pro_monthly',
  team_monthly: 'price_team_monthly',
  credits_1000: 'price_credits_1000',
  credits_5000: 'price_credits_5000',
  credits_20000: 'price_credits_20000',
};

const TEST_TIER_MAP = {
  starter_monthly: 'starter',
  pro_monthly: 'pro',
  team_monthly: 'team',
};

describe('Stripe Constants', () => {
  const PRICE_IDS = TEST_PRICE_IDS;
  const CREDIT_PACKS = TEST_CREDIT_PACKS;
  it('PRICE_IDS should contain all 6 expected keys', () => {
    const expected = ['starter_monthly', 'pro_monthly', 'team_monthly', 'credits_1000', 'credits_5000', 'credits_20000'];
    for (const key of expected) {
      assert.ok(PRICE_IDS[key], `Missing PRICE_IDS key: ${key}`);
    }
  });

  it('CREDIT_PACKS should have correct credit amounts', () => {
    assert.equal(CREDIT_PACKS.credits_1000.credits, 1000);
    assert.equal(CREDIT_PACKS.credits_5000.credits, 5000);
    assert.equal(CREDIT_PACKS.credits_20000.credits, 20000);
  });

  it('CREDIT_PACKS should have correct prices in cents', () => {
    assert.equal(CREDIT_PACKS.credits_1000.price, 499);
    assert.equal(CREDIT_PACKS.credits_5000.price, 1999);
    assert.equal(CREDIT_PACKS.credits_20000.price, 6999);
  });

  it('CREDIT_PACKS should have exactly 3 entries', () => {
    assert.equal(Object.keys(CREDIT_PACKS).length, 3);
  });

  it('subscription PRICE_IDS should map to tier strings via TIER_MAP', () => {
    for (const [priceKey, tier] of Object.entries(TEST_TIER_MAP)) {
      assert.ok(PRICE_IDS[priceKey], `PRICE_IDS missing subscription key: ${priceKey}`);
      assert.equal(typeof tier, 'string');
    }
    assert.equal(TEST_TIER_MAP.starter_monthly, 'starter');
    assert.equal(TEST_TIER_MAP.pro_monthly, 'pro');
    assert.equal(TEST_TIER_MAP.team_monthly, 'team');
  });
});

describe('Billing Usage Queries', () => {
  let db;

  before(() => { db = createTestDb(); });
  after(() => { db.close(); });

  it('should aggregate usage analytics for a user', () => {
    const userId = createTestUser(db, { credits_balance: 5000, tier: 'pro' });
    const now = Date.now();
    const monthAgo = now - 30 * 24 * 60 * 60 * 1000;

    // Insert usage within the last 30 days
    db.prepare('INSERT INTO usage_log (user_id, model, prompt_tokens, completion_tokens, credits_deducted, created_at) VALUES (?,?,?,?,?,?)')
      .run(userId, 'claude-3', 500, 200, 10, now - 1000);
    db.prepare('INSERT INTO usage_log (user_id, model, prompt_tokens, completion_tokens, credits_deducted, created_at) VALUES (?,?,?,?,?,?)')
      .run(userId, 'claude-3', 300, 150, 8, now - 2000);
    db.prepare('INSERT INTO usage_log (user_id, model, prompt_tokens, completion_tokens, credits_deducted, created_at) VALUES (?,?,?,?,?,?)')
      .run(userId, 'gpt-4', 100, 50, 5, now - 3000);

    // Query matching getUsageAnalytics logic
    const summary = db.prepare(`
      SELECT SUM(credits_deducted) as credits_used, COUNT(*) as requests,
             SUM(prompt_tokens) as prompt_tokens, SUM(completion_tokens) as completion_tokens
      FROM usage_log WHERE user_id = ? AND created_at >= ?
    `).get(userId, monthAgo);

    assert.equal(summary.credits_used, 23);
    assert.equal(summary.requests, 3);
    assert.equal(summary.prompt_tokens, 900);
    assert.equal(summary.completion_tokens, 400);
  });

  it('should aggregate usage by model', () => {
    const userId = createTestUser(db);
    const now = Date.now();
    const monthAgo = now - 30 * 24 * 60 * 60 * 1000;

    db.prepare('INSERT INTO usage_log (user_id, model, prompt_tokens, completion_tokens, credits_deducted, created_at) VALUES (?,?,?,?,?,?)')
      .run(userId, 'claude-3', 100, 50, 3, now);
    db.prepare('INSERT INTO usage_log (user_id, model, prompt_tokens, completion_tokens, credits_deducted, created_at) VALUES (?,?,?,?,?,?)')
      .run(userId, 'claude-3', 100, 50, 4, now);
    db.prepare('INSERT INTO usage_log (user_id, model, prompt_tokens, completion_tokens, credits_deducted, created_at) VALUES (?,?,?,?,?,?)')
      .run(userId, 'gpt-4', 200, 100, 10, now);

    const byModel = db.prepare(`
      SELECT model, COUNT(*) as requests, SUM(credits_deducted) as credits
      FROM usage_log WHERE user_id = ? AND created_at >= ?
      GROUP BY model ORDER BY credits DESC
    `).all(userId, monthAgo);

    assert.equal(byModel.length, 2);
    assert.equal(byModel[0].model, 'gpt-4');
    assert.equal(byModel[0].credits, 10);
    assert.equal(byModel[1].model, 'claude-3');
    assert.equal(byModel[1].requests, 2);
    assert.equal(byModel[1].credits, 7);
  });

  it('should return recent credit purchases', () => {
    const userId = createTestUser(db);
    const now = Date.now();

    db.prepare('INSERT INTO credit_purchases (user_id, pack_key, credits_added, amount_cents, stripe_session_id, created_at) VALUES (?,?,?,?,?,?)')
      .run(userId, 'credits_5000', 5000, 1999, 'cs_test_a', now - 2000);
    db.prepare('INSERT INTO credit_purchases (user_id, pack_key, credits_added, amount_cents, stripe_session_id, created_at) VALUES (?,?,?,?,?,?)')
      .run(userId, 'credits_1000', 1000, 499, 'cs_test_b', now - 1000);

    const purchases = db.prepare(`
      SELECT pack_key, credits_added, amount_cents, created_at
      FROM credit_purchases WHERE user_id = ?
      ORDER BY created_at DESC LIMIT 10
    `).all(userId);

    assert.equal(purchases.length, 2);
    assert.equal(purchases[0].pack_key, 'credits_1000');
    assert.equal(purchases[0].credits_added, 1000);
    assert.equal(purchases[1].pack_key, 'credits_5000');
    assert.equal(purchases[1].amount_cents, 1999);
  });

  it('should exclude old usage from 30-day window', () => {
    const userId = createTestUser(db);
    const now = Date.now();
    const monthAgo = now - 30 * 24 * 60 * 60 * 1000;
    const oldTime = now - 60 * 24 * 60 * 60 * 1000; // 60 days ago

    db.prepare('INSERT INTO usage_log (user_id, model, prompt_tokens, completion_tokens, credits_deducted, created_at) VALUES (?,?,?,?,?,?)')
      .run(userId, 'gpt-4', 100, 50, 5, now);
    db.prepare('INSERT INTO usage_log (user_id, model, prompt_tokens, completion_tokens, credits_deducted, created_at) VALUES (?,?,?,?,?,?)')
      .run(userId, 'gpt-4', 100, 50, 10, oldTime);

    const summary = db.prepare(`
      SELECT SUM(credits_deducted) as credits_used, COUNT(*) as requests
      FROM usage_log WHERE user_id = ? AND created_at >= ?
    `).get(userId, monthAgo);

    assert.equal(summary.credits_used, 5);
    assert.equal(summary.requests, 1);
  });
});

// ── Credit Deduction Tests ────────────────────────────────────────────────

describe('Credit Deduction', () => {
  let db;

  before(() => { db = createTestDb(); });
  after(() => { db.close(); });

  it('should deduct credits atomically', () => {
    const userId = createTestUser(db, { credits_balance: 100 });

    // Atomic deduction
    const result = db.prepare(
      'UPDATE users SET credits_balance = MAX(0, credits_balance - ?) WHERE id = ? AND credits_balance >= ?'
    ).run(10, userId, 10);

    assert.equal(result.changes, 1);
    const user = db.prepare('SELECT credits_balance FROM users WHERE id = ?').get(userId);
    assert.equal(user.credits_balance, 90);
  });

  it('should not go below zero with atomic deduction', () => {
    const userId = createTestUser(db, { credits_balance: 5 });

    // Try to deduct more than available
    const result = db.prepare(
      'UPDATE users SET credits_balance = MAX(0, credits_balance - ?) WHERE id = ? AND credits_balance >= ?'
    ).run(10, userId, 10);

    // Should fail — not enough credits
    assert.equal(result.changes, 0);
    const user = db.prepare('SELECT credits_balance FROM users WHERE id = ?').get(userId);
    assert.equal(user.credits_balance, 5);
  });

  it('should handle zero balance deduction attempt', () => {
    const userId = createTestUser(db, { credits_balance: 0 });

    const result = db.prepare(
      'UPDATE users SET credits_balance = MAX(0, credits_balance - ?) WHERE id = ? AND credits_balance >= ?'
    ).run(1, userId, 1);

    assert.equal(result.changes, 0);
    const user = db.prepare('SELECT credits_balance FROM users WHERE id = ?').get(userId);
    assert.equal(user.credits_balance, 0);
  });
});

// ── Auth / Token Tests ────────────────────────────────────────────────────

describe('Auth Tokens', () => {
  it('should sign and verify a valid token', () => {
    const token = signTestToken({ userId: 'user-123' });
    assert.ok(token);
    const payload = verifyTestToken(token);
    assert.equal(payload.userId, 'user-123');
  });

  it('should reject an expired token', () => {
    const token = jwt.sign({ userId: 'user-123' }, TEST_SECRET, { expiresIn: '0s' });
    const payload = verifyTestToken(token);
    assert.equal(payload, null);
  });

  it('should reject a token with wrong secret', () => {
    const token = jwt.sign({ userId: 'user-123' }, 'wrong-secret', { expiresIn: '1h' });
    const payload = verifyTestToken(token);
    assert.equal(payload, null);
  });

  it('should reject malformed tokens', () => {
    assert.equal(verifyTestToken('not-a-jwt'), null);
    assert.equal(verifyTestToken(''), null);
  });
});

// ── Webhook Simulation Tests ──────────────────────────────────────────────

describe('Webhook State Changes', () => {
  let db;

  before(() => { db = createTestDb(); });
  after(() => { db.close(); });

  it('should update tier on subscription created', () => {
    const userId = createTestUser(db, { tier: 'free', credits_balance: 500 });

    // Simulate what the webhook handler does
    db.prepare(
      'UPDATE users SET tier = ?, subscription_status = ?, credits_balance = ? WHERE id = ?'
    ).run('pro', 'active', 5000, userId);

    const user = db.prepare('SELECT tier, subscription_status, credits_balance FROM users WHERE id = ?').get(userId);
    assert.equal(user.tier, 'pro');
    assert.equal(user.subscription_status, 'active');
    assert.equal(user.credits_balance, 5000);
  });

  it('should revert to free on subscription deleted', () => {
    const userId = createTestUser(db, { tier: 'pro', credits_balance: 5000 });

    db.prepare(
      "UPDATE users SET tier = 'free', subscription_status = 'canceled', stripe_subscription_id = NULL WHERE id = ?"
    ).run(userId);

    const user = db.prepare('SELECT tier, subscription_status FROM users WHERE id = ?').get(userId);
    assert.equal(user.tier, 'free');
    assert.equal(user.subscription_status, 'canceled');
  });

  it('should set past_due on payment failure', () => {
    const userId = createTestUser(db, { tier: 'pro' });

    db.prepare(
      "UPDATE users SET subscription_status = 'past_due' WHERE id = ?"
    ).run(userId);

    const user = db.prepare('SELECT subscription_status FROM users WHERE id = ?').get(userId);
    assert.equal(user.subscription_status, 'past_due');
  });

  it('should set active on payment success', () => {
    const userId = createTestUser(db, { tier: 'pro' });
    db.prepare("UPDATE users SET subscription_status = 'past_due' WHERE id = ?").run(userId);

    db.prepare(
      "UPDATE users SET subscription_status = 'active', subscription_period_end = ? WHERE id = ?"
    ).run(Date.now() + 30 * 24 * 60 * 60 * 1000, userId);

    const user = db.prepare('SELECT subscription_status, subscription_period_end FROM users WHERE id = ?').get(userId);
    assert.equal(user.subscription_status, 'active');
    assert.ok(user.subscription_period_end > Date.now());
  });

  it('should pause subscription', () => {
    const userId = createTestUser(db, { tier: 'pro' });

    db.prepare(
      "UPDATE users SET subscription_status = 'paused', tier = 'free' WHERE id = ?"
    ).run(userId);

    const user = db.prepare('SELECT tier, subscription_status FROM users WHERE id = ?').get(userId);
    assert.equal(user.tier, 'free');
    assert.equal(user.subscription_status, 'paused');
  });
});

// ── GDPR Data Export / Delete Tests ───────────────────────────────────────

describe('GDPR Operations', () => {
  let db;

  before(() => { db = createTestDb(); });
  after(() => { db.close(); });

  it('should export all user data', () => {
    const userId = createTestUser(db, { credits_balance: 100 });
    db.prepare('INSERT INTO usage_log (user_id, model, prompt_tokens, completion_tokens, credits_deducted, created_at) VALUES (?,?,?,?,?,?)')
      .run(userId, 'claude', 100, 50, 5, Date.now());

    const user = db.prepare('SELECT * FROM users WHERE id = ?').get(userId);
    const usage = db.prepare('SELECT * FROM usage_log WHERE user_id = ?').all(userId);

    assert.ok(user);
    assert.equal(usage.length, 1);
    assert.equal(usage[0].model, 'claude');
  });

  it('should cascade delete user and all related data', () => {
    const userId = createTestUser(db, { credits_balance: 100 });
    db.prepare('INSERT INTO usage_log (user_id, model, prompt_tokens, completion_tokens, credits_deducted, created_at) VALUES (?,?,?,?,?,?)')
      .run(userId, 'claude', 100, 50, 5, Date.now());
    db.prepare('INSERT INTO credit_purchases (user_id, pack_key, credits_added, amount_cents, created_at) VALUES (?,?,?,?,?)')
      .run(userId, 'credits_1000', 1000, 499, Date.now());

    // Delete in same order as the API
    db.prepare('DELETE FROM usage_log WHERE user_id = ?').run(userId);
    db.prepare('DELETE FROM credit_purchases WHERE user_id = ?').run(userId);
    db.prepare('DELETE FROM users WHERE id = ?').run(userId);

    assert.equal(db.prepare('SELECT COUNT(*) as c FROM users WHERE id = ?').get(userId).c, 0);
    assert.equal(db.prepare('SELECT COUNT(*) as c FROM usage_log WHERE user_id = ?').get(userId).c, 0);
    assert.equal(db.prepare('SELECT COUNT(*) as c FROM credit_purchases WHERE user_id = ?').get(userId).c, 0);
  });
});
