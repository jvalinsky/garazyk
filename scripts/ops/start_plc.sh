#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/../.." && pwd))"
BIN_DIR="$REPO_ROOT/build/bin"

if [ ! -f "$BIN_DIR/campagnola" ]; then
    echo "Error: campagnola binary not found. Build it first with CMake."
    exit 1
fi

exec "$BIN_DIR/campagnola" "$@"
