#!/usr/bin/env bash
# full_suite_demo.sh — Launch full ATProto stack with demo data and Admin UI
#
# Starts: PLC → PDS → Relay → AppView → Chat → Video → Admin UI
# Seeds accounts with 10+ records each, wires Relay→PDS via requestCrawl,
# ensures AppView backfills from Relay, and launches Admin UI.
#
# This is the broadest local smoke launcher. It exercises every local service
# that the Admin UI can talk to, using disposable state under DEMO_ROOT and
# predictable credentials so browser/manual tests can start from a known shape.
#
# Usage:
#   ./scripts/full_suite_demo.sh              # Full launch with seeding
#   ./scripts/full_suite_demo.sh --skip-seed   # Start services only
#   ./scripts/full_suite_demo.sh --stop      # Stop all services
#

set -euo pipefail

# ── Shared library ────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# ── Configuration ──────────────────────────────────────────────────────────

PROJECT_ROOT="$(resolve_project_root "$SCRIPT_DIR")"
BUILD_DIR="$(resolve_build_dir "$PROJECT_ROOT")"
DEMO_ROOT="${DEMO_ROOT:-/tmp/atproto-demo}"

# Service URLs (from common.sh SERVICE_URLS)
PLC_URL="$SERVICE_URL_PLC"
PDS_URL="$SERVICE_URL_PDS"
RELAY_URL="$SERVICE_URL_RELAY"
APPVIEW_URL="$SERVICE_URL_APPVIEW"
CHAT_URL="$SERVICE_URL_CHAT"
VIDEO_URL="$SERVICE_URL_VIDEO"
UI_URL="$SERVICE_URL_UI"

# Secrets
PDS_MASTER_SECRET="${PDS_MASTER_SECRET:-test-master-secret-123}"
PDS_ADMIN_PASSWORD="${PDS_ADMIN_PASSWORD:-localdevadmin}"
APPVIEW_ADMIN_SECRET="${APPVIEW_ADMIN_SECRET:-localdevadmin}"
CHAT_ADMIN_SECRET="${CHAT_ADMIN_SECRET:-localdevadmin}"
VIDEO_ADMIN_SECRET="${VIDEO_ADMIN_SECRET:-localdevadmin}"
UI_ADMIN_PASSWORD="${UI_ADMIN_PASSWORD:-localdev}"

LOG_DIR="$DEMO_ROOT/logs"
PID_FILE="$DEMO_ROOT/pids.txt"

# ── Cleanup ────────────────────────────────────────────────────────────────

cleanup() {
    # Stop children recorded in PID_FILE first. The shared cleanup then handles
    # any service process that survived an interrupted or partially failed run.
    log_info "Stopping all services..."
    if [[ -f "$PID_FILE" ]]; then
        while read -r line; do
            if [[ "$line" =~ ^PID=([0-9]+)$ ]]; then
                kill "${BASH_REMATCH[1]}" 2>/dev/null || true
            fi
        done < "$PID_FILE"
    fi
    kill_stray_processes
    sleep 1
    rm -f "$PID_FILE"
    log_ok "All services stopped"
}

# ── Parse Args ──────────────────────────────────────────────────────────────

SKIP_SEED=false
STOP_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --skip-seed) SKIP_SEED=true ;;
        --stop)      STOP_ONLY=true ;;
        --help|-h)
            echo "Usage: $0 [--skip-seed] [--stop]"
            echo ""
            echo "  --skip-seed   Start services without seeding data"
            echo "  --stop        Stop all running services"
            exit 0
            ;;
    esac
done

if [[ "$STOP_ONLY" == "true" ]]; then
    cleanup
    exit 0
fi

# ── Signal Handlers ─────────────────────────────────────────────────────────

trap cleanup EXIT INT TERM

# ── Pre-flight ──────────────────────────────────────────────────────────────

log_info "Starting full ATProto suite demo..."
echo ""

# Fail before touching DEMO_ROOT if any required service binary is missing.
check_binaries "$BUILD_DIR"

