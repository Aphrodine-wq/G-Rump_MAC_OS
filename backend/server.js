import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import { getDb, TIERS } from './db.js';
import { signToken, authMiddleware, verifyGoogleIdToken, getOrCreateUserByGoogle, replenishCreditsIfNeeded } from './auth.js';
import { proxyChat } from './proxy.js';

const app = express();

const corsOrigin = process.env.CORS_ORIGIN;
app.use(cors({
  origin: corsOrigin ? corsOrigin.split(',').map(s => s.trim()) : true,
  credentials: true,
}));
app.use(express.json({ limit: '2mb' }));

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 30,
  message: { error: 'Too many attempts. Try again later.' },
  standardHeaders: true,
});
app.use('/api/auth', authLimiter);

const apiLimiter = rateLimit({
  windowMs: 1 * 60 * 1000,
  max: 120,
  standardHeaders: true,
});
app.use('/api/', apiLimiter);

// MARK: - Health Check

app.get('/api/health', (_req, res) => {
  const db = getDb();
  try {
    db.prepare('SELECT 1').get();
    res.json({
      status: 'ok',
      timestamp: new Date().toISOString(),
      uptime: Math.floor(process.uptime()),
      openrouter: !!process.env.OPENROUTER_API_KEY,
    });
  } catch (err) {
    res.status(503).json({
      status: 'degraded',
      error: 'database_unavailable',
      message: 'Database health check failed',
    });
  }
});

// MARK: - Structured Error Helper

function apiError(res, status, code, message) {
  return res.status(status).json({ error: { code, message } });
}

// MARK: - Auth

app.post('/api/auth/google', async (req, res) => {
  const { idToken } = req.body || {};
  if (!idToken || typeof idToken !== 'string') {
    return res.status(400).json({ error: 'Google ID token required' });
  }
  try {
    const { googleId, email } = await verifyGoogleIdToken(idToken);
    const { user, isNew } = getOrCreateUserByGoogle(googleId, email);
    const db = getDb();
    replenishCreditsIfNeeded(db, user.id, user.credits_balance, user.credits_replenished_at);
    const updated = db.prepare('SELECT credits_balance, credits_replenished_at, display_name, avatar_url FROM users WHERE id = ?').get(user.id);
    const token = signToken({ userId: user.id });
    const profile = updated ?? user;
    return res.json({
      token,
      user: {
        id: user.id,
        email: user.email,
        tier: user.tier,
        creditsBalance: updated?.credits_balance ?? user.credits_balance,
        creditsReplenishedAt: updated?.credits_replenished_at ?? user.credits_replenished_at,
        displayName: profile.display_name ?? null,
        avatarUrl: profile.avatar_url ?? null,
      },
      isNew: !!isNew,
    });
  } catch (err) {
    if (err.message?.includes('Invalid') || err.message?.includes('token')) {
      return res.status(401).json({ error: err.message });
    }
    console.error('Google auth error:', err);
    return res.status(500).json({ error: 'Sign-in failed. Try again.' });
  }
});

app.get('/api/me', authMiddleware, (req, res) => {
  const db = getDb();
  const user = db.prepare('SELECT id, email, tier, credits_balance, credits_replenished_at, display_name, avatar_url FROM users WHERE id = ?').get(req.userId);
  if (!user) return res.status(401).end();
  replenishCreditsIfNeeded(db, user.id, user.credits_balance, user.credits_replenished_at);
  const updated = db.prepare('SELECT credits_balance, credits_replenished_at FROM users WHERE id = ?').get(user.id);
  const tierInfo = TIERS[user.tier] ?? TIERS.free;
  return res.json({
    id: user.id,
    email: user.email,
    tier: user.tier,
    tierName: tierInfo.name,
    creditsBalance: updated?.credits_balance ?? user.credits_balance,
    creditsPerMonth: tierInfo.creditsPerMonth,
    creditsReplenishedAt: updated?.credits_replenished_at ?? user.credits_replenished_at,
    displayName: user.display_name ?? null,
    avatarUrl: user.avatar_url ?? null,
  });
});

