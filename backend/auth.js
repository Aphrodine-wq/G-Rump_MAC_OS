import jwt from 'jsonwebtoken';
import { OAuth2Client } from 'google-auth-library';
import { randomUUID } from 'crypto';
import { getDb, TIERS } from './db.js';

const JWT_SECRET = process.env.JWT_SECRET;
const JWT_EXPIRY = '7d';
const GOOGLE_CLIENT_IDS = (process.env.GOOGLE_CLIENT_ID || process.env.GOOGLE_CLIENT_IDS || '')
  .split(',')
  .map(s => s.trim())
  .filter(Boolean);

const isProduction = process.env.NODE_ENV === 'production';
if (isProduction && (!JWT_SECRET || JWT_SECRET.length < 32)) {
  throw new Error('JWT_SECRET must be set and at least 32 characters in production');
}
const secret = JWT_SECRET || 'dev-only-change-in-production';

if (isProduction && GOOGLE_CLIENT_IDS.length === 0) {
  throw new Error('GOOGLE_CLIENT_ID or GOOGLE_CLIENT_IDS must be set in production for Google Sign-In');
}

const googleClient = GOOGLE_CLIENT_IDS.length > 0 ? new OAuth2Client() : null;

export function signToken(payload) {
  return jwt.sign(payload, secret, { expiresIn: JWT_EXPIRY });
}

export function verifyToken(token) {
  try {
    return jwt.verify(token, secret);
  } catch {
    return null;
  }
}

export async function verifyGoogleIdToken(idToken) {
  if (!googleClient || GOOGLE_CLIENT_IDS.length === 0) {
    throw new Error('Google Sign-In is not configured');
  }
  const ticket = await googleClient.verifyIdToken({
    idToken,
    audience: GOOGLE_CLIENT_IDS,
  });
  const payload = ticket.getPayload();
  if (!payload?.sub || !payload?.email) {
    throw new Error('Invalid Google token');
  }
  return { googleId: payload.sub, email: payload.email };
}

export function authMiddleware(req, res, next) {
  const auth = req.headers.authorization;
  const token = auth?.startsWith('Bearer ') ? auth.slice(7) : null;
  if (!token) {
    return res.status(401).json({ error: 'Missing or invalid authorization' });
  }
  const payload = verifyToken(token);
  if (!payload?.userId) {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
  req.userId = payload.userId;
  next();
}

export function getOrCreateUserByGoogle(googleId, email) {
  const db = getDb();
  const existing = db.prepare(
    'SELECT id, email, tier, credits_balance, credits_replenished_at, display_name, avatar_url FROM users WHERE google_id = ?'
  ).get(googleId);
  if (existing) {
    return { user: existing, isNew: false };
  }
  const id = randomUUID();
  const now = Date.now();
  const initialCredits = TIERS.free.creditsPerMonth;
  db.prepare(`
    INSERT INTO users (id, google_id, email, tier, credits_balance, credits_replenished_at, created_at, updated_at)
    VALUES (?, ?, ?, 'free', ?, ?, ?, ?)
  `).run(id, googleId, email, initialCredits, now, now, now);
  const user = db.prepare('SELECT id, email, tier, credits_balance, credits_replenished_at, display_name, avatar_url FROM users WHERE id = ?').get(id);
  return { user, isNew: true };
}

export function replenishCreditsIfNeeded(db, userId, currentBalance, replenishedAt) {
  const tierRow = db.prepare('SELECT tier FROM users WHERE id = ?').get(userId);
  if (!tierRow) return currentBalance;
  const tierConfig = TIERS[tierRow.tier] ?? TIERS.free;
  const now = Date.now();
  const monthMs = 30 * 24 * 60 * 60 * 1000;
  const lastReplenish = replenishedAt ?? 0;
  if (now - lastReplenish >= monthMs) {
    const newBalance = (currentBalance ?? 0) + tierConfig.creditsPerMonth;
    const newReplenishedAt = replenishedAt ? lastReplenish + monthMs : now;
    db.prepare('UPDATE users SET credits_balance = ?, credits_replenished_at = ?, updated_at = ? WHERE id = ?')
      .run(newBalance, newReplenishedAt, now, userId);
    return newBalance;
  }
  return currentBalance;
}
