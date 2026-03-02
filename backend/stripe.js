import Stripe from 'stripe';
import crypto from 'crypto';
import { getDb, TIERS } from './db.js';

// MARK: - Stripe Integration
//
// Handles payment processing for G-Rump subscriptions and credit packs.
// Uses Stripe Checkout for tier upgrades and Customer Portal for management.

const stripe = process.env.STRIPE_SECRET_KEY
  ? new Stripe(process.env.STRIPE_SECRET_KEY, { apiVersion: '2024-12-18.acacia' })
  : null;

// Pricing IDs (set these in your Stripe Dashboard or via env vars)
const PRICE_IDS = {
  starter_monthly: process.env.STRIPE_PRICE_STARTER,
  pro_monthly: process.env.STRIPE_PRICE_PRO,
  team_monthly: process.env.STRIPE_PRICE_TEAM,
  credits_1000: process.env.STRIPE_PRICE_CREDITS_1K,
  credits_5000: process.env.STRIPE_PRICE_CREDITS_5K,
  credits_20000: process.env.STRIPE_PRICE_CREDITS_20K,
};

// Validate Stripe price IDs on startup if Stripe is configured
if (stripe) {
  const missing = Object.entries(PRICE_IDS)
    .filter(([, v]) => !v)
    .map(([k]) => k);
  if (missing.length > 0) {
    console.error(`[stripe] Missing price env vars: ${missing.join(', ')}. Set STRIPE_PRICE_* env vars.`);
  }
}

const CREDIT_PACKS = {
  credits_1000: { credits: 1000, price: 499 },   // $4.99
  credits_5000: { credits: 5000, price: 1999 },   // $19.99
  credits_20000: { credits: 20000, price: 6999 },  // $69.99
};

const TIER_MAP = {
  starter_monthly: 'starter',
  pro_monthly: 'pro',
  team_monthly: 'team',
};

// MARK: - Customer Management

export async function getOrCreateStripeCustomer(userId, email) {
  if (!stripe) throw new Error('Stripe not configured');
  const db = getDb();
  const user = await db.get('SELECT stripe_customer_id FROM users WHERE id = ?', [userId]);

  if (user?.stripe_customer_id) {
    return user.stripe_customer_id;
  }

  const idempotencyKey = crypto.createHash('sha256').update(`customer:${userId}:${email}`).digest('hex');
  const customer = await stripe.customers.create({
    email,
    metadata: { grump_user_id: userId },
  }, { idempotencyKey });

  await db.run('UPDATE users SET stripe_customer_id = ?, updated_at = ? WHERE id = ?',
    [customer.id, Date.now(), userId]);

  return customer.id;
}

// MARK: - Checkout Session

