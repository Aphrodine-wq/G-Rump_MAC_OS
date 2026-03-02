# G-Rump Platform Backend

Locked-down commercial backend: one OpenRouter API key, **Google Sign-In only** (no passwords stored), pricing tiers, and credit tracking.

## Security

- **No passwords stored** — Google OAuth only. Users sign in with Google; we store Google ID and email (from Google) for display.
- **JWT**: In production, `JWT_SECRET` must be set and at least 32 characters.
- **Rate limits**: Auth 30 requests / 15 min; API 120 / min.
- **CORS**: Set `CORS_ORIGIN` to `https://www.g-rump.com,https://g-rump.com` in production.

## Setup

1. **Google Cloud Console**  
   Create OAuth 2.0 Client IDs at [console.cloud.google.com/apis/credentials](https://console.cloud.google.com/apis/credentials) for iOS and macOS.

2. Copy `.env.example` to `.env` and set:
   - `OPENROUTER_API_KEY` — from [OpenRouter](https://openrouter.ai/settings/keys)
   - `JWT_SECRET` — random 32+ character string (required in production)
   - `GOOGLE_CLIENT_ID` — comma-separated iOS and macOS client IDs (e.g. `ios-id.apps.googleusercontent.com,macos-id.apps.googleusercontent.com`)

3. Install and run:

```bash
npm install
npm start
```

Runs on `http://localhost:3042` by default. For production, deploy behind `api.g-rump.com` and set `NODE_ENV=production`.

## API

### Auth
- **POST /api/auth/google** — `{ "idToken" }` → `{ token, user, isNew }`

### User
- **GET /api/me** — `Authorization: Bearer <token>` → `{ id, email, tier, creditsBalance, creditsPerMonth, ... }`
- **PATCH /api/me** — `{ displayName?, avatarUrl? }` → updated user
- **GET /api/me/usage** — usage analytics (by model, daily, monthly)
- **GET /api/me/export** — GDPR data export
- **DELETE /api/me** — delete account and all data

### Billing (Stripe)
- **POST /api/billing/checkout** — `{ priceKey, successUrl?, cancelUrl? }` → `{ url, sessionId }`
- **POST /api/billing/portal** — `{ returnUrl? }` → `{ url }`
- **POST /api/billing/credit-pack** — `{ packKey, successUrl?, cancelUrl? }` → `{ url, sessionId }`
- **GET /api/billing/usage** — billing analytics with tier info
- **POST /api/billing/webhook** — Stripe webhook handler

Stripe checkout and portal redirect to `www.g-rump.com` by default (configurable via `APP_URL`).

### Chat Proxy
- **POST /api/v1/chat/completions** — Same body as OpenRouter; requires auth. Proxies to OpenRouter, deducts credits from usage.

## Tiers (edit in `db.js`)

| Tier    | Credits/month | Models               | Price     |
|---------|---------------|----------------------|-----------|
| Free    | 500           | free-tier            | $0        |
| Starter | 2,000         | free, fast           | $9.99/mo  |
| Pro     | 5,000         | free, fast, frontier | $19.99/mo |
| Team    | 25,000        | free, fast, frontier | $49.99/mo |

Credits are deducted per request (1 credit per 1K tokens by default; see `CREDITS_PER_1K_TOKENS` in `db.js`).

## OpenRouter

The backend is tuned for OpenRouter:

- Single server-side API key; clients never see it.
- Requests use `provider: { sort: "price", allow_fallbacks: true }`.
- Usage from the last stream chunk is used to deduct credits.

## Data

SQLite at `backend/data/grump.db` (or `DATABASE_PATH`). No migrations; schema is created on first run.
