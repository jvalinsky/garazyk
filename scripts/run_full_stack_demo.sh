#!/bin/bash
set -e

DEMO_ROOT="/tmp/atproto-demo"
mkdir -p "$DEMO_ROOT"

# Cleanup function
cleanup() {
    echo "Stopping all servers..."
    pkill -f "campagnola.*2582" || true
    pkill -f "kaszlak.*2583" || true
    pkill -f "zuk.*2584" || true
    pkill -f "syrena.*3200" || true
    sleep 1
}
trap cleanup EXIT

# Force cleanup
cleanup
rm -rf "$DEMO_ROOT"/*
mkdir -p "$DEMO_ROOT/plc" "$DEMO_ROOT/pds" "$DEMO_ROOT/relay" "$DEMO_ROOT/appview"

PLC_BIN="./build/bin/campagnola"
PDS_BIN="./build/bin/kaszlak"
RELAY_BIN="./build/bin/zuk"
APPVIEW_BIN="./build/bin/syrena"

# 1. Start PLC
echo "==> Starting PLC (campagnola) on port 2582..."
# Campagnola doesn't support --verbose
"$PLC_BIN" serve --port 2582 --database "$DEMO_ROOT/plc/plc.db" > "$DEMO_ROOT/plc.log" 2>&1 &

# ...

# 2. Start PDS
echo "==> Starting PDS (kaszlak) on port 2583..."
export PDS_PLC_URL="http://127.0.0.1:2582"
export PDS_ISSUER="http://127.0.0.1:2583"
export PDS_MASTER_SECRET="32107992c973da8445b485263cb2bd3157859cb94294a2355e3c4a7b0f825afe"
export PDS_ADMIN_PASSWORD="localdevadmin"
export PDS_LOG_LEVEL="debug"
"$PDS_BIN" serve --port 2583 --data-dir "$DEMO_ROOT/pds" --config /tmp/missing.json --foreground --verbose > "$DEMO_ROOT/pds.log" 2>&1 &


# ...

# 3. Start Relay
echo "==> Starting Relay (zuk) on port 2584..."
# Give PDS more time to start before Relay connects
sleep 5
export RELAY_ADMIN_PASSWORD="localdevadmin"
"$RELAY_BIN" serve --port 2584 --data-dir "$DEMO_ROOT/relay" --upstream "http://127.0.0.1:2583" --verbose > "$DEMO_ROOT/relay.log" 2>&1 &

# ...

# 4. Start AppView
echo "==> Starting AppView (syrena) on port 3200..."
export APPVIEW_PLC_URL="http://localhost:2582"
export APPVIEW_DATA_DIR="$DEMO_ROOT/appview"
export APPVIEW_ADMIN_SECRET="localdevadmin"
export PDS_ADMIN_SECRET="localdevadmin"
"$APPVIEW_BIN" serve --port 3200 --data-dir "$DEMO_ROOT/appview" --relay "http://127.0.0.1:2584" --verbose > "$DEMO_ROOT/appview.log" 2>&1 &



for i in {1..20}; do
    if curl -s -H "Authorization: Bearer localdevadmin" "http://127.0.0.1:3200/admin/backfill/status" >/dev/null; then
        echo "  ✓ AppView is up"
        break
    fi
    sleep 0.5
done

# Give some extra time for connections to stabilize
sleep 2

# 5. Create accounts & records (Now all services are listening and connected)
echo "==> Seeding PDS with accounts and records via XRPC..."
export PDS_URL="http://127.0.0.1:2583"
export PDS_DATA_DIR="$DEMO_ROOT/pds"
export PDS_BIN="$PDS_BIN"
python3 scripts/demo_seed.py

# Give some time for indexing
echo "==> Waiting for indexing..."
sleep 15

# 6. Verification
echo ""
echo "==> STACK VERIFICATION"
echo "======================"

echo "PDS Discovery:"
curl -s "http://127.0.0.1:2583/xrpc/com.atproto.server.describeServer" | jq .

echo "Relay Health:"
curl -s "http://127.0.0.1:2584/api/relay/health" | jq .

echo "AppView Backfill Status:"
curl -s -H "Authorization: Bearer localdevadmin" "http://127.0.0.1:3200/admin/backfill/status" | jq .

echo "Checking if Alice exists in AppView..."
for i in {1..5}; do
    PROFILE=$(curl -s "http://127.0.0.1:3200/xrpc/app.bsky.actor.getProfile?actor=alice.test")
    if echo "$PROFILE" | grep -q "Alice"; then
        echo "  ✓ Alice found in AppView!"
        echo "$PROFILE" | jq .
        break
    else
        echo "  ... Alice not indexed yet (attempt $i)"
        # Force AppView to index Alice if it hasn't found her yet
        if [ $i -eq 2 ]; then
            ALICE_DID=$(curl -s "http://127.0.0.1:2583/xrpc/com.atproto.identity.resolveHandle?handle=alice.test" | jq -r .did)
            if [ "$ALICE_DID" != "null" ]; then
                echo "  (Forcing backfill for Alice: $ALICE_DID)"
                curl -s -X POST -H "Authorization: Bearer localdevadmin" \
                     -H "Content-Type: application/json" \
                     -d "{\"dids\": [\"$ALICE_DID\"]}" \
                     "http://127.0.0.1:3200/admin/backfill/repos"
            fi
        fi
        sleep 5
    fi
done

echo ""
echo "Demo complete."
echo "Servers are running in background."
echo "Press Ctrl+C to stop."
wait
