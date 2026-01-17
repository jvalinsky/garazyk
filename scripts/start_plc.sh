#!/bin/bash
BIN_DIR="$(dirname "$0")/../build/bin"

if [ ! -f "$BIN_DIR/atproto-plc" ]; then
    echo "Error: atproto-plc binary not found. Build it first with CMake."
    exit 1
fi

exec "$BIN_DIR/atproto-plc" "$@"