log_info "Cleaning up any existing demo service processes..."
kill_stray_processes
sleep 1

# Recreate disposable service state and log directories for a deterministic
# demo. Persistent/local production data should never be pointed at DEMO_ROOT.
rm -rf "$DEMO_ROOT"
mkdir -p "$DEMO_ROOT"/{plc,pds,relay,appview,chat,video,ui,logs}
> "$PID_FILE"

# ── 1. Start PLC ────────────────────────────────────────────────────────────

log_info "Starting PLC (campagnola) on port $SERVICE_PORT_PLC..."
"$BUILD_DIR/campagnola" serve --port "$SERVICE_PORT_PLC" --database "$DEMO_ROOT/plc/plc.db" \
    > "$LOG_DIR/plc.log" 2>&1 &
echo "PID=$!" >> "$PID_FILE"

wait_for_http "$PLC_URL/_health" "PLC" 30

# ── 2. Start PDS ───────────────────────────────────────────────────────────

log_info "Starting PDS (kaszlak) on port $SERVICE_PORT_PDS..."
PDS_PLC_URL="$PLC_URL" \
PDS_ISSUER="$PDS_URL" \
PDS_MASTER_SECRET="$PDS_MASTER_SECRET" \
PDS_ADMIN_PASSWORD="$PDS_ADMIN_PASSWORD" \
    "$BUILD_DIR/kaszlak" serve --port "$SERVICE_PORT_PDS" --data-dir "$DEMO_ROOT/pds" \
    > "$LOG_DIR/pds.log" 2>&1 &
echo "PID=$!" >> "$PID_FILE"

    wait_for_http "$PDS_URL/xrpc/com.atproto.server.describeServer" "PDS" 60

# Brief pause to let PDS finish initializing PLC client
sleep 2

# Create an admin account with retries because the PDS can accept HTTP traffic
# before its PLC client has completed first-use initialization.
log_info "Creating PDS admin account..."
for attempt in 1 2 3; do
    ADMIN_CREATE_RESP=$(curl -s -X POST "$PDS_URL/xrpc/com.atproto.server.createAccount" \
        -H "Content-Type: application/json" \
        -d "{\"email\": \"admin@localhost\", \"handle\": \"pds-admin.test\", \"password\": \"$PDS_ADMIN_PASSWORD\"}" \
        2>/dev/null || echo "{}")
    if echo "$ADMIN_CREATE_RESP" | jq -e '.did' >/dev/null 2>&1; then
        log_ok "Admin account created (DID: $(echo "$ADMIN_CREATE_RESP" | jq -r '.did'))"
        break
    elif echo "$ADMIN_CREATE_RESP" | jq -e '.error' >/dev/null 2>&1; then
        ERR_MSG=$(echo "$ADMIN_CREATE_RESP" | jq -r '.message // .error' 2>/dev/null)
        if [[ "$attempt" -lt 3 ]]; then
            log_debug "Admin account creation attempt $attempt failed: $ERR_MSG — retrying in 2s..."
            sleep 2
        else
            log_warn "Admin account creation failed: $ERR_MSG"
        fi
    else
        log_debug "Admin account creation response: ${ADMIN_CREATE_RESP:0:100}"
        break
    fi
done
sleep 1

# Fetch a PDS admin token for the Admin UI. The UI can still start without it,
# but admin panels that call PDS privileged endpoints will be degraded.
log_info "Getting PDS admin token (JWT)..."
PDS_ADMIN_TOKEN=$(curl -s -X POST "$PDS_URL/admin/login" \
    -H "Content-Type: application/json" \
    -d "{\"password\": \"$PDS_ADMIN_PASSWORD\"}" 2>/dev/null | \
    jq -r '.token // empty' 2>/dev/null || echo "")
if [[ -n "$PDS_ADMIN_TOKEN" && "$PDS_ADMIN_TOKEN" != "null" ]]; then
    log_ok "PDS admin JWT obtained"
else
    log_warn "Failed to get PDS admin token — UI admin features may not work"
    PDS_ADMIN_TOKEN=""
fi

