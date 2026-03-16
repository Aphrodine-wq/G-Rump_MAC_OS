# Backend API

G-Rump's backend is a Node.js/Express server handling authentication, billing, and AI provider proxying.

## Stack

- **Runtime**: Node.js
- **Framework**: Express
- **Auth**: Google OAuth + JWT
- **Payments**: Stripe
- **Security**: Helmet, CORS, rate limiting, audit logging

## Endpoints

### Authentication
| Method | Path | Description |
|---|---|---|
| POST | `/auth/google` | Google OAuth sign-in |
| POST | `/auth/refresh` | Refresh JWT token |
| GET | `/auth/me` | Get current user profile |

### Billing
| Method | Path | Description |
|---|---|---|
| POST | `/billing/subscribe` | Create Stripe subscription |
| POST | `/billing/credits` | Purchase additional credits |
| GET | `/billing/usage` | Get usage analytics |
| POST | `/webhooks/stripe` | Stripe webhook handler |

### Proxy
| Method | Path | Description |
|---|---|---|
| POST | `/proxy/chat` | Proxy AI chat requests |
| POST | `/proxy/models` | List available models |

## Security

- **Helmet** — HTTP security headers
- **CORS** — Configured for app origin only
- **Rate Limiting** — Per-IP and per-user limits
- **Audit Logging** — All requests logged with timestamps
- **Webhook Verification** — Stripe signatures verified

## Running Locally

```bash
cd backend
npm install
cp .env.example .env  # Add your keys
npm start             # Starts on port 3001
```

## Key Files

| File | Purpose |
|---|---|
| `server.js` | Entry point, middleware setup |
| `auth.js` | Authentication routes and JWT |
| `proxy.js` | AI provider request proxying |
| `stripe.js` | Billing and webhook handling |
| `package.json` | Dependencies |
