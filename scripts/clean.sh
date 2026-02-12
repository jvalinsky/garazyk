#!/bin/bash
set -e

# Get the directory of the script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "Cleaning build artifacts in $ROOT_DIR..."

if [ -d "$ROOT_DIR/build" ]; then
    echo "Removing build/..."
    rm -rf "$ROOT_DIR/build"
fi

if [ -d "$ROOT_DIR/build_verify" ]; then
    echo "Removing build_verify/..."
    rm -rf "$ROOT_DIR/build_verify"
fi

if [ -d "$ROOT_DIR/DerivedData" ]; then
    echo "Removing DerivedData/..."
    rm -rf "$ROOT_DIR/DerivedData"
fi

if [ -d "$ROOT_DIR/.cache" ]; then
    echo "Removing .cache/..."
    rm -rf "$ROOT_DIR/.cache"
fi

# Clean logs
echo "Removing logs..."
rm -f "$ROOT_DIR"/*.log
rm -f "$ROOT_DIR/scripts"/*.log

# Clean node_modules if present
if [ -d "$ROOT_DIR/docs/site/node_modules" ]; then
    echo "Removing docs/site/node_modules..."
    rm -rf "$ROOT_DIR/docs/site/node_modules"
fi

echo "Cleaning complete."
