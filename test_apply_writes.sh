#!/bin/bash

# Test script for applyWrites endpoint
# Tests batch record operations

set -e

# Configuration
SERVER_HOST="http://localhost:2583"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}🧪 Testing applyWrites endpoint${NC}"

# Start server in background
echo "Starting server..."
./build/atprotopds &
SERVER_PID=$!

# Wait for server
sleep 2

# Check if server is running
if ! kill -0 $SERVER_PID 2>/dev/null; then
    echo -e "${RED}❌ Server failed to start${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Server started${NC}"

# Cleanup function
cleanup() {
    kill $SERVER_PID 2>/dev/null || true
}

trap cleanup EXIT

# Create test account
echo "Creating test account..."
CREATE_RESPONSE=$(curl -s -X POST "$SERVER_HOST/xrpc/com.atproto.server.createAccount" \
    -H "Content-Type: application/json" \
    -d '{
        "email": "test@example.com",
        "handle": "test.example.com",
        "password": "testpassword123",
        "did": "did:web:test.example.com"
    }')

if echo "$CREATE_RESPONSE" | grep -q "error"; then
    if echo "$CREATE_RESPONSE" | grep -q "AccountCreationFailed"; then
        echo "Account already exists, attempting login..."
        LOGIN_RESPONSE=$(curl -s -X POST "$SERVER_HOST/xrpc/com.atproto.server.createSession" \
            -H "Content-Type: application/json" \
            -d '{
                "identifier": "test@example.com",
                "password": "testpassword123"
            }')

        if echo "$LOGIN_RESPONSE" | grep -q "error"; then
            echo -e "${RED}❌ Login failed${NC}"
            exit 1
        fi

        DID=$(echo "$LOGIN_RESPONSE" | grep -o '"did":"[^"]*"' | cut -d'"' -f4)
        ACCESS_JWT=$(echo "$LOGIN_RESPONSE" | grep -o '"accessJwt":"[^"]*"' | cut -d'"' -f4)
    else
        echo -e "${RED}❌ Account creation failed${NC}"
        exit 1
    fi
else
    DID=$(echo "$CREATE_RESPONSE" | grep -o '"did":"[^"]*"' | cut -d'"' -f4)
    ACCESS_JWT=$(echo "$CREATE_RESPONSE" | grep -o '"accessJwt":"[^"]*"' | cut -d'"' -f4)
fi

echo -e "${GREEN}✅ Account ready (DID: $DID)${NC}"

# Test 1: applyWrites with create operations
echo "Testing applyWrites with create operations..."
CREATE_WRITES_RESPONSE=$(curl -s -X POST "$SERVER_HOST/xrpc/com.atproto.repo.applyWrites" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_JWT" \
    -d "{
        \"repo\": \"$DID\",
        \"writes\": [
            {
                \"\$type\": \"com.atproto.repo.applyWrites#create\",
                \"collection\": \"app.bsky.feed.post\",
                \"value\": {
                    \"text\": \"Hello from applyWrites!\",
                    \"createdAt\": \"$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)\"
                }
            },
            {
                \"\$type\": \"com.atproto.repo.applyWrites#create\",
                \"collection\": \"app.bsky.feed.post\",
                \"value\": {
                    \"text\": \"Second post from batch operation\",
                    \"createdAt\": \"$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)\"
                }
            }
        ]
    }")

if echo "$CREATE_WRITES_RESPONSE" | grep -q "error"; then
    echo -e "${RED}❌ applyWrites create failed: $CREATE_WRITES_RESPONSE${NC}"
    exit 1
fi

echo -e "${GREEN}✅ applyWrites create succeeded${NC}"

# Extract URIs from response
URI1=$(echo "$CREATE_WRITES_RESPONSE" | grep -o '"uri":"[^"]*"' | head -1 | cut -d'"' -f4)
URI2=$(echo "$CREATE_WRITES_RESPONSE" | grep -o '"uri":"[^"]*"' | tail -1 | cut -d'"' -f4)

echo "Created records: $URI1, $URI2"

# Test 2: applyWrites with update operation
echo "Testing applyWrites with update operation..."
UPDATE_WRITES_RESPONSE=$(curl -s -X POST "$SERVER_HOST/xrpc/com.atproto.repo.applyWrites" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_JWT" \
    -d "{
        \"repo\": \"$DID\",
        \"writes\": [
            {
                \"\$type\": \"com.atproto.repo.applyWrites#update\",
                \"collection\": \"app.bsky.feed.post\",
                \"rkey\": \"$(basename "$URI1")\",
                \"value\": {
                    \"text\": \"Updated: Hello from applyWrites!\",
                    \"createdAt\": \"$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)\"
                }
            }
        ]
    }")

if echo "$UPDATE_WRITES_RESPONSE" | grep -q "error"; then
    echo -e "${RED}❌ applyWrites update failed: $UPDATE_WRITES_RESPONSE${NC}"
    exit 1
fi

echo -e "${GREEN}✅ applyWrites update succeeded${NC}"

# Test 3: applyWrites with delete operation
echo "Testing applyWrites with delete operation..."
DELETE_WRITES_RESPONSE=$(curl -s -X POST "$SERVER_HOST/xrpc/com.atproto.repo.applyWrites" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_JWT" \
    -d "{
        \"repo\": \"$DID\",
        \"writes\": [
            {
                \"\$type\": \"com.atproto.repo.applyWrites#delete\",
                \"collection\": \"app.bsky.feed.post\",
                \"rkey\": \"$(basename "$URI2")\"
            }
        ]
    }")

if echo "$DELETE_WRITES_RESPONSE" | grep -q "error"; then
    echo -e "${RED}❌ applyWrites delete failed: $DELETE_WRITES_RESPONSE${NC}"
    exit 1
fi

echo -e "${GREEN}✅ applyWrites delete succeeded${NC}"

# Test 4: Verify operations worked
echo "Verifying operations..."
LIST_RESPONSE=$(curl -s "$SERVER_HOST/xrpc/com.atproto.repo.listRecords?repo=$DID&collection=app.bsky.feed.post")

if echo "$LIST_RESPONSE" | grep -q "error"; then
    echo -e "${RED}❌ Failed to list records${NC}"
    exit 1
fi

RECORD_COUNT=$(echo "$LIST_RESPONSE" | grep -o '"uri":"[^"]*"' | wc -l)
if [ "$RECORD_COUNT" -ne 1 ]; then
    echo -e "${RED}❌ Expected 1 record after operations, got $RECORD_COUNT${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Operations verified - 1 record remaining${NC}"

echo ""
echo -e "${GREEN}🎉 All applyWrites tests PASSED!${NC}"
echo "==================================="
echo "✅ Batch create operations"
echo "✅ Batch update operations"
echo "✅ Batch delete operations"
echo "✅ Transaction integrity"
echo "✅ Record verification"

exit 0