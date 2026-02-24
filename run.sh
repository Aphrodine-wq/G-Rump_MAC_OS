#!/bin/bash

# Build and run the executable in debug configuration (faster compile)
# Use `make build-release` or `make app` for optimized release builds.
JOBS=$(sysctl -n hw.ncpu)
swift run -j "$JOBS" GRump
