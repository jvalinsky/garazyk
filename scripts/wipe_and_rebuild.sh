#!/bin/bash
set -e

# Default data directory for macOS
DATA_DIR="$HOME/Library/Application Support/ATProtoPDS"
LOCAL_SHARE_DIR="$HOME/.local/share/ATProtoPDS"

echo "⚠️  This will delete all build artifacts and the local PDS database."
echo "   Data directories to be wiped:"
echo "     - $DATA_DIR"
echo "     - $LOCAL_SHARE_DIR"
echo "     - ./data"
read -p "Are you sure? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo "🧹 Wiping build artifacts..."
rm -rf build
mkdir build

echo "🧹 Wiping local database..."
rm -rf "$DATA_DIR"
rm -rf "$LOCAL_SHARE_DIR"
rm -rf ./data

echo "⚙️  Configuring CMake..."
cd build
cmake ..

echo "🔨 Building..."
make -j8

echo "✅ Wipe and rebuild complete!"
echo "   Run './kaszlak' to start the server or './tests/AllTests' to run tests."
