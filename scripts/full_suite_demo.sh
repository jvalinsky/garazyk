#!/usr/bin/env bash
# full_suite_demo.sh — Launch full ATProto stack with demo data and Admin UI
#
# Starts: PLC → PDS → Relay → AppView → Admin UI
# Seeds accounts with 10+ records each, wires Relay→PDS via requestCrawl,
# ensures AppView backfills from Relay, and launches Admin UI.
#
# Usage:
#   ./scripts/full_suite_demo.sh              # Full launch with seeding
#   ./scripts/full_suite_demo.sh --skip-seed   # Start services only
#   ./scripts/full_suite_demo.sh --stop      # Stop all services
#

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/build/bin}"
DEMO_ROOT="${DEMO_ROOT:-/tmp/atproto-demo}"

# Ports
PLC_PORT="${PLC_PORT:-2582}"
PDS_PORT="${PDS_PORT:-2583}"
RELAY_PORT="${RELAY_PORT:-2584}"
APPVIEW_PORT="${APPVIEW_PORT:-3200}"
UI_PORT="${UI_PORT:-2590}"

# URLs
PLC_URL="http://127.0.0.1:$PLC_PORT"
PDS_URL="http://127.0.0.1:$PDS_PORT"
RELAY_URL="http://127.0.0.1:$RELAY_PORT"
APPVIEW_URL="http://127.0.0.1:$APPVIEW_PORT"
UI_URL="http://127.0.0.1:$UI_PORT"

# Secrets
PDS_MASTER_SECRET="${PDS_MASTER_SECRET:-test-master-secret-123}"
PDS_ADMIN_PASSWORD="${PDS_ADMIN_PASSWORD:-localdevadmin}"
APPVIEW_ADMIN_SECRET="${APPVIEW_ADMIN_SECRET:-localdevadmin}"
UI_ADMIN_PASSWORD="${UI_ADMIN_PASSWORD:-localdev}"

LOG_DIR="$DEMO_ROOT/logs"
PID_FILE="$DEMO_ROOT/pids.txt"

# ── Colors ──────────────────────────────────────────────────────────────────

