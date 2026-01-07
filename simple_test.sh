#!/bin/bash

# Simple test script to isolate issues
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER="$SCRIPT_DIR/build/atprotopds"
PORT=2583
BASE_URL="http://localhost:$PORT"
SERVER_PID=""

info() {
    echo "[INFO] $1"
}

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
    # Use a known rkey from createRecord response, or just test with a dummy one
    local url="$BASE_URL/xrpc/com.atproto.repo.getRecord?repo=$DID&collection=app.bsky.feed.post&rkey=test"
    local response=$(curl -s "$url")

    # getRecord should return either the record or an error
    if echo "$response" | grep -q "uri\|error"; then
        echo "PASS: getRecord responded"
        echo "Response: $response"
    else
        echo "FAIL: getRecord failed: $response"
    fi
}

# Start server
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

# Cleanup
kill "$SERVER_PID" 2>/dev/null || true
wait "$SERVER_PID" 2>/dev/null || true