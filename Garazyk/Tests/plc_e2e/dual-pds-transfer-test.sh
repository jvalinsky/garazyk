#!/bin/bash
set -eo pipefail

echo "=========================================="
echo " Starting Dual-PDS PLC Integration Test "
echo "=========================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Build directories
BUILD_DIR="${ROOT_DIR}/build"
CLI_BIN="${BUILD_DIR}/bin/kaszlak"
PLC_BIN="${BUILD_DIR}/bin/campagnola"

killall kaszlak campagnola 2>/dev/null || true

if [ ! -f "$CLI_BIN" ] || [ ! -f "$PLC_BIN" ]; then
    echo "ERROR: Required binaries not found. Please build the project first."
    exit 1
fi

TEMP_DIR=$(mktemp -d)
trap 'echo "Cleaning up..."; killall kaszlak campagnola 2>/dev/null || true; kill $(jobs -p) 2>/dev/null || true; rm -rf "$TEMP_DIR"' EXIT

PLC_PORT=2582
PDS_A_PORT=8001
PDS_B_PORT=8002

PLC_DATA="${TEMP_DIR}/plc"
PDS_A_DATA="${TEMP_DIR}/pds_a"
PDS_B_DATA="${TEMP_DIR}/pds_b"

mkdir -p "$PLC_DATA" "$PDS_A_DATA" "$PDS_B_DATA"

cat <<EOF > "$PDS_A_DATA/config.json"
{
  "server": {
    "host": "127.0.0.1:$PDS_A_PORT",
    "port": $PDS_A_PORT,
    "data_dir": "$PDS_A_DATA"
  }
}
EOF

cat <<EOF > "$PDS_B_DATA/config.json"
{
  "server": {
    "host": "127.0.0.1:$PDS_B_PORT",
    "port": $PDS_B_PORT,
    "data_dir": "$PDS_B_DATA"
  }
}
EOF

export PDS_ADMIN_PASSWORD=admin
export PDS_PLC_URL="http://127.0.0.1:$PLC_PORT"
export PDS_DEBUG_SKIP_PLC=0

echo "-> Starting PLC Server on port $PLC_PORT..."
"$PLC_BIN" serve --port $PLC_PORT --database "$PLC_DATA/plc.db" &
PLC_PID=$!
sleep 2

echo "-> Starting PDS Server A on port $PDS_A_PORT..."
"$CLI_BIN" serve --data-dir "$PDS_A_DATA" --config "$PDS_A_DATA/config.json" --port $PDS_A_PORT &
PDS_A_PID=$!
sleep 2

echo "-> Starting PDS Server B on port $PDS_B_PORT..."
"$CLI_BIN" serve --data-dir "$PDS_B_DATA" --config "$PDS_B_DATA/config.json" --port $PDS_B_PORT &
PDS_B_PID=$!
sleep 2

echo "-> Creating account 'alice.test' on PDS A..."
# We explicitly do NOT use interactive prompt by providing all arguments
ATPROTO_INTERACTIVE=0 "$CLI_BIN" account create \
    --data-dir "$PDS_A_DATA" \
    --config "$PDS_A_DATA/config.json" \
    --email alice@example.com \
    --handle alice.test \
    --password secret \
    --verbose

echo "-> Waiting for account to sync..."
sleep 2

echo "-> Resolving alice.test via PLC to confirm PDS A configuration..."
# Get the DID from the database on Node A
DID=$("$CLI_BIN" account info \
    --data-dir "$PDS_A_DATA" \
    --config "$PDS_A_DATA/config.json" \
    alice.test | grep 'DID:' | awk '{print $2}')

if [ -z "$DID" ]; then
     echo "ERROR: DID could not be extracted from PDS A database."
     exit 1
fi
echo "Resolved DID: $DID"

echo "-> Verifying PDS A is the endpoint in PLC..."
PLC_RES=$(curl -s "http://127.0.0.1:$PLC_PORT/$DID")
if [[ "$PLC_RES" != *"127.0.0.1:8001"* ]]; then
    echo "ERROR: PLC does not point to PDS A. Response:"
    echo "$PLC_RES"
    exit 1
fi
echo "SUCCESS: PLC correctly points to PDS A."

echo "-> Updating PLC endpoint to point to PDS B..."
"$CLI_BIN" account update-plc-endpoint \
    --verbose \
    --data-dir "$PDS_A_DATA" \
    --config "$PDS_A_DATA/config.json" \
    "$DID" "http://127.0.0.1:8002" || { echo "ERROR: failed to update PLC endpoint"; exit 1; }

sleep 2

echo "-> Verifying PLC now points to PDS B..."
PLC_RES_B=$(curl -s "http://127.0.0.1:$PLC_PORT/$DID")
if [[ "$PLC_RES_B" != *"127.0.0.1:8002"* ]]; then
    echo "ERROR: PLC does not point to PDS B after update. Response:"
    echo "$PLC_RES_B"
    exit 1
fi
echo "SUCCESS: PLC correctly points to PDS B."

echo "=========================================="
echo " Dual-PDS Transfer Test SUCCESSFUL "
echo "=========================================="
exit 0
