#!/bin/bash
# Reset G-Rump app state for fresh-boot testing.
# Use when the app freezes on splash or you need a clean state.
#
# Usage: ./scripts/reset-app.sh
#
# Preserves: app binary, source code, Keychain (API keys).
# Clears: UserDefaults, conversations, SwiftData store, exec approvals.

set -euo pipefail

echo "Resetting G-Rump app state..."
pkill -x GRump 2>/dev/null || true
defaults delete com.grump.app 2>/dev/null || true
rm -rf "$HOME/.grump"
rm -rf "$HOME/Library/Application Support/GRump"
rm -rf "$HOME/Library/Application Support/com.grump.app"
echo "✓ App state reset. Kill any frozen windows, then relaunch."
