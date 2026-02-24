#!/bin/bash

# G-Rump Development Builder — fast debug builds for development
# Double-click to build & run in debug mode
# If you see "access privileges" error: in Terminal run: chmod +x "build-dev.command"

cd "$(dirname "$0")"

# Use only local paths so we never touch ~/Library (avoids permission hangs at "Write swift-version...").
BUILD_DIR="$(pwd)/.build-dev"
mkdir -p "$BUILD_DIR/cache" "$BUILD_DIR/config" "$BUILD_DIR/security"

# Parse command line arguments
CLEAN_BUILD=false
VERBOSE=false
AUTO_RESTART=false

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
    --auto-restart)
      AUTO_RESTART=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--clean] [--verbose] [--auto-restart]"
      exit 1
      ;;
  esac
done

# Clean build if requested
if [ "$CLEAN_BUILD" = true ]; then
    echo "Cleaning previous build..."
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR/cache" "$BUILD_DIR/config" "$BUILD_DIR/security"
fi

# Build configuration
BUILD_CONFIG="debug"
BUILD_FLAGS="-c $BUILD_CONFIG"
if [ "$VERBOSE" = true ]; then
    BUILD_FLAGS="$BUILD_FLAGS --verbose"
fi

echo "Building G-Rump (debug) for faster development..."
echo "Build directory: $BUILD_DIR"
if [ "$AUTO_RESTART" = true ]; then
    echo "Auto-restart enabled: will restart on file changes"
fi
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
    echo "Tip: Try running with --clean to force a fresh build"
    read -p "Press Enter to close..."
    exit 1
fi

# Calculate build time
END_TIME=$(date +%s)
BUILD_TIME=$((END_TIME - START_TIME))

echo ""
echo "Build completed in ${BUILD_TIME}s"
echo "Launching G-Rump (debug mode)..."

# Launch the app
if [ "$AUTO_RESTART" = true ]; then
    echo "Auto-restart: Watching for file changes..."
    # Simple file watching loop
    while true; do
        exec swift run -c debug --skip-build GRump \
          --scratch-path "$BUILD_DIR" \
          --cache-path "$BUILD_DIR/cache" \
          --config-path "$BUILD_DIR/config" \
          --security-path "$BUILD_DIR/security"
        
        echo "App terminated. Restarting in 2 seconds..."
        sleep 2
    done
else
    exec swift run -c debug --skip-build GRump \
      --scratch-path "$BUILD_DIR" \
      --cache-path "$BUILD_DIR/cache" \
      --config-path "$BUILD_DIR/config" \
      --security-path "$BUILD_DIR/security"
fi
