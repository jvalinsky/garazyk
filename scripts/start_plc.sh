#!/bin/bash
BIN_DIR="$(dirname "$0")/../build/bin"

if [ ! -f "$BIN_DIR/campagnola" ]; then
    echo "Error: campagnola binary not found. Build it first with CMake."
    exit 1
fi

exec "$BIN_DIR/campagnola" "$@"
