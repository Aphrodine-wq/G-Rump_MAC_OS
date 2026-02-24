#!/bin/bash
set -euo pipefail

# G-Rump 2.0 macOS Packaging Script
# Creates a signed .app bundle and optionally a .dmg with notarization.
#
# Usage:
#   ./scripts/package.sh                          # Build .app only (no signing)
#   ./scripts/package.sh --sign                    # Build + code sign
#   ./scripts/package.sh --sign --dmg              # Build + sign + create .dmg
#   ./scripts/package.sh --sign --dmg --notarize   # Build + sign + .dmg + notarize
#
# Prerequisites:
#   brew install create-dmg    (required for --dmg)
#
# Environment variables (for signing/notarization):
#   DEVELOPER_ID    — "Developer ID Application: Your Name (TEAMID)"
#   APPLE_ID        — your Apple ID email
#   TEAM_ID         — your Apple Developer Team ID
#   APP_PASSWORD    — app-specific password for notarytool

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_NAME="G-Rump"
APP_BUNDLE="$PROJECT_DIR/dist/${APP_NAME}.app"
DMG_PATH="$PROJECT_DIR/dist/${APP_NAME}.dmg"
ENTITLEMENTS="$PROJECT_DIR/GRump.entitlements"
INFO_PLIST="$PROJECT_DIR/Sources/GRump/Info.plist"

DO_SIGN=false
DO_DMG=false
DO_NOTARIZE=false

for arg in "$@"; do
    case "$arg" in
        --sign) DO_SIGN=true ;;
        --dmg) DO_DMG=true ;;
        --notarize) DO_NOTARIZE=true ;;
        --help|-h)
            echo "Usage: $0 [--sign] [--dmg] [--notarize]"
            echo ""
            echo "  --sign       Code sign with Developer ID (requires DEVELOPER_ID env var)"
            echo "  --dmg        Create .dmg disk image"
            echo "  --notarize   Submit to Apple for notarization (requires APPLE_ID, TEAM_ID, APP_PASSWORD)"
            exit 0
            ;;
    esac
done

# ── Pre-flight: check create-dmg if needed ────────
if $DO_DMG; then
    if ! command -v create-dmg &>/dev/null; then
        echo "✗ create-dmg is required for DMG creation."
        echo "  Install it with: brew install create-dmg"
        exit 1
    fi
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  G-Rump 2.0 Packaging"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Step 1: Build release binary ──────────────────────
echo "▸ Building release binary..."
cd "$PROJECT_DIR"
swift build -c release -j "$(sysctl -n hw.ncpu)" 2>&1 | tail -5
BINARY="$BUILD_DIR/GRump"

if [ ! -f "$BINARY" ]; then
    echo "✗ Build failed — binary not found at $BINARY"
    exit 1
fi
echo "✓ Binary built: $BINARY"
echo ""

# ── Step 2: Create .app bundle ────────────────────────
echo "▸ Creating .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/GRump"

# Copy Info.plist
cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"

# Copy bundled resources (skills, etc.) if they exist
RESOURCES_DIR="$BUILD_DIR/GRump_GRump.bundle"
if [ -d "$RESOURCES_DIR" ]; then
    cp -R "$RESOURCES_DIR" "$APP_BUNDLE/Contents/Resources/"
    echo "  → Copied resource bundle"
fi

# Copy or generate app icon
ICON_PATH="$PROJECT_DIR/Sources/GRump/Resources/AppIcon.icns"
if [ ! -f "$ICON_PATH" ]; then
    echo "  → Generating AppIcon.icns from xcassets PNGs..."
    ICONSET_DIR=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$ICONSET_DIR"
    ASSETS_DIR="$PROJECT_DIR/Sources/GRump/Resources/Assets.xcassets/AppIcon.appiconset"
    cp "$ASSETS_DIR/16.png"   "$ICONSET_DIR/icon_16x16.png"
    cp "$ASSETS_DIR/32.png"   "$ICONSET_DIR/icon_16x16@2x.png"
    cp "$ASSETS_DIR/32.png"   "$ICONSET_DIR/icon_32x32.png"
    cp "$ASSETS_DIR/64.png"   "$ICONSET_DIR/icon_32x32@2x.png"
    cp "$ASSETS_DIR/128.png"  "$ICONSET_DIR/icon_128x128.png"
    cp "$ASSETS_DIR/256.png"  "$ICONSET_DIR/icon_128x128@2x.png"
    cp "$ASSETS_DIR/256.png"  "$ICONSET_DIR/icon_256x256.png"
    cp "$ASSETS_DIR/512.png"  "$ICONSET_DIR/icon_256x256@2x.png"
    cp "$ASSETS_DIR/512.png"  "$ICONSET_DIR/icon_512x512.png"
    cp "$ASSETS_DIR/1024.png" "$ICONSET_DIR/icon_512x512@2x.png"
    iconutil -c icns "$ICONSET_DIR" -o "$ICON_PATH"
    rm -rf "$(dirname "$ICONSET_DIR")"
    echo "  → Generated AppIcon.icns"