if [[ -t 1 ]] && [[ "${NO_COLOR:-false}" != "true" ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; NC=''
fi

# ── Logging ──────────────────────────────────────────────────────────────────

log()     { echo -e "${CYAN}[SETUP]${NC} $1"; }
ok()      { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }
info()    { echo -e "  $1"; }

# ── Helpers ──────────────────────────────────────────────────────────────────

wait_for_http() {
    local url="$1" label="${2:-$1}" timeout="${3:-30}"
    local deadline=$(( $(date +%s) + timeout ))
    while [[ $(date +%s) -lt $deadline ]]; do
        if curl -s -f "$url" >/dev/null 2>&1; then
            ok "$label is healthy"
            return 0
        fi
        sleep 0.5
    done
    warn "$label not healthy after ${timeout}s ($url)"
    return 1
}

cleanup() {
    log "Stopping all services..."
    if [[ -f "$PID_FILE" ]]; then
        while read -r line; do
            if [[ "$line" =~ ^PID=([0-9]+)$ ]]; then
                kill "${BASH_REMATCH[1]}" 2>/dev/null || true
            fi
        done < "$PID_FILE"
    fi
    # Stray processes
    for name in campagnola kaszlak zuk syrena garazyk-ui; do
        pkill -f "$name.*serve" 2>/dev/null || true
    done
    sleep 1
    rm -f "$PID_FILE"
    ok "All services stopped"
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

# ── Signal Handlers ──────────────────────────────────────────────────────────

trap cleanup EXIT INT TERM

# ── Pre-flight ─────────────────────────────────────────────────────────────

log "Starting full ATProto suite demo..."
echo ""

# Check binaries
for bin in campagnola kaszlak zuk syrena garazyk-ui; do
    if [[ ! -x "$BUILD_DIR/$bin" ]]; then
        error "Binary not found: $BUILD_DIR/$bin"
        error "Build with: xcodebuild -scheme $bin build"
        exit 1
    fi
done

# Clean + create dirs
rm -rf "$DEMO_ROOT"
mkdir -p "$DEMO_ROOT"/{plc,pds,relay,appview,ui,logs}
> "$PID_FILE"

# ── 1. Start PLC ──────────────────────────────────────────────────────────

log "Starting PLC (campagnola) on port $PLC_PORT..."
"$BUILD_DIR/campagnola" serve --port "$PLC_PORT" --database "$DEMO_ROOT/plc/plc.db" \
    > "$LOG_DIR/plc.log" 2>&1 &
echo "PID=$!" >> "$PID_FILE"

wait_for_http "$PLC_URL/_health" "PLC" 30

# ── 2. Start PDS ──────────────────────────────────────────────────────────

log "Starting PDS (kaszlak) on port $PDS_PORT..."
PDS_PLC_URL="$PLC_URL" \
PDS_ISSUER="$PDS_URL" \
PDS_MASTER_SECRET="$PDS_MASTER_SECRET" \
PDS_ADMIN_PASSWORD="$PDS_ADMIN_PASSWORD" \
    "$BUILD_DIR/kaszlak" serve --port "$PDS_PORT" --data-dir "$DEMO_ROOT/pds" \
    > "$LOG_DIR/pds.log" 2>&1 &
echo "PID=$!" >> "$PID_FILE"

    wait_for_http "$PDS_URL/xrpc/com.atproto.server.describeServer" "PDS" 60

# Get PDS admin token (JWT) for UI to use
# PDS uses JWT from createSession, not /admin/login
log "Getting PDS admin token (JWT)..."
PDS_ADMIN_TOKEN=$(curl -s -X POST "$PDS_URL/xrpc/com.atproto.server.createSession" \
    -H "Content-Type: application/json" \
    -d "{\"identifier\": \"admin\", \"password\": \"$PDS_ADMIN_PASSWORD\"}" 2>/dev/null | \
    jq -r '.accessJwt // empty' 2>/dev/null || echo "")
if [[ -n "$PDS_ADMIN_TOKEN" && "$PDS_ADMIN_TOKEN" != "null" ]]; then
    ok "PDS admin JWT obtained"
else
    # Try with a seeded account instead
    log "Trying to get token via seeded account..."
    PDS_ADMIN_TOKEN=$(curl -s -X POST "$PDS_URL/xrpc/com.atproto.server.createSession" \
        -H "Content-Type: application/json" \
        -d "{\"identifier\": \"alice.test\", \"password\": \"alicepass\"}" 2>/dev/null | \
        jq -r '.accessJwt // empty' 2>/dev/null || echo "")
    if [[ -n "$PDS_ADMIN_TOKEN" && "$PDS_ADMIN_TOKEN" != "null" ]]; then
        ok "PDS admin JWT obtained via alice.test"
    else
        warn "Failed to get PDS admin token — UI admin features may not work"
        PDS_ADMIN_TOKEN=""
    fi
fi

# ── 3. Start Relay ────────────────────────────────────────────────────────

log "Starting Relay (zuk) on port $RELAY_PORT..."
RELAY_ADMIN_PASSWORD="$APPVIEW_ADMIN_SECRET" \
    "$BUILD_DIR/zuk" serve --port "$RELAY_PORT" --data-dir "$DEMO_ROOT/relay" \
    --no-upstream \
    > "$LOG_DIR/relay.log" 2>&1 &
echo "PID=$!" >> "$PID_FILE"

wait_for_http "$RELAY_URL/api/relay/health" "Relay" 30


# ── 4. Wire PDS → Relay ────────────────────────────────────────

log "Wiring PDS → Relay..."

# Add PDS as upstream to relay via correct API endpoint
# POST /api/relay/upstreams with URL in body
RESP=$(curl -s -X POST "$RELAY_URL/api/relay/upstreams" \
    -H "Authorization: Bearer $APPVIEW_ADMIN_SECRET" \
    -H "Content-Type: application/json" \
    -d "{\"url\": \"ws://127.0.0.1:$PDS_PORT/xrpc/com.atproto.sync.subscribeRepos\"}" 2>/dev/null || echo "{}")
if echo "$RESP" | grep -q "success.*true"; then
    ok "Relay upstream added"
else
    warn "Failed to add relay upstream (may already exist): ${RESP:0:100}"
fi

# Trigger connect to upstream (URL-encoded path)
sleep 1
ENCODED_URL=$(python3 -c "import urllib.parse; print(urllib.parse.quote('ws://127.0.0.1:$PDS_PORT/xrpc/com.atproto.sync.subscribeRepos', safe='')" 2>/dev/null || echo "ws%3A%2F%2F127.0.0.1%3A$PDS_PORT%2Fxrpc%2Fcom.atproto.sync.subscribeRepos")
RESP=$(curl -s -X POST "$RELAY_URL/api/relay/upstreams/$ENCODED_URL/connect" \
    -H "Authorization: Bearer $APPVIEW_ADMIN_SECRET" 2>/dev/null || echo "{}")
if echo "$RESP" | grep -q "success.*true"; then
    ok "Relay connecting to PDS"
else
    warn "Relay connect trigger failed: ${RESP:0:100}"
fi

# Also try requestCrawl from PDS to relay as backup
sleep 1
curl -s -X POST "$PDS_URL/xrpc/com.atproto.sync.requestCrawl" \
    -H "Content-Type: application/json" \
    -d "{\"hostname\": \"127.0.0.1:$PDS_PORT\"}" 2>/dev/null >/dev/null || true

sleep 2

# Verify relay has upstream connected
UPSTREAM_COUNT=$(curl -s "$RELAY_URL/api/relay/upstreams" | jq -r '.total // 0' 2>/dev/null || echo "0")
if [[ "$UPSTREAM_COUNT" -gt 0 ]]; then
    ok "Relay has $UPSTREAM_COUNT upstream(s) configured"
else
    warn "Relay upstream count is 0 - PDS may not be connected"
fi


# ── 5. Start AppView (pointed at Relay) ──────────────────────────────

log "Starting AppView (syrena) on port $APPVIEW_PORT..."
APPVIEW_RELAY_URLS="ws://127.0.0.1:$RELAY_PORT/xrpc/com.atproto.sync.subscribeRepos" \
APPVIEW_ADMIN_SECRET="$APPVIEW_ADMIN_SECRET" \
APPVIEW_MASTER_SECRET="$PDS_MASTER_SECRET" \
APPVIEW_PLC_URL="$PLC_URL" \
    "$BUILD_DIR/syrena" serve --port "$APPVIEW_PORT" --data-dir "$DEMO_ROOT/appview" \
    > "$LOG_DIR/appview.log" 2>&1 &
echo "PID=$!" >> "$PID_FILE"

log "Waiting for AppView backfill status endpoint..."
for i in {1..40}; do
    if curl -s -H "Authorization: Bearer $APPVIEW_ADMIN_SECRET" \
        "$APPVIEW_URL/admin/backfill/status" >/dev/null 2>&1; then
        ok "AppView is up"
        break
    fi
    sleep 0.5
done

# ── 6. Start Admin UI (wired to all backends) ──────────────────────────

log "Starting Admin UI (garazyk-ui) on port $UI_PORT..."
GARAZYK_UI_PDS_URL="$PDS_URL" \
GARAZYK_UI_PLC_URL="$PLC_URL" \
GARAZYK_UI_RELAY_URL="$RELAY_URL" \
GARAZYK_UI_APPVIEW_URL="$APPVIEW_URL" \
GARAZYK_UI_CHAT_URL="$PDS_URL" \
GARAZYK_UI_ADMIN_PASSWORD="$UI_ADMIN_PASSWORD" \
GARAZYK_UI_PDS_TOKEN="${PDS_ADMIN_TOKEN:-}" \
GARAZYK_UI_PLC_TOKEN="$APPVIEW_ADMIN_SECRET" \
GARAZYK_UI_RELAY_TOKEN="$APPVIEW_ADMIN_SECRET" \
GARAZYK_UI_APPVIEW_TOKEN="$APPVIEW_ADMIN_SECRET" \
GARAZYK_UI_CHAT_TOKEN="${PDS_ADMIN_TOKEN:-}" \
    "$BUILD_DIR/garazyk-ui" serve \
    > "$LOG_DIR/ui.log" 2>&1 &
echo "PID=$!" >> "$PID_FILE"

wait_for_http "$UI_URL/admin" "Admin UI" 30

# ── 7. Seed Data ──────────────────────────────────────────────────────────

if [[ "$SKIP_SEED" != "true" ]]; then
    log "Seeding PDS with demo accounts and records..."

    export PDS_URL PDS_DATA_DIR="$DEMO_ROOT/pds" BUILD_DIR
    if [[ -f "$SCRIPT_DIR/seed_full_suite.py" ]]; then
        python3 "$SCRIPT_DIR/seed_full_suite.py" && ok "Seeding completed" || \
            warn "Seeding script had errors (see output above)"
    else
        warn "seed_full_suite.py not found, skipping seed"
    fi

    # Give AppView time to backfill
    log "Waiting for AppView to backfill seeded accounts..."
    sleep 15

    # Force backfill for known accounts if needed
    for handle in alice.test bob.test carol.test; do
        DID=$(curl -s "$PDS_URL/xrpc/com.atproto.identity.resolveHandle?handle=$handle" | \
            jq -r '.did // empty' 2>/dev/null || echo "")
        if [[ -n "$DID" && "$DID" != "null" ]]; then
            curl -s -X POST \
                -H "Authorization: Bearer $APPVIEW_ADMIN_SECRET" \
                -H "Content-Type: application/json" \
                -d "{\"dids\": [\"$DID\"]}" \
                "$APPVIEW_URL/admin/backfill/repos" >/dev/null 2>&1 && \
                info "Backfill requested for $handle ($DID)"
        fi
    done

    sleep 5

    # Verify AppView has the accounts
    log "Verifying AppView backfill..."
    for handle in alice.test bob.test carol.test; do
        PROFILE=$(curl -s "$APPVIEW_URL/xrpc/app.bsky.actor.getProfile?actor=$handle" 2>/dev/null || echo "{}")
        if echo "$PROFILE" | jq -e '.displayName' >/dev/null 2>&1; then
            ok "$handle found in AppView"
        else
            warn "$handle not yet in AppView (backfill may still be in progress)"
        fi
    done
fi

# ── 8. Verify UI → PDS Admin Connectivity ──────────────────────

if [[ -n "$PDS_ADMIN_TOKEN" ]]; then
    log "Verifying UI can access PDS admin endpoints..."
    # Test that the PDS token works by checking search
    SEARCH_TEST=$(curl -s -H "Authorization: Bearer $PDS_ADMIN_TOKEN" \
        "$PDS_URL/xrpc/com.atproto.admin.searchAccounts?q=alice" 2>/dev/null || echo "{}")
    if echo "$SEARCH_TEST" | jq -e '.accounts' >/dev/null 2>&1; then
        ok "PDS admin token works — UI admin features should work"
    else
        warn "PDS admin token test failed — some UI admin features may not work"
    fi
fi

# ── 9. Summary ────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║     Full ATProto Suite Demo is Ready!              ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
info "PLC:      $PLC_URL"
info "PDS:      $PDS_URL"
info "Relay:    $RELAY_URL"
info "AppView:  $APPVIEW_URL"
info "Admin UI: $UI_URL/admin"
echo ""
info "Demo Accounts:"
info "  alice.test / alicepass  (5 posts, profile, follows)"
info "  bob.test   / bobpass    (5 posts, profile, follows)"
info "  carol.test / carolpass  (5 posts, profile, follows)"
echo ""
info "Logs: $LOG_DIR/"
info "Stop: ./scripts/full_suite_demo.sh --stop"
info "      (or Ctrl+C)"
echo ""

# Keep running
wait