# ── 3. Start Relay ─────────────────────────────────────────────────────────

log_info "Starting Relay (zuk) on port $SERVICE_PORT_RELAY..."
RELAY_ADMIN_PASSWORD="$APPVIEW_ADMIN_SECRET" \
    "$BUILD_DIR/zuk" serve --port "$SERVICE_PORT_RELAY" --data-dir "$DEMO_ROOT/relay" \
    --no-upstream \
    > "$LOG_DIR/relay.log" 2>&1 &
echo "PID=$!" >> "$PID_FILE"

wait_for_http "$RELAY_URL/api/relay/health" "Relay" 30


# ── 4. Wire PDS → Relay ────────────────────────────────────────────────────

log_info "Wiring PDS → Relay..."

# Add the PDS firehose as a relay upstream. The later requestCrawl call is a
# backup path for services that discover relay connectivity from the PDS side.
RESP=$(curl -s -X POST "$RELAY_URL/api/relay/upstreams" \
    -H "Authorization: Bearer $APPVIEW_ADMIN_SECRET" \
    -H "Content-Type: application/json" \
    -d "{\"url\": \"ws://127.0.0.1:$SERVICE_PORT_PDS/xrpc/com.atproto.sync.subscribeRepos\"}" 2>/dev/null || echo "{}")
if echo "$RESP" | grep -q "success.*true"; then
    log_ok "Relay upstream added"
else
    log_warn "Failed to add relay upstream (may already exist): ${RESP:0:100}"
fi

# Trigger the relay to connect immediately instead of waiting for periodic
# upstream maintenance. The URL path segment must be encoded exactly.
sleep 1
ENCODED_URL=$(python3 -c "import urllib.parse; print(urllib.parse.quote('ws://127.0.0.1:$SERVICE_PORT_PDS/xrpc/com.atproto.sync.subscribeRepos', safe='')" 2>/dev/null || echo "ws%3A%2F%2F127.0.0.1%3A$SERVICE_PORT_PDS%2Fxrpc%2Fcom.atproto.sync.subscribeRepos")
RESP=$(curl -s -X POST "$RELAY_URL/api/relay/upstreams/$ENCODED_URL/connect" \
    -H "Authorization: Bearer $APPVIEW_ADMIN_SECRET" \
    -H "Content-Length: 0" 2>/dev/null || echo "{}")
if echo "$RESP" | grep -q "success.*true"; then
    log_ok "Relay connecting to PDS"
else
    log_warn "Relay connect trigger failed: ${RESP:0:100}"
fi

# Also ask the PDS to announce itself. This covers relay implementations that
# use requestCrawl as the preferred crawl trigger.
sleep 1
curl -s -X POST "$PDS_URL/xrpc/com.atproto.sync.requestCrawl" \
    -H "Content-Type: application/json" \
    -d "{\"hostname\": \"127.0.0.1:$SERVICE_PORT_PDS\"}" 2>/dev/null >/dev/null || true

sleep 2

# Check that the relay accepted at least one upstream. This is not fatal because
# AppView can still start and expose diagnostics that explain the missing data.
UPSTREAM_COUNT=$(curl -s "$RELAY_URL/api/relay/upstreams" | jq -r '.total // 0' 2>/dev/null || echo "0")
if [[ "$UPSTREAM_COUNT" -gt 0 ]]; then
    log_ok "Relay has $UPSTREAM_COUNT upstream(s) configured"
else
    log_warn "Relay upstream count is 0 - PDS may not be connected"
fi


# ── 5. Start AppView (pointed at Relay) ─────────────────────────────────────

log_info "Starting AppView (syrena) on port $SERVICE_PORT_APPVIEW..."
APPVIEW_RELAY_URLS="ws://127.0.0.1:$SERVICE_PORT_RELAY/xrpc/com.atproto.sync.subscribeRepos" \
APPVIEW_ADMIN_SECRET="$APPVIEW_ADMIN_SECRET" \
APPVIEW_MASTER_SECRET="$PDS_MASTER_SECRET" \
APPVIEW_PLC_URL="$PLC_URL" \
    "$BUILD_DIR/syrena" serve --port "$SERVICE_PORT_APPVIEW" --data-dir "$DEMO_ROOT/appview" \
    > "$LOG_DIR/appview.log" 2>&1 &
