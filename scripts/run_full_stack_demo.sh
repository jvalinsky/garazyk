#!/usr/bin/env bash
# run_full_stack_demo.sh - Start PLC, PDS, Relay, and AppView for a smoke demo.
#
# This script is a mid-sized stack launcher: it brings up the core federation
# services from local binaries, seeds a small account dataset, gives AppView
# time to ingest it, and prints a few API responses for quick verification.
# It keeps services running until interrupted so a developer can inspect logs,
# replay requests, or open UI/API endpoints after the initial checks.
#
# Environment:
#   BUILD_DIR                 Directory containing service binaries.
#   DEMO_ROOT                 Disposable data/log root, default /tmp/atproto-demo.
#   PDS_MASTER_SECRET         Local PDS signing/master secret.
#   PDS_ADMIN_PASSWORD        Password used for local PDS admin login.
#   APPVIEW_ADMIN_SECRET      Bearer secret for AppView admin endpoints.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

PROJECT_ROOT="$(resolve_project_root "$SCRIPT_DIR")"
BUILD_DIR="$(resolve_build_dir "$PROJECT_ROOT")"
DEMO_ROOT="${DEMO_ROOT:-/tmp/atproto-demo}"
mkdir -p "$DEMO_ROOT"

PLC_BIN="$BUILD_DIR/$SERVICE_BINARY_PLC"
PDS_BIN="$BUILD_DIR/$SERVICE_BINARY_PDS"
RELAY_BIN="$BUILD_DIR/$SERVICE_BINARY_RELAY"
APPVIEW_BIN="$BUILD_DIR/$SERVICE_BINARY_APPVIEW"

PLC_URL="$SERVICE_URL_PLC"
PDS_URL="$SERVICE_URL_PDS"
RELAY_URL="$SERVICE_URL_RELAY"
APPVIEW_URL="$SERVICE_URL_APPVIEW"

PDS_MASTER_SECRET="${PDS_MASTER_SECRET:-32107992c973da8445b485263cb2bd3157859cb94294a2355e3c4a7b0f825afe}"
PDS_ADMIN_PASSWORD="${PDS_ADMIN_PASSWORD:-localdevadmin}"
RELAY_ADMIN_PASSWORD="${RELAY_ADMIN_PASSWORD:-localdevadmin}"
APPVIEW_ADMIN_SECRET="${APPVIEW_ADMIN_SECRET:-localdevadmin}"
PDS_ADMIN_SECRET="${PDS_ADMIN_SECRET:-localdevadmin}"

cleanup() {
    # The demo owns all core services on the shared local ports. Use the common
    # port-aware cleanup helper rather than relying only on shell job state.
    log_info "Stopping all servers..."
    kill_stray_processes plc pds relay appview
    sleep 1
}

trap cleanup EXIT INT TERM

