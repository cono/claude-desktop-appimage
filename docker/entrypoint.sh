#!/bin/bash
set -euo pipefail

# Copy source to a temporary working directory so build artifacts
# never touch the mounted source or output directories
WORK=/tmp/build
cp -a /build/src/. "$WORK/"
cd "$WORK"

# Run the build
./build.sh --clean no "$@"

# Copy only the final artifacts to the output mount
cp -v ./*.AppImage /build/output/ 2>/dev/null || echo "Warning: No AppImage files found"
cp -v ./*.desktop /build/output/ 2>/dev/null || true
