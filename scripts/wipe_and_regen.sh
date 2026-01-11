#!/bin/bash
set -e

# Build CLI
echo "Building CLI..."
xcodebuild -scheme ATProtoPDS-CLI build > /dev/null

CLI="./build/bin/atprotopds-cli"
DATA_DIR="$(pwd)/data"

# Stop existing server
echo "Stopping existing server..."
pkill -f atprotopds-cli || true

# Wipe data
echo "Wiping data directory: $DATA_DIR"
rm -rf "$DATA_DIR"
mkdir -p "$DATA_DIR"

# Start server
echo "Starting PDS server..."
$CLI serve --data-dir "$DATA_DIR" > server.log 2>&1 &
SERVER_PID=$!

echo "Waiting for server to start (PID: $SERVER_PID)..."
sleep 5

# Create accounts
echo "Creating accounts..."
$CLI account create --handle alice.test --email alice@test.com --password password123
$CLI account create --handle bob.test --email bob@test.com --password password123
$CLI account create --handle charlie.test --email charlie@test.com --password password123
$CLI account create --handle dana.test --email dana@test.com --password password123

# Create interactions using curl (since CLI doesn't support creating records yet)
echo "Creating interactions..."

# Get DIDs
ALICE_DID=$($CLI account list | grep alice.test | awk '{print $1}')
BOB_DID=$($CLI account list | grep bob.test | awk '{print $1}')
CHARLIE_DID=$($CLI account list | grep charlie.test | awk '{print $1}')
DANA_DID=$($CLI account list | grep dana.test | awk '{print $1}')

echo "DIDs:"
echo "Alice: $ALICE_DID"
echo "Bob: $BOB_DID"
echo "Charlie: $CHARLIE_DID"
echo "Dana: $DANA_DID"

# Helper function for creating records
create_record() {
    local did=$1
    local collection=$2
    local record=$3
    curl -s -X POST "http://localhost:2583/xrpc/com.atproto.repo.createRecord" \
        -H "Content-Type: application/json" \
        -d "{\"repo\": \"$did\", \"collection\": \"$collection\", \"record\": $record}"
}

# Posts
echo "Creating posts..."
create_record "$ALICE_DID" "app.bsky.feed.post" "{\"text\": \"Hello World!\", \"createdAt\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
create_record "$BOB_DID" "app.bsky.feed.post" "{\"text\": \"Bob here.\", \"createdAt\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"

# Follows
echo "Creating follows..."
create_record "$ALICE_DID" "app.bsky.graph.follow" "{\"subject\": \"$BOB_DID\", \"createdAt\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
create_record "$BOB_DID" "app.bsky.graph.follow" "{\"subject\": \"$ALICE_DID\", \"createdAt\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"

# Test Explore API
echo "Testing Explore API..."
curl -s "http://localhost:2583/explore/api/describe?did=$ALICE_DID" > explore.json
if grep -q "\"handle\":\"alice.test\"" explore.json; then
    echo "Explore API OK"
else
    echo "Explore API FAILED"
    cat explore.json
fi

echo "Data regeneration complete."
echo "Server is running at PID $SERVER_PID"
echo "Press Ctrl+C to stop."
wait $SERVER_PID
