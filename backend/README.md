# G-Rump Platform Backend

Locked-down commercial backend: one OpenRouter API key, **Google Sign-In only** (no passwords stored), pricing tiers, and credit tracking.

## Security

- **No passwords stored** — Google OAuth only. Users sign in with Google; we store Google ID and email (from Google) for display.
- **JWT**: In production, `JWT_SECRET` must be set and at least 32 characters.
- **Rate limits**: Auth 30 requests / 15 min; API 120 / min.
- **CORS**: Set `CORS_ORIGIN` for web; omit for native app only.

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

Runs on `http://localhost:3042` by default. For production, deploy and set `NODE_ENV=production`.

## API

- **POST /api/auth/signup** — `{ "email", "password" }` → `{ token, user }`
- **POST /api/auth/login** — `{ "email", "password" }` → `{ token, user }`
- **GET /api/me** — `Authorization: Bearer <token>` → `{ id, email, tier, creditsBalance, creditsPerMonth, ... }`
- **POST /api/v1/chat/completions** — Same body as OpenRouter; requires auth. Proxies to OpenRouter, deducts credits from usage.

## Tiers (edit in `db.js`)

| Tier  | Credits/month | Models        |
|-------|----------------|---------------|
| Free  | 500            | free-tier     |
| Pro   | 5,000          | free, fast, frontier |
| Team  | 25,000         | free, fast, frontier |

Credits are deducted per request (1 credit per 1K tokens by default; see `CREDITS_PER_1K_TOKENS` in `db.js`).

## OpenRouter

The backend is tuned for OpenRouter:

- Single server-side API key; clients never see it.
- Requests use `provider: { sort: "price", allow_fallbacks: true }`.
- Usage from the last stream chunk is used to deduct credits.

## Data

SQLite at `backend/data/grump.db` (or `DATABASE_PATH`). No migrations; schema is created on first run.