echo "PID=$!" >> "$PID_FILE"

log_info "Waiting for AppView backfill status endpoint..."
for i in {1..40}; do
    if curl -s -H "Authorization: Bearer $APPVIEW_ADMIN_SECRET" \
        "$APPVIEW_URL/admin/backfill/status" >/dev/null 2>&1; then
        log_ok "AppView is up"
        break
    fi
    sleep 0.5
done

# ── 5.5. Start Chat Service ────────────────────────────────────────────────

log_info "Starting Chat (syrena-chat) on port $SERVICE_PORT_CHAT..."
PDS_URL="$PDS_URL" \
CHAT_ADMIN_SECRET="$CHAT_ADMIN_SECRET" \
    "$BUILD_DIR/syrena-chat" serve --port "$SERVICE_PORT_CHAT" --data-dir "$DEMO_ROOT/chat" \
    > "$LOG_DIR/chat.log" 2>&1 &
echo "PID=$!" >> "$PID_FILE"

wait_for_http "$CHAT_URL/_health" "Chat" 30 || \
    log_warn "Chat service health check failed — chat tab may not work"

# ── 5.6. Start Video Service (jelcz) ───────────────────────────────────────

log_info "Starting Video (jelcz) on port $SERVICE_PORT_VIDEO..."
JELCZ_ADMIN_SECRET="$VIDEO_ADMIN_SECRET" \
JELCZ_PDS_URL="$PDS_URL" \
    "$BUILD_DIR/jelcz" serve --port "$SERVICE_PORT_VIDEO" \
    --data-dir "$DEMO_ROOT/video" \
    --pds-url "$PDS_URL" \
    > "$LOG_DIR/video.log" 2>&1 &
echo "PID=$!" >> "$PID_FILE"

wait_for_http "$VIDEO_URL/_health" "Video" 30 || \
    log_warn "Video service health check failed — video tab may not work"

# ── 6. Start Admin UI (wired to all backends) ──────────────────────────────

log_info "Starting Admin UI (garazyk-ui) on port $SERVICE_PORT_UI..."
GARAZYK_UI_PDS_URL="$PDS_URL" \
GARAZYK_UI_PLC_URL="$PLC_URL" \
GARAZYK_UI_RELAY_URL="$RELAY_URL" \
GARAZYK_UI_APPVIEW_URL="$APPVIEW_URL" \
GARAZYK_UI_CHAT_URL="$CHAT_URL" \
GARAZYK_UI_VIDEO_URL="$VIDEO_URL" \
GARAZYK_UI_PORT="$SERVICE_PORT_UI" \
GARAZYK_UI_ADMIN_PASSWORD="$UI_ADMIN_PASSWORD" \
GARAZYK_UI_PDS_TOKEN="${PDS_ADMIN_TOKEN:-}" \
GARAZYK_UI_PLC_TOKEN="$APPVIEW_ADMIN_SECRET" \
GARAZYK_UI_RELAY_TOKEN="$APPVIEW_ADMIN_SECRET" \
GARAZYK_UI_APPVIEW_TOKEN="$APPVIEW_ADMIN_SECRET" \
GARAZYK_UI_CHAT_TOKEN="$CHAT_ADMIN_SECRET" \
GARAZYK_UI_VIDEO_TOKEN="$VIDEO_ADMIN_SECRET" \
    "$BUILD_DIR/garazyk-ui" serve --port "$SERVICE_PORT_UI" \
    > "$LOG_DIR/ui.log" 2>&1 &
echo "PID=$!" >> "$PID_FILE"

wait_for_http "$UI_URL/admin" "Admin UI" 30

# ── 7. Seed Data ────────────────────────────────────────────────────────────

