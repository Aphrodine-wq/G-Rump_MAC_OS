import { getDb, TIERS, CREDITS_PER_1K_TOKENS } from './db.js';
import { replenishCreditsIfNeeded } from './auth.js';

const OPENROUTER_URL = 'https://openrouter.ai/api/v1/chat/completions';
const OPENROUTER_KEY = process.env.OPENROUTER_API_KEY;

export async function proxyChat(req, res) {
  if (!OPENROUTER_KEY) {
    return res.status(503).json({ error: 'OpenRouter is not configured' });
  }

  const userId = req.userId;
  const db = getDb();
  const user = await db.get('SELECT tier, credits_balance, credits_replenished_at FROM users WHERE id = ?', [userId]);
  if (!user) return res.status(401).end();

  let balance = await replenishCreditsIfNeeded(db, userId, user.credits_balance, user.credits_replenished_at);
  const tierConfig = TIERS[user.tier] ?? TIERS.free;

  const body = req.body;
  const model = body?.model;
  if (!model) return res.status(400).json({ error: 'model is required' });

  const modelTier = getModelTier(model);
  if (!tierConfig.models.includes(modelTier)) {
    return res.status(403).json({ error: `Your plan (${tierConfig.name}) does not include this model. Upgrade to use ${model}.` });
  }

  const forwardHeaders = {
    'Authorization': `Bearer ${OPENROUTER_KEY}`,
    'Content-Type': 'application/json',
    'HTTP-Referer': 'https://github.com/jameswalton/G-Rump',
    'X-Title': 'G-Rump',
  };

  const stream = body.stream === true;
  if (!stream) {
    const resp = await fetch(OPENROUTER_URL, {
      method: 'POST',
      headers: forwardHeaders,
      body: JSON.stringify(body),
    });
    const data = await resp.json();
    if (data.usage) await deductAndLog(db, userId, model, data.usage, res);
    res.status(resp.status).json(data);
    return;
  }

  const response = await fetch(OPENROUTER_URL, {
    method: 'POST',
    headers: forwardHeaders,
    body: JSON.stringify(body),
    duplex: 'half',
  });

  if (!response.ok) {
    const err = await response.text();
    return res.status(response.status).send(err);
  }

  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.flushHeaders();

  let lastUsage = null;
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n');
      buffer = lines.pop() || '';
      for (const line of lines) {
        if (line.startsWith('data: ')) {
          const data = line.slice(6);
          if (data === '[DONE]') continue;
          try {
            const parsed = JSON.parse(data);
            if (parsed.usage) lastUsage = parsed.usage;
            res.write(line + '\n');
            if (typeof res.flush === 'function') res.flush();
          } catch (_) {
            res.write(line + '\n');
            if (typeof res.flush === 'function') res.flush();
          }
        }
      }
    }
    if (buffer.trim()) {
      res.write(buffer + '\n');
      if (typeof res.flush === 'function') res.flush();
    }
    if (lastUsage) await deductAndLog(db, userId, model, lastUsage, res);
  } finally {
    res.end();
  }
}

// Model tier classification — explicit allowlist instead of brittle string matching
const MODEL_TIERS = {
  frontier: ['claude-opus', 'claude-sonnet', 'gpt-4o', 'gpt-4-turbo', 'kimi-k2', 'gemini-2'],
  free: [':free'],
};

function getModelTier(model) {
  if (MODEL_TIERS.free.some(m => model.includes(m))) return 'free';
  if (MODEL_TIERS.frontier.some(m => model.includes(m))) return 'frontier';
  console.warn(`[proxy] Unknown model tier for "${model}", defaulting to "fast"`);
  return 'fast';
}

async function deductAndLog(db, userId, model, usage, res) {
  const prompt = usage.prompt_tokens ?? 0;
  const completion = usage.completion_tokens ?? 0;
  const total = prompt + completion;
  const creditsDeducted = Math.max(1, Math.ceil((total / 1000) * CREDITS_PER_1K_TOKENS));

  // Atomic credit deduction — prevents race condition with concurrent requests
  const result = await db.run(
    'UPDATE users SET credits_balance = MAX(0, credits_balance - ?), updated_at = ? WHERE id = ? AND credits_balance >= ?',
    [creditsDeducted, Date.now(), userId, creditsDeducted]
  );

  // If no rows updated, user had insufficient credits — deduct whatever remains
  if (result.changes === 0) {
    await db.run(
      'UPDATE users SET credits_balance = 0, updated_at = ? WHERE id = ? AND credits_balance > 0',
      [Date.now(), userId]
    );
  }

  await db.run(
    `INSERT INTO usage_log (user_id, model, prompt_tokens, completion_tokens, credits_deducted, created_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [userId, model, prompt, completion, creditsDeducted, Date.now()]
  );

  // Read final balance for headers
  const row = await db.get('SELECT credits_balance FROM users WHERE id = ?', [userId]);
  const newBalance = row?.credits_balance ?? 0;

  // Headers only for non-streaming; when streaming, client refetches /api/me for balance
  if (res && !res.headersSent) {
    res.setHeader('X-Credits-Deducted', String(creditsDeducted));
    res.setHeader('X-Credits-Balance', String(newBalance));
  }
}