app.patch('/api/me', authMiddleware, (req, res) => {
  const db = getDb();
  const { displayName, avatarUrl } = req.body || {};
  const updates = [];
  const args = [];
  if (typeof displayName === 'string') {
    updates.push('display_name = ?');
    args.push(displayName.trim() || null);
  }
  if (typeof avatarUrl === 'string') {
    updates.push('avatar_url = ?');
    args.push(avatarUrl.trim() || null);
  }
  if (updates.length === 0) {
    return res.status(400).json({ error: 'No valid profile fields to update' });
  }
  const now = Date.now();
  updates.push('updated_at = ?');
  args.push(now);
  args.push(req.userId);
  db.prepare(`UPDATE users SET ${updates.join(', ')} WHERE id = ?`).run(...args);
  const user = db.prepare('SELECT id, email, tier, credits_balance, credits_replenished_at, display_name, avatar_url FROM users WHERE id = ?').get(req.userId);
  const tierInfo = TIERS[user.tier] ?? TIERS.free;
  return res.json({
    id: user.id,
    email: user.email,
    tier: user.tier,
    tierName: tierInfo.name,
    creditsBalance: user.credits_balance,
    creditsPerMonth: tierInfo.creditsPerMonth,
    creditsReplenishedAt: user.credits_replenished_at ?? null,
    displayName: user.display_name ?? null,
    avatarUrl: user.avatar_url ?? null,
  });
});

app.get('/api/me/usage', authMiddleware, (req, res) => {
  const db = getDb();
  const rows = db.prepare(`
    SELECT SUM(credits_deducted) as total_credits, COUNT(*) as request_count,
           SUM(prompt_tokens) as total_prompt, SUM(completion_tokens) as total_completion
    FROM usage_log WHERE user_id = ?
  `).get(req.userId);
  const monthAgo = Date.now() - 30 * 24 * 60 * 60 * 1000;
  const recent = db.prepare(`
    SELECT SUM(credits_deducted) as credits_this_month, COUNT(*) as requests_this_month
    FROM usage_log WHERE user_id = ? AND created_at >= ?
  `).get(req.userId, monthAgo);

  // Per-model breakdown (last 30 days)
  const byModel = db.prepare(`
    SELECT model, COUNT(*) as requests, SUM(credits_deducted) as credits,
           SUM(prompt_tokens) as prompt_tokens, SUM(completion_tokens) as completion_tokens
    FROM usage_log WHERE user_id = ? AND created_at >= ?
    GROUP BY model ORDER BY credits DESC
  `).all(req.userId, monthAgo);

  // Daily usage (last 14 days)
  const twoWeeksAgo = Date.now() - 14 * 24 * 60 * 60 * 1000;
  const daily = db.prepare(`
    SELECT CAST(created_at / 86400000 AS INTEGER) as day,
           COUNT(*) as requests, SUM(credits_deducted) as credits
    FROM usage_log WHERE user_id = ? AND created_at >= ?
    GROUP BY day ORDER BY day
  `).all(req.userId, twoWeeksAgo);

  return res.json({
    totalCreditsUsed: rows?.total_credits ?? 0,
    requestCount: rows?.request_count ?? 0,
    totalPromptTokens: rows?.total_prompt ?? 0,
    totalCompletionTokens: rows?.total_completion ?? 0,
    creditsThisMonth: recent?.credits_this_month ?? 0,
    requestsThisMonth: recent?.requests_this_month ?? 0,
    byModel,
    dailyUsage: daily,
  });
});

app.post('/api/v1/chat/completions', authMiddleware, (req, res) => {
  // Validate chat request body
  const body = req.body;
  if (!body || typeof body !== 'object') {
    return apiError(res, 400, 'invalid_request', 'Request body must be a JSON object');
  }
  if (!body.model || typeof body.model !== 'string') {
    return apiError(res, 400, 'missing_model', 'model field is required and must be a string');
  }
  if (!Array.isArray(body.messages) || body.messages.length === 0) {
    return apiError(res, 400, 'missing_messages', 'messages must be a non-empty array');
  }
  for (const msg of body.messages) {
    if (!msg.role || !['system', 'user', 'assistant', 'tool'].includes(msg.role)) {
      return apiError(res, 400, 'invalid_message_role', `Invalid message role: ${msg.role}`);
    }
  }

  proxyChat(req, res).catch(err => {
    console.error('Proxy error:', err);
    if (!res.headersSent) {
      apiError(res, 500, 'proxy_error', 'Failed to proxy request to AI provider');
    }
  });
});

const port = process.env.PORT || 3042;
getDb();
app.listen(port, () => {
  console.log(`G-Rump platform listening on http://localhost:${port}`);
  if (!process.env.OPENROUTER_API_KEY) {
    console.warn('WARNING: OPENROUTER_API_KEY not set. Chat proxy will return 503.');
  }
});
