#!/bin/bash
set -e

# Get the directory of the script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ROOT_DIR/build"

# Check for build type argument
BUILD_TYPE="${1:-Debug}"

echo "=== ATProtoPDS Build ($BUILD_TYPE) ==="

# Check if cmake is installed
if ! command -v cmake &> /dev/null; then
    echo "Error: cmake is not installed."
    exit 1
fi

echo "Configuring in $BUILD_DIR..."
cmake -B "$BUILD_DIR" -S "$ROOT_DIR" \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON

echo "Building..."
cmake --build "$BUILD_DIR" -j$(sysctl -n hw.ncpu 2>/dev/null || echo 4)

echo "Build complete."