if [[ "$SKIP_SEED" != "true" ]]; then
    log_info "Seeding PDS records and Chat conversations..."

    export PDS_URL CHAT_URL PDS_DATA_DIR="$DEMO_ROOT/pds" BUILD_DIR
    if [[ -f "$SCRIPT_DIR/seed_full_suite.py" ]]; then
        python3 "$SCRIPT_DIR/seed_full_suite.py" && log_ok "Seeding completed" || \
            log_warn "Seeding script had errors (see output above)"
    else
        log_warn "seed_full_suite.py not found, skipping seed"
    fi

    # Give AppView time to consume relay events generated by the seeder.
    log_info "Waiting for AppView to backfill seeded accounts..."
    sleep 15

    # Force backfill for known accounts as a second path in case the relay did
    # not deliver every event before the verification window.
    for handle in alice.test bob.test carol.test; do
        DID=$(curl -s "$PDS_URL/xrpc/com.atproto.identity.resolveHandle?handle=$handle" | \
            jq -r '.did // empty' 2>/dev/null || echo "")
        if [[ -n "$DID" && "$DID" != "null" ]]; then
            curl -s -X POST \
                -H "Authorization: Bearer $APPVIEW_ADMIN_SECRET" \
                -H "Content-Type: application/json" \
                -d "{\"dids\": [\"$DID\"]}" \
                "$APPVIEW_URL/admin/backfill/repos" >/dev/null 2>&1 && \
                log_debug "Backfill requested for $handle ($DID)"
        fi
    done

    sleep 5

    # Verify user-visible AppView state, not just that the backfill endpoint
    # accepted requests.
    log_info "Verifying AppView backfill..."
    for handle in alice.test bob.test carol.test; do
        PROFILE=$(curl -s "$APPVIEW_URL/xrpc/app.bsky.actor.getProfile?actor=$handle" 2>/dev/null || echo "{}")
        if echo "$PROFILE" | jq -e '.displayName' >/dev/null 2>&1; then
            log_ok "$handle found in AppView"
        else
            log_warn "$handle not yet in AppView (backfill may still be in progress)"
        fi
    done
fi

# ── 8. Verify UI → PDS Admin Connectivity ──────────────────────────────────

if [[ -n "$PDS_ADMIN_TOKEN" ]]; then
    log_info "Verifying UI can access PDS admin endpoints..."
    SEARCH_TEST=$(curl -s -H "Authorization: Bearer $PDS_ADMIN_TOKEN" \
        "$PDS_URL/xrpc/com.atproto.admin.searchAccounts?q=alice" 2>/dev/null || echo "{}")
    if echo "$SEARCH_TEST" | jq -e '.accounts' >/dev/null 2>&1; then
        log_ok "PDS admin token works — UI admin features should work"
    else
        log_warn "PDS admin token test failed — some UI admin features may not work"
    fi
fi

# ── 9. Summary ─────────────────────────────────────────────────────────────

echo ""
echo -e "${_LIB_BOLD}╔══════════════════════════════════════════════════════╗${_LIB_NC}"
echo -e "${_LIB_BOLD}║     Full ATProto Suite Demo is Ready!              ║${_LIB_NC}"
echo -e "${_LIB_BOLD}╚══════════════════════════════════════════════════════╝${_LIB_NC}"
echo ""
log_info "PLC:      $PLC_URL"
log_info "PDS:      $PDS_URL"
log_info "Relay:    $RELAY_URL"
log_info "AppView:  $APPVIEW_URL"
log_info "Chat:     $CHAT_URL"
log_info "Video:    $VIDEO_URL"
log_info "Admin UI: $UI_URL/admin"
echo ""
log_info "Demo Accounts:"
log_info "  alice.test / alicepass  (5 posts, profile, follows)"
log_info "  bob.test   / bobpass    (5 posts, profile, follows)"
log_info "  carol.test / carolpass  (5 posts, profile, follows)"
echo ""
log_info "Logs: $LOG_DIR/"
log_info "Stop: ./scripts/full_suite_demo.sh --stop"
log_info "      (or Ctrl+C)"
echo ""

# Keep running
wait
