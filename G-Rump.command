#!/bin/bash

# G-Rump Launcher — double-click to build & run.
# If you see "access privileges" error: in Terminal run: chmod +x "G-Rump.command"
# Usage: ./G-Rump.command [--clean] [--verbose] [--dev]
#   --clean: Force clean build
#   --verbose: Show detailed build output
#   --dev: Use debug build instead of release (faster compilation)
# See LAUNCH.md for more options.

cd "$(dirname "$0")"

# Parse command line arguments
CLEAN_BUILD=false
VERBOSE=false
DEV_MODE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --clean)
      CLEAN_BUILD=true
      shift
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    --dev)
      DEV_MODE=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--clean] [--verbose] [--dev]"
      exit 1
      ;;
  esac
done

# Use only local paths so we never touch ~/Library (avoids permission hangs at "Write swift-version...").
BUILD_DIR="$(pwd)/.build"
if [ "$DEV_MODE" = true ]; then
    BUILD_DIR="$(pwd)/.build-dev"
fi
mkdir -p "$BUILD_DIR/cache" "$BUILD_DIR/config" "$BUILD_DIR/security"

# Clean build if requested
if [ "$CLEAN_BUILD" = true ]; then
    echo "Cleaning previous build..."
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR/cache" "$BUILD_DIR/config" "$BUILD_DIR/security"
fi

# Build configuration
BUILD_CONFIG="release"
if [ "$DEV_MODE" = true ]; then
    BUILD_CONFIG="debug"
fi

BUILD_FLAGS="-c $BUILD_CONFIG"
if [ "$VERBOSE" = true ]; then
    BUILD_FLAGS="$BUILD_FLAGS --verbose"
fi

echo "Building G-Rump ($BUILD_CONFIG)..."
if [ "$DEV_MODE" = true ]; then
    echo "Development mode: Faster compilation, debug symbols included"
fi
echo "(First build may take 1–2 minutes.)"
echo "Build directory: $BUILD_DIR"
echo ""

# Start build timer
START_TIME=$(date +%s)

if ! swift build $BUILD_FLAGS \
  --scratch-path "$BUILD_DIR" \
  --cache-path "$BUILD_DIR/cache" \
  --config-path "$BUILD_DIR/config" \
  --security-path "$BUILD_DIR/security" \
  --manifest-cache local; then
    echo ""
    echo "Build failed. Check the errors above."
    echo "Tips:"
    echo "  - Try running with --clean to force a fresh build"
    echo "  - Try running with --dev for faster debug builds"
    echo "  - Use build-dev.command for development workflow"
    read -p "Press Enter to close..."
    exit 1
fi

# Calculate build time
END_TIME=$(date +%s)
BUILD_TIME=$((END_TIME - START_TIME))

echo ""
echo "Build completed in ${BUILD_TIME}s"
echo "Launching G-Rump..."
exec swift run -c $BUILD_CONFIG --skip-build GRump \
  --scratch-path "$BUILD_DIR" \
  --cache-path "$BUILD_DIR/cache" \
  --config-path "$BUILD_DIR/config" \
  --security-path "$BUILD_DIR/security"
