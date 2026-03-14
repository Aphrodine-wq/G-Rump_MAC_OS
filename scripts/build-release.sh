#!/bin/bash
set -euo pipefail

# G-Rump Release Build Script
# Builds, signs, creates DMG, notarizes, and staples in one shot.
#
# Usage:
#   ./scripts/build-release.sh                    # Full pipeline (sign + DMG + notarize)
#   ./scripts/build-release.sh --skip-notarize    # Sign + DMG only (no Apple submission)
#   ./scripts/build-release.sh --app-only         # Signed .app only (no DMG, no notarize)
#
# Required environment variables:
#   DEVELOPER_ID  — e.g. "Developer ID Application: Your Name (TEAMID)"
#   APPLE_ID      — your Apple ID email (for notarization)
#   TEAM_ID       — your Apple Developer Team ID
#   APP_PASSWORD  — app-specific password for notarytool
#
# Tip: Store credentials in .env.local and run:
#   source .env.local && ./scripts/build-release.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

SKIP_NOTARIZE=false
APP_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --skip-notarize) SKIP_NOTARIZE=true ;;
        --app-only) APP_ONLY=true; SKIP_NOTARIZE=true ;;
        --help|-h)
            echo "Usage: $0 [--skip-notarize] [--app-only]"
            echo ""
            echo "  --skip-notarize  Build + sign + DMG, skip notarization"
            echo "  --app-only       Build + sign .app only (no DMG, no notarize)"
            echo ""
            echo "Environment variables:"
            echo "  DEVELOPER_ID  — Developer ID Application identity"
            echo "  APPLE_ID      — Apple ID email (for notarization)"
            echo "  TEAM_ID       — Apple Developer Team ID"
            echo "  APP_PASSWORD  — App-specific password for notarytool"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Run $0 --help for usage."
            exit 1
            ;;
    esac
done

# ── Validate environment ─────────────────────────────
if [ -z "${DEVELOPER_ID:-}" ]; then
    echo "Error: DEVELOPER_ID is not set."
    echo ""
    echo "  export DEVELOPER_ID=\"Developer ID Application: Your Name (TEAMID)\""
    echo ""
    echo "  To find your identity: security find-identity -v -p codesigning"
    exit 1
fi

if ! $SKIP_NOTARIZE; then
    MISSING=""
    [ -z "${APPLE_ID:-}" ] && MISSING="$MISSING APPLE_ID"
    [ -z "${TEAM_ID:-}" ] && MISSING="$MISSING TEAM_ID"
    [ -z "${APP_PASSWORD:-}" ] && MISSING="$MISSING APP_PASSWORD"
    if [ -n "$MISSING" ]; then
        echo "Error: Missing environment variables for notarization:$MISSING"
        echo ""
        echo "  export APPLE_ID=\"your@email.com\""
        echo "  export TEAM_ID=\"XXXXXXXXXX\""
        echo "  export APP_PASSWORD=\"xxxx-xxxx-xxxx-xxxx\""
        echo ""
        echo "  Or use --skip-notarize to skip notarization."
        exit 1
    fi
fi

echo ""
echo "  G-Rump Release Build"
echo "  ====================="
echo "  Identity:    $DEVELOPER_ID"
if ! $SKIP_NOTARIZE; then
    echo "  Apple ID:    $APPLE_ID"
    echo "  Team ID:     $TEAM_ID"
fi
echo "  Notarize:    $( $SKIP_NOTARIZE && echo 'no' || echo 'yes' )"
echo "  DMG:         $( $APP_ONLY && echo 'no' || echo 'yes' )"
echo ""

# ── Build the flags for package.sh ────────────────────
PACKAGE_FLAGS="--sign"

if ! $APP_ONLY; then
    PACKAGE_FLAGS="$PACKAGE_FLAGS --dmg"
fi

if ! $SKIP_NOTARIZE; then
    PACKAGE_FLAGS="$PACKAGE_FLAGS --notarize"
fi

# ── Run the packaging pipeline ────────────────────────
exec "$SCRIPT_DIR/package.sh" $PACKAGE_FLAGS