cleanup
rm -rf "$DEMO_ROOT"/*
mkdir -p "$DEMO_ROOT/plc" "$DEMO_ROOT/pds" "$DEMO_ROOT/relay" "$DEMO_ROOT/appview"

check_binaries "$BUILD_DIR" plc pds relay appview

log_info "Starting PLC (campagnola) on port $SERVICE_PORT_PLC..."
"$PLC_BIN" serve --port "$SERVICE_PORT_PLC" --database "$DEMO_ROOT/plc/plc.db" > "$DEMO_ROOT/plc.log" 2>&1 &
wait_for_http "$PLC_URL/_health" "PLC" 30

log_info "Starting PDS (kaszlak) on port $SERVICE_PORT_PDS..."
export PDS_PLC_URL="$PLC_URL"
export PDS_ISSUER="$PDS_URL"
export PDS_MASTER_SECRET="$PDS_MASTER_SECRET"
export PDS_ADMIN_PASSWORD="$PDS_ADMIN_PASSWORD"
export PDS_LOG_LEVEL="debug"
"$PDS_BIN" serve --port "$SERVICE_PORT_PDS" --data-dir "$DEMO_ROOT/pds" --config /tmp/missing.json --foreground --verbose > "$DEMO_ROOT/pds.log" 2>&1 &
wait_for_http "$PDS_URL/xrpc/com.atproto.server.describeServer" "PDS" 30

log_info "Starting Relay (zuk) on port $SERVICE_PORT_RELAY..."
log_debug "Giving PDS more time to start before Relay connects"
sleep 5
export RELAY_ADMIN_PASSWORD="$RELAY_ADMIN_PASSWORD"
"$RELAY_BIN" serve --port "$SERVICE_PORT_RELAY" --data-dir "$DEMO_ROOT/relay" --upstream "$PDS_URL" --verbose > "$DEMO_ROOT/relay.log" 2>&1 &
wait_for_http "$RELAY_URL/api/relay/health" "Relay" 30

log_info "Starting AppView (syrena) on port $SERVICE_PORT_APPVIEW..."
export APPVIEW_PLC_URL="$PLC_URL"
export APPVIEW_DATA_DIR="$DEMO_ROOT/appview"
export APPVIEW_ADMIN_SECRET="$APPVIEW_ADMIN_SECRET"
export PDS_ADMIN_SECRET="$PDS_ADMIN_SECRET"
"$APPVIEW_BIN" serve --port "$SERVICE_PORT_APPVIEW" --data-dir "$DEMO_ROOT/appview" --relay "$RELAY_URL" --verbose > "$DEMO_ROOT/appview.log" 2>&1 &

for i in {1..20}; do
    # AppView's admin status endpoint is the first useful readiness signal for
    # this flow because backfill checks and forced indexing both depend on it.
    if curl -s -H "Authorization: Bearer $APPVIEW_ADMIN_SECRET" "$APPVIEW_URL/admin/backfill/status" >/dev/null; then
        log_ok "AppView is up"
        break
    fi
    sleep 0.5
done

sleep 2

log_info "Seeding PDS with accounts and records via XRPC..."
export PDS_URL="$PDS_URL"
export PDS_DATA_DIR="$DEMO_ROOT/pds"
export PDS_BIN="$PDS_BIN"
python3 scripts/demo_seed.py

log_info "Waiting for indexing..."
# AppView indexes asynchronously from the relay. The fixed wait keeps this
# smoke script dependency-free; full scenario tests perform stricter polling.
sleep 15

echo ""
echo "==> STACK VERIFICATION"
echo "======================"

echo "PDS Discovery:"
curl -s "$PDS_URL/xrpc/com.atproto.server.describeServer" | jq .

echo "Relay Health:"
curl -s "$RELAY_URL/api/relay/health" | jq .

echo "AppView Backfill Status:"
curl -s -H "Authorization: Bearer $APPVIEW_ADMIN_SECRET" "$APPVIEW_URL/admin/backfill/status" | jq .

echo "Checking if Alice exists in AppView..."
for i in {1..5}; do
    # If AppView has not seen Alice by the second attempt, force a backfill for
    # her DID. This preserves the fast path while making local relay hiccups
    # less likely to produce an empty demo.
    PROFILE=$(curl -s "$APPVIEW_URL/xrpc/app.bsky.actor.getProfile?actor=alice.test")
    if echo "$PROFILE" | grep -q "Alice"; then
        log_ok "Alice found in AppView!"
        echo "$PROFILE" | jq .
        break
    else
        log_info "Alice not indexed yet (attempt $i)"
        if [[ $i -eq 2 ]]; then
            ALICE_DID=$(curl -s "$PDS_URL/xrpc/com.atproto.identity.resolveHandle?handle=alice.test" | jq -r .did)
            if [[ "$ALICE_DID" != "null" ]]; then
                log_info "Forcing backfill for Alice: $ALICE_DID"
                curl -s -X POST -H "Authorization: Bearer $APPVIEW_ADMIN_SECRET" \
                    -H "Content-Type: application/json" \
                    -d "{\"dids\":[\"$ALICE_DID\"]}" \
                    "$APPVIEW_URL/admin/backfill/repos"
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
