#!/bin/bash
# G-Rump Backend — One-command Turso + Vercel deployment
# Run from project root:  ./scripts/deploy-backend.sh
set -euo pipefail

BACKEND_DIR="$(cd "$(dirname "$0")/../backend" && pwd)"
DB_NAME="${TURSO_DB_NAME:-grump-prod}"

echo "=== G-Rump Backend Deploy ==="
echo ""

# ── Step 1: Check prerequisites ─────────────────────
echo "▸ Checking prerequisites..."

if ! command -v turso &>/dev/null; then
    echo "  Installing Turso CLI..."
    brew install tursodatabase/tap/turso
fi

if ! command -v npx &>/dev/null; then
    echo "  Error: Node.js / npx not found. Install from https://nodejs.org"
    exit 1
fi

# Check Turso auth
if ! turso auth status &>/dev/null 2>&1; then
    echo "  Turso not authenticated. Logging in..."
    turso auth login
fi

echo "  ✓ Prerequisites OK"
echo ""

# ── Step 2: Create Turso database ────────────────────
echo "▸ Setting up Turso database: $DB_NAME"

if turso db show "$DB_NAME" &>/dev/null 2>&1; then
    echo "  Database '$DB_NAME' already exists."
else
    echo "  Creating database..."
    turso db create "$DB_NAME"
    echo "  ✓ Database created"
fi

TURSO_URL=$(turso db show "$DB_NAME" --url)
TURSO_TOKEN=$(turso db tokens create "$DB_NAME")
echo "  URL: $TURSO_URL"
echo "  ✓ Auth token generated"
echo ""

# ── Step 3: Install backend dependencies ─────────────
echo "▸ Installing backend dependencies..."
cd "$BACKEND_DIR"
npm install --silent
echo "  ✓ Dependencies installed"
echo ""

# ── Step 4: Deploy to Vercel ─────────────────────────
echo "▸ Deploying to Vercel..."

# Link project if not already linked
if [ ! -d ".vercel" ]; then
    echo "  Linking Vercel project (follow the prompts)..."
    npx vercel link
fi

# Set environment variables
echo "  Setting environment variables..."
echo "$TURSO_URL" | npx vercel env add TURSO_DATABASE_URL production --force 2>/dev/null || true
echo "$TURSO_TOKEN" | npx vercel env add TURSO_AUTH_TOKEN production --force 2>/dev/null || true

# Prompt for secrets we can't auto-generate
if [ -z "${JWT_SECRET:-}" ]; then
    JWT_SECRET=$(openssl rand -base64 48)
    echo "  Generated JWT_SECRET (random 48-byte key)"
fi
echo "$JWT_SECRET" | npx vercel env add JWT_SECRET production --force 2>/dev/null || true

if [ -n "${OPENROUTER_API_KEY:-}" ]; then
    echo "$OPENROUTER_API_KEY" | npx vercel env add OPENROUTER_API_KEY production --force 2>/dev/null || true
    echo "  ✓ OPENROUTER_API_KEY set from environment"
else
    echo "  ⚠ OPENROUTER_API_KEY not in environment. Set it manually:"
    echo "    npx vercel env add OPENROUTER_API_KEY production"
fi

if [ -n "${GOOGLE_CLIENT_ID:-}" ]; then
    echo "$GOOGLE_CLIENT_ID" | npx vercel env add GOOGLE_CLIENT_ID production --force 2>/dev/null || true
    echo "  ✓ GOOGLE_CLIENT_ID set from environment"
else
    echo "  ⚠ GOOGLE_CLIENT_ID not in environment. Set it manually:"
    echo "    npx vercel env add GOOGLE_CLIENT_ID production"
fi

if [ -n "${STRIPE_SECRET_KEY:-}" ]; then
    echo "$STRIPE_SECRET_KEY" | npx vercel env add STRIPE_SECRET_KEY production --force 2>/dev/null || true
    echo "  ✓ STRIPE_SECRET_KEY set"
fi

if [ -n "${STRIPE_WEBHOOK_SECRET:-}" ]; then
    echo "$STRIPE_WEBHOOK_SECRET" | npx vercel env add STRIPE_WEBHOOK_SECRET production --force 2>/dev/null || true
    echo "  ✓ STRIPE_WEBHOOK_SECRET set"
fi

echo ""
echo "  Deploying to production..."
DEPLOY_URL=$(npx vercel --prod --yes 2>&1 | tail -1)
echo ""
echo "  ✓ Deployed!"
echo ""

# ── Step 5: Verify ───────────────────────────────────
echo "▸ Verifying deployment..."
HEALTH_URL="${DEPLOY_URL}/api/health"
echo "  Checking: $HEALTH_URL"

sleep 3
HEALTH=$(curl -s "$HEALTH_URL" 2>/dev/null || echo '{"status":"unreachable"}')
echo "  Response: $HEALTH"
echo ""

# ── Done ─────────────────────────────────────────────
echo "=== Deploy Complete ==="
echo ""
echo "  Production URL:  $DEPLOY_URL"
echo "  Health Check:    $DEPLOY_URL/api/health"
echo "  Turso Dashboard: https://turso.tech/app/databases/$DB_NAME"
echo ""
echo "  Still need to set (if not done above):"
echo "    npx vercel env add OPENROUTER_API_KEY production"
echo "    npx vercel env add GOOGLE_CLIENT_ID production"
echo ""
echo "  Update your Swift app's backend URL to: $DEPLOY_URL"