export async function createCheckoutSession(userId, email, priceKey, successUrl, cancelUrl) {
  if (!stripe) throw new Error('Stripe not configured');

  const customerId = await getOrCreateStripeCustomer(userId, email);
  const priceId = PRICE_IDS[priceKey];
  if (!priceId) throw new Error(`Unknown price key: ${priceKey}`);

  const isSubscription = !priceKey.startsWith('credits_');

  const checkoutIdempotencyKey = crypto.createHash('sha256').update(`checkout:${userId}:${priceKey}:${Date.now()}`).digest('hex');
  const session = await stripe.checkout.sessions.create({
    customer: customerId,
    mode: isSubscription ? 'subscription' : 'payment',
    line_items: [{ price: priceId, quantity: 1 }],
    success_url: successUrl || `${process.env.APP_URL || 'https://www.g-rump.com'}/billing/success?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: cancelUrl || `${process.env.APP_URL || 'https://www.g-rump.com'}/billing/cancel`,
    metadata: {
      grump_user_id: userId,
      price_key: priceKey,
    },
    ...(isSubscription && {
      subscription_data: {
        metadata: { grump_user_id: userId },
        trial_period_days: priceKey === 'pro_monthly' ? 14 : priceKey === 'starter_monthly' ? 7 : undefined,
      },
    }),
  });

  return session;
}

// MARK: - Customer Portal

export async function createPortalSession(userId, email, returnUrl) {
  if (!stripe) throw new Error('Stripe not configured');

  const customerId = await getOrCreateStripeCustomer(userId, email);

  const session = await stripe.billingPortal.sessions.create({
    customer: customerId,
    return_url: returnUrl || `${process.env.APP_URL || 'https://www.g-rump.com'}/settings`,
  });

  return session;
}

// MARK: - Webhook Handler

export async function handleStripeWebhook(rawBody, signature) {
  if (!stripe) throw new Error('Stripe not configured');

  const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;
  if (!webhookSecret) throw new Error('STRIPE_WEBHOOK_SECRET not set');

  const event = stripe.webhooks.constructEvent(rawBody, signature, webhookSecret);
  const db = getDb();

  switch (event.type) {
    case 'checkout.session.completed': {
      const session = event.data.object;
      const userId = session.metadata?.grump_user_id;
      const priceKey = session.metadata?.price_key;
      if (!userId) break;

      if (priceKey?.startsWith('credits_') && CREDIT_PACKS[priceKey]) {
        // Credit pack purchase
        const pack = CREDIT_PACKS[priceKey];
        // Read current balance, add credits, write back (no credits_balance + ? in libsql)
        const current = await db.get('SELECT credits_balance FROM users WHERE id = ?', [userId]);
        const newBalance = (current?.credits_balance ?? 0) + pack.credits;
        await db.run('UPDATE users SET credits_balance = ?, updated_at = ? WHERE id = ?',
          [newBalance, Date.now(), userId]);

        // Log the purchase
        await db.run(
          `INSERT INTO credit_purchases (user_id, pack_key, credits_added, amount_cents, stripe_session_id, created_at)
           VALUES (?, ?, ?, ?, ?, ?)`,
          [userId, priceKey, pack.credits, pack.price, session.id, Date.now()]
        );
      }
      break;
    }

    case 'customer.subscription.created':
    case 'customer.subscription.updated': {
      const subscription = event.data.object;
      const userId = subscription.metadata?.grump_user_id;
      if (!userId) break;

      const priceId = subscription.items?.data?.[0]?.price?.id;
      const priceKey = Object.entries(PRICE_IDS).find(([, v]) => v === priceId)?.[0];
      const tier = priceKey ? TIER_MAP[priceKey] : null;

      if (tier) {
        const tierInfo = TIERS[tier];
        await db.run(
          `UPDATE users SET tier = ?, stripe_subscription_id = ?, subscription_status = ?,
           subscription_period_end = ?, credits_balance = ?, updated_at = ?
           WHERE id = ?`,
          [
            tier,
            subscription.id,
            subscription.status,
            subscription.current_period_end * 1000,
            tierInfo.creditsPerMonth,
            Date.now(),
            userId,
          ]
        );
      }
      break;
    }

    case 'customer.subscription.deleted': {
      const subscription = event.data.object;
      const userId = subscription.metadata?.grump_user_id;
      if (!userId) break;

      await db.run(
        `UPDATE users SET tier = 'free', subscription_status = 'canceled',
         stripe_subscription_id = NULL, updated_at = ?
         WHERE id = ?`,
        [Date.now(), userId]
      );
      break;
    }

    case 'invoice.payment_failed': {
      const invoice = event.data.object;
      const customerId = invoice.customer;
      const user = await db.get('SELECT id FROM users WHERE stripe_customer_id = ?', [customerId]);
      if (user) {
        await db.run('UPDATE users SET subscription_status = ?, updated_at = ? WHERE id = ?',
          ['past_due', Date.now(), user.id]);
      }
      break;
    }

    case 'invoice.payment_succeeded': {
      const invoice = event.data.object;
      const customerId = invoice.customer;
      const user = await db.get('SELECT id FROM users WHERE stripe_customer_id = ?', [customerId]);
      if (user && invoice.subscription) {
        const subscription = await stripe.subscriptions.retrieve(invoice.subscription);
        const priceId = subscription.items?.data?.[0]?.price?.id;
        const priceKey = Object.entries(PRICE_IDS).find(([, v]) => v === priceId)?.[0];
        const tier = priceKey ? TIER_MAP[priceKey] : null;

        const updates = ['subscription_status = ?', 'updated_at = ?'];
        const args = ['active', Date.now()];
        if (subscription.current_period_end) {
          updates.push('subscription_period_end = ?');
          args.push(subscription.current_period_end * 1000);
        }
        if (tier) {
          updates.push('tier = ?');
          args.push(tier);
        }
        args.push(user.id);
        await db.run(`UPDATE users SET ${updates.join(', ')} WHERE id = ?`, args);
      }
      break;
    }

    case 'customer.subscription.paused': {
      const subscription = event.data.object;
      const userId = subscription.metadata?.grump_user_id;
      if (!userId) break;
      await db.run(
        'UPDATE users SET subscription_status = ?, tier = ?, updated_at = ? WHERE id = ?',
        ['paused', 'free', Date.now(), userId]
      );
      break;
    }
  }

  return { received: true };
}

// MARK: - Usage Analytics

export async function getUsageAnalytics(userId) {
  const db = getDb();

  const monthAgo = Date.now() - 30 * 24 * 60 * 60 * 1000;

  const summary = await db.get(
    `SELECT SUM(credits_deducted) as credits_used, COUNT(*) as requests,
            SUM(prompt_tokens) as prompt_tokens, SUM(completion_tokens) as completion_tokens
     FROM usage_log WHERE user_id = ? AND created_at >= ?`,
    [userId, monthAgo]
  );

  const byModel = await db.all(
    `SELECT model, COUNT(*) as requests, SUM(credits_deducted) as credits
     FROM usage_log WHERE user_id = ? AND created_at >= ?
     GROUP BY model ORDER BY credits DESC`,
    [userId, monthAgo]
  );

  const purchases = await db.all(
    `SELECT pack_key, credits_added, amount_cents, created_at
     FROM credit_purchases WHERE user_id = ?
     ORDER BY created_at DESC LIMIT 10`,
    [userId]
  );

  return {
    creditsUsedThisMonth: summary?.credits_used ?? 0,
    requestsThisMonth: summary?.requests ?? 0,
    promptTokens: summary?.prompt_tokens ?? 0,
    completionTokens: summary?.completion_tokens ?? 0,
    byModel,
    recentPurchases: purchases,
  };
}

export { stripe, PRICE_IDS, CREDIT_PACKS };
