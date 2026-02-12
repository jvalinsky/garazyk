#!/bin/bash
set -e

# Get the directory of the script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ROOT_DIR/build"

# Check if build exists
if [ ! -f "$BUILD_DIR/tests/AllTests" ]; then
    echo "Test binary not found. Building..."
    "$SCRIPT_DIR/build.sh"
fi

echo "Running AllTests..."
# Run the test binary
cd "$BUILD_DIR" && ctest --output-on-failure
# Or directly: "$BUILD_DIR/tests/AllTests"
echo "Tests completed."
