#!/usr/bin/env bash

# This script demonstrates PDS operations on Linux:
# 1. Creating accounts (Alice and Bob)
# 2. Creating various record types (Post, Follow, Like, Reply, Block)
# 3. Verifying the records and their CIDs

set -e

# Source GNUstep environment if needed
if [ -f /usr/GNUstep/System/Library/Makefiles/GNUstep.sh ]; then
    . /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
CLI="$PROJECT_ROOT/build/bin/atprotopds-cli"
DATA="$PROJECT_ROOT/data"

if [ ! -f "$CLI" ]; then
    echo "Error: CLI not found at $CLI. Please build it first."
    exit 1
fi

echo "--- Cleaning data directory ---"
rm -rf "$DATA"
mkdir -p "$DATA"

echo "--- Creating accounts ---"
"$CLI" account create --email alice@test.com --handle alice.test --data-dir "$DATA"
"$CLI" account create --email bob@test.com --handle bob.test --data-dir "$DATA"

# Capture DIDs
ALICE=$("$CLI" account info alice.test --data-dir "$DATA" --json | grep -o '"did":"[^"]*"' | head -1 | cut -d'"' -f4)
BOB=$("$CLI" account info bob.test --data-dir "$DATA" --json | grep -o '"did":"[^"]*"' | head -1 | cut -d'"' -f4)

echo "Alice DID: $ALICE"
echo "Bob DID:   $BOB"

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "--- Creating Alice's first post ---"
# Note: In ATProto, the record content itself is what is hashed to create the CID.
"$CLI" repo create-record "$ALICE" "app.bsky.feed.post" "post1" \
    "{\"\$type\": \"app.bsky.feed.post\", \"text\": \"Hello from Linux PDS!\", \"createdAt\": \"$NOW\"}" \
    --data-dir "$DATA"

echo "--- Bob follows Alice ---"
"$CLI" repo create-record "$BOB" "app.bsky.graph.follow" "follow1" \
    "{\"\$type\": \"app.bsky.graph.follow\", \"subject\": \"$ALICE\", \"createdAt\": \"$NOW\"}" \
    --data-dir "$DATA"

echo "--- Fetching Post 1 CID for referencing ---"
POST1_JSON=$("$CLI" repo get "$ALICE" "at://$ALICE/app.bsky.feed.post/post1" --data-dir "$DATA" --json)
POST1_CID=$(echo "$POST1_JSON" | grep -o '"cid":"[^"]*"' | head -1 | cut -d'"' -f4)
echo "Post 1 CID: $POST1_CID"

echo "--- Bob likes Alice's post ---"
# References in ATProto require both the URI and the CID of the target to ensure the reference is to a specific version of content.
"$CLI" repo create-record "$BOB" "app.bsky.feed.like" "like1" \
    "{\"\$type\": \"app.bsky.feed.like\", \"subject\": {\"uri\": \"at://$ALICE/app.bsky.feed.post/post1\", \"cid\": \"$POST1_CID\"}, \"createdAt\": \"$NOW\"}" \
    --data-dir "$DATA"

echo "--- Bob replies to Alice ---"
"$CLI" repo create-record "$BOB" "app.bsky.feed.post" "post2" \
    "{\"\$type\": \"app.bsky.feed.post\", \"text\": \"Welcome Alice!\", \"reply\": {\"root\": {\"uri\": \"at://$ALICE/app.bsky.feed.post/post1\", \"cid\": \"$POST1_CID\"}, \"parent\": {\"uri\": \"at://$ALICE/app.bsky.feed.post/post1\", \"cid\": \"$POST1_CID\"}}, \"createdAt\": \"$NOW\"}" \
    --data-dir "$DATA"

echo "--- Alice blocks Bob ---"
"$CLI" repo create-record "$ALICE" "app.bsky.graph.block" "block1" \
    "{\"\$type\": \"app.bsky.graph.block\", \"subject\": \"$BOB\", \"createdAt\": \"$NOW\"}" \
    --data-dir "$DATA"

echo ""
echo "--- Verification: Alice's Repo ---"
"$CLI" repo list "$ALICE" --data-dir "$DATA"
echo ""
echo "--- Verification: Bob's Repo ---"
"$CLI" repo list "$BOB" --data-dir "$DATA"

echo ""
echo "PDS Operation Demo Complete."
