#!/bin/bash
set -e

# Cleanup function
cleanup() {
    echo "Stopping servers..."
    if [ -f plc.pid ]; then
        kill $(cat plc.pid) 2>/dev/null || true
        rm plc.pid
    fi
    if [ -f pds.pid ]; then
        kill $(cat pds.pid) 2>/dev/null || true
        rm pds.pid
    fi
    # Also ensure no strays are left on these ports
    pkill -f "campagnola.*2582" || true
    pkill -f "september.*2583" || true
}
trap cleanup EXIT

# Force cleanup of any existing stray servers before starting
echo "Cleaning up any existing stray servers..."
pkill -f "campagnola.*2582" || true
pkill -f "september.*2583" || true
rm -f plc.log pds.log
sleep 1

# Build paths
PLC_BIN="./build/bin/campagnola"
PDS_BIN="./build/bin/kaszlak"
DATA_DIR="${DATA_DIR:-/tmp/objpds-demo-data}"

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
mkdir -p "$DATA_DIR/service" # Pre-create service dir to be safe

echo "Starting PLC server on port 2582..."
"$PLC_BIN" --port 2582 > plc.log 2>&1 &
echo $! > plc.pid

# Wait for PLC to come up (local-only listener on 127.0.0.1)
echo "Waiting for PLC server to be ready..."
for i in {1..20}; do
    if curl -s --max-time 1 "http://127.0.0.1:2582/_health" >/dev/null 2>&1; then
        echo "PLC server is up!"
        break
    fi
    sleep 0.25
done

if ! curl -s --max-time 1 "http://127.0.0.1:2582/_health" >/dev/null 2>&1; then
    echo "Error: PLC server failed to start. plc.log tail:"
    tail -n 80 plc.log || true
    exit 1
fi

echo "Starting PDS server on port 2583..."
export PDS_PLC_URL="http://127.0.0.1:2582"
export PDS_DEBUG_SKIP_PLC="0"
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
