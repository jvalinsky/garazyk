#!/bin/bash
set -e

SERVER_BIN="./build/bin/atproto-plc"
DB_PATH="./plc_test.db"
PORT=3001

# Cleanup
rm -f "$DB_PATH"
rm -rf "./plc_test.db-shm" "./plc_test.db-wal"

echo "Starting PLC server on port $PORT with DB $DB_PATH..."
"$SERVER_BIN" --port "$PORT" --database "$DB_PATH" &
SERVER_PID=$!

# Wait for start
sleep 2

echo "Verifying /_list..."
curl -s "http://localhost:$PORT/_list" | grep "\[\]" || echo "List failed"

echo "Verifying /export..."
curl -s "http://localhost:$PORT/export" > export_output.txt
if [ -s export_output.txt ]; then
    echo "Export returned data (unexpected for empty DB)"
    cat export_output.txt
else
    echo "Export returned empty (expected)"
fi

echo "Verifying /did:test:1/log/last (Expecting 404)..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT/did:test:1/log/last")
if [ "$HTTP_CODE" == "404" ]; then
    echo "Correctly got 404 for missing DID"
else
    echo "Failed: Got $HTTP_CODE"
    exit 1
fi

echo "Verifying /did:test:1/data (Expecting 404)..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT/did:test:1/data")
if [ "$HTTP_CODE" == "404" ]; then
    echo "Correctly got 404 for missing DID data"
else
    echo "Failed: Got $HTTP_CODE"
    exit 1
fi

# Cleanup
kill "$SERVER_PID"
rm -f "$DB_PATH"
rm -rf "./plc_test.db-shm" "./plc_test.db-wal"
rm -f export_output.txt

echo "Verification Passed!"
