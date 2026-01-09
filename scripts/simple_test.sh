#!/bin/bash

# Simple test script to isolate issues
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER="$SCRIPT_DIR/build/atprotopds"
PORT=2583
BASE_URL="http://localhost:$PORT"
SERVER_PID=""
DB_PATH="/tmp/atproto_pds.db"

info() {
    echo "[INFO] $1"
}

cleanup() {
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        info "Stopping server (PID: $SERVER_PID)..."
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    pkill -f "atprotopds.*$PORT" 2>/dev/null || true
    rm -f "$DB_PATH" 2>/dev/null || true
}

trap cleanup EXIT

test_health() {
    info "Testing health endpoint..."
    local response=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/" 2>/dev/null || echo "000")
    if [ "$response" = "200" ] || [ "$response" = "404" ]; then
        echo "PASS: Server is responding (HTTP $response)"
    else
        echo "FAIL: Server not responding (HTTP $response)"
    fi
}

test_create_account() {
    info "Testing createAccount..."
    local timestamp=$(date +%s)
    local response=$(curl -s -X POST "$BASE_URL/xrpc/com.atproto.server.createAccount" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"test$timestamp@example.com\",
            \"password\": \"password123\",
            \"handle\": \"testuser$timestamp\"
        }")

    if echo "$response" | grep -q "did"; then
        DID=$(echo "$response" | grep -o '"did":"[^"]*"' | cut -d'"' -f4)
        echo "PASS: createAccount succeeded - DID: $DID"
    else
        echo "FAIL: createAccount failed: $response"
    fi
}

test_create_record() {
    if [ -z "$DID" ]; then
        echo "SKIP: test_create_record - no DID available"
        return
    fi

    info "Testing createRecord..."
    local response=$(curl -s -X POST "$BASE_URL/xrpc/com.atproto.repo.createRecord" \
        -H "Content-Type: application/json" \
        -d "{
            \"repo\": \"$DID\",
            \"collection\": \"app.bsky.feed.post\",
            \"record\": {
                \"\$type\": \"app.bsky.feed.post\",
                \"text\": \"Hello ATProto!\",
                \"createdAt\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
            }
        }")

    if echo "$response" | grep -q '"uri":'; then
        echo "PASS: createRecord succeeded"
        echo "Response: $response"
    else
        echo "FAIL: createRecord failed: $response"
    fi
}

test_list_records() {
    if [ -z "$DID" ]; then
        echo "SKIP: test_list_records - no DID available"
        return
    fi

    info "Testing listRecords..."
    local url="$BASE_URL/xrpc/com.atproto.repo.listRecords?repo=$DID&collection=app.bsky.feed.post"
    local response=$(curl -s "$url")

    if echo "$response" | grep -q "records"; then
        echo "PASS: listRecords succeeded"
        echo "Response: $response"
    else
        echo "FAIL: listRecords failed: $response"
    fi
}

test_get_record() {
    if [ -z "$DID" ]; then
        echo "SKIP: test_get_record - no DID available"
        return
    fi

    info "Testing getRecord..."
    local url="$BASE_URL/xrpc/com.atproto.repo.getRecord?repo=$DID&collection=app.bsky.feed.post&rkey=test"
    local response=$(curl -s "$url")

    if echo "$response" | grep -q "uri\|error"; then
        echo "PASS: getRecord responded"
        echo "Response: $response"
    else
        echo "FAIL: getRecord failed: $response"
    fi
}

# Start server
info "Starting ATProto PDS server..."
pkill -f "atprotopds.*$PORT" 2>/dev/null || true
sleep 1
rm -f "$DB_PATH" 2>/dev/null || true

"$SERVER" &
SERVER_PID=$!
sleep 2

if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "FAIL: Server failed to start"
    exit 1
fi

echo "PASS: Server started (PID: $SERVER_PID)"

test_health
test_create_account
test_create_record
test_get_record
test_list_records
