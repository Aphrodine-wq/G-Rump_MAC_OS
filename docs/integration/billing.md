# Billing

G-Rump uses a Stripe-based billing system with subscription tiers and credit-based usage.

## Subscription Tiers

| Tier | Price | Includes |
|---|---|---|
| **Free** | $0/mo | Limited daily credits, basic models |
| **Pro** | TBD/mo | Generous credit allowance, all models, priority |
| **Team** | TBD/mo | Shared workspace, admin controls, usage analytics |

## Credits

Credits are consumed per API request based on model and token count. Credit balance is tracked server-side via the backend.

## Frontend

- **Settings → Account → Billing** — Manage subscription, purchase credits, view usage analytics
- `BillingView.swift` handles the UI

## Backend Integration

The Node.js backend (`backend/server.js`) handles:
- **Stripe webhooks** (`/webhooks/stripe`) — Subscription lifecycle events
- **Credit tracking** — Per-user credit balance and consumption
- **Usage analytics** — Token counts, model usage, cost breakdown

### Key Backend Files

| File | Purpose |
|---|---|
| `backend/server.js` | Express server entry point |
| `backend/stripe.js` | Stripe integration, webhook handlers |
| `backend/auth.js` | Authentication middleware |
| `backend/proxy.js` | AI provider request proxying |

## Environment Variables

```
STRIPE_SECRET_KEY=sk_...
STRIPE_WEBHOOK_SECRET=whsec_...
STRIPE_PRICE_ID_PRO=price_...
```

## Security

- All billing operations go through the backend (never client-side)
- Stripe webhook signatures are verified
- API keys stored server-side only
