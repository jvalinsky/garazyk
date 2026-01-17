#!/bin/bash
set -e

# Cleanup function
cleanup() {
    echo "Stopping servers..."
    if [ -f plc.pid ]; then
        kill $(cat plc.pid) || true
        rm plc.pid
    fi
    if [ -f pds.pid ]; then
        kill $(cat pds.pid) || true
        rm pds.pid
    fi
}
trap cleanup EXIT

# Build paths
PLC_BIN="./build/bin/atproto-plc"
PDS_BIN="./build/bin/september"
DATA_DIR="./demo_data"

if [ ! -f "$PLC_BIN" ]; then
    echo "Error: $PLC_BIN not found"
    exit 1
fi
if [ ! -f "$PDS_BIN" ]; then
    echo "Error: $PDS_BIN not found"
    exit 1
fi

# IMPORTANT: Clean previous data to ensure fresh DB and avoid migration issues if previous run failed halfway
rm -rf "$DATA_DIR"
mkdir -p "$DATA_DIR"

echo "Starting PLC server on port 2582..."
"$PLC_BIN" --port 2582 > plc.log 2>&1 &
echo $! > plc.pid
sleep 2

echo "Starting PDS server on port 2583..."
export PDS_PLC_URL="http://localhost:2582"
export PDS_ISSUER="http://localhost:2583"
export PDS_LOG_LEVEL="debug"
# Note: we pass a fake config file to ensure CLI arg for data-dir is respected
"$PDS_BIN" serve --port 2583 --data-dir "$DATA_DIR" --config /tmp/missing_config_to_force_args.json --log-level debug > pds.log 2>&1 &
echo $! > pds.pid
sleep 5

echo "Servers running. Running seed script..."
export PDS_URL="http://localhost:2583"
export PDS_DATA_DIR="$DATA_DIR"
export PDS_BIN="$PDS_BIN"
python3 scripts/demo_seed.py

echo "Demo complete."
echo "Servers are still running at http://localhost:2583"
echo "Press Ctrl+C to stop."

# Wait for background processes
wait
