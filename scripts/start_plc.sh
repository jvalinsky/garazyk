#!/bin/bash
BIN_DIR="$(dirname "$0")/../build/bin"
if [ ! -f "$BIN_DIR/atproto-plc" ]; then
    BIN_DIR="$(dirname "$0")/../build/Debug"
fi

if [ ! -f "$BIN_DIR/atproto-plc" ]; then
    echo "Error: atproto-plc binary not found. Build it first with xcodebuild."
    exit 1
fi

exec "$BIN_DIR/atproto-plc" "$@"