fi
cp "$ICON_PATH" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
echo "  → Copied app icon"

# Write PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "✓ App bundle created: $APP_BUNDLE"
echo ""

# ── Step 3: Code sign ─────────────────────────────────
if $DO_SIGN; then
    if [ -z "${DEVELOPER_ID:-}" ]; then
        echo "✗ DEVELOPER_ID not set. Example:"
        echo '  export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"'
        exit 1
    fi
    echo "▸ Code signing with: $DEVELOPER_ID"
    codesign --force --deep --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign "$DEVELOPER_ID" \
        "$APP_BUNDLE"
    echo "▸ Verifying signature..."
    codesign --verify --verbose=2 "$APP_BUNDLE"
    echo "✓ Code signed and verified"
    echo ""
fi

# ── Step 4: Create .dmg ──────────────────────────────
if $DO_DMG; then
    echo "▸ Creating .dmg..."
    rm -f "$DMG_PATH"

    create-dmg \
        --volname "$APP_NAME" \
        --volicon "$APP_BUNDLE/Contents/Resources/AppIcon.icns" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "$APP_NAME.app" 175 190 \
        --app-drop-link 425 190 \
        --hide-extension "$APP_NAME.app" \
        "$DMG_PATH" \
        "$APP_BUNDLE" \
        2>&1 || true

    if [ -f "$DMG_PATH" ]; then
        echo "✓ DMG created: $DMG_PATH"
    else
        echo "✗ DMG creation failed"
        exit 1
    fi

    # Sign the DMG too
    if $DO_SIGN && [ -n "${DEVELOPER_ID:-}" ]; then
        echo "▸ Signing .dmg..."
        codesign --force --sign "$DEVELOPER_ID" "$DMG_PATH"
        echo "✓ DMG signed"
    fi
    echo ""
fi

# ── Step 5: Notarize ─────────────────────────────────
if $DO_NOTARIZE; then
    if [ -z "${APPLE_ID:-}" ] || [ -z "${TEAM_ID:-}" ] || [ -z "${APP_PASSWORD:-}" ]; then
        echo "✗ Notarization requires these environment variables:"
        echo "  APPLE_ID     — your Apple ID email"
        echo "  TEAM_ID      — your Apple Developer Team ID"
        echo "  APP_PASSWORD — app-specific password"
        exit 1
    fi

    NOTARIZE_TARGET="$DMG_PATH"
    if [ ! -f "$NOTARIZE_TARGET" ]; then
        # If no DMG, zip the .app for notarization
        NOTARIZE_TARGET="$PROJECT_DIR/dist/${APP_NAME}.zip"
        echo "▸ Creating zip for notarization..."
        ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARIZE_TARGET"
    fi

    echo "▸ Submitting for notarization..."
    xcrun notarytool submit "$NOTARIZE_TARGET" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APP_PASSWORD" \
        --wait

    echo "▸ Stapling notarization ticket..."
    if [ -f "$DMG_PATH" ]; then
        xcrun stapler staple "$DMG_PATH"
    fi
    xcrun stapler staple "$APP_BUNDLE"

    echo "✓ Notarization complete"
    echo ""
fi

# ── Summary ───────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Done!"
echo ""
echo "  .app → $APP_BUNDLE"
if $DO_DMG && [ -f "$DMG_PATH" ]; then
    DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
    echo "  .dmg → $DMG_PATH ($DMG_SIZE)"
fi
echo ""
echo "  To test: open \"$APP_BUNDLE\""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
