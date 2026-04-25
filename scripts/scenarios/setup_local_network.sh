#!/usr/bin/env bash
# setup_local_network.sh — Start the ATProto local-network environment
#
# Usage:
#   ./setup_local_network.sh              # Start PLC + PDS + Relay + AppView (Docker)
#   ./setup_local_network.sh --binary     # Start from build/bin/ (no Docker)
#   ./setup_local_network.sh --pds2       # Also start second PDS for federation
#   ./setup_local_network.sh --wait-only  # Just wait for healthy, don't start
#   ./setup_local_network.sh --teardown   # Stop all services
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_DIR="$REPO_ROOT/docker/local-network"
CONFIG_DIR="$SCRIPT_DIR/config"
BUILD_BIN="$REPO_ROOT/build/bin"

BINARY_MODE=false
WITH_PDS2=false
WAIT_ONLY=false
TEARDOWN=false

for arg in "$@"; do
    case "$arg" in
        --binary)    BINARY_MODE=true ;;
        --pds2)      WITH_PDS2=true ;;
        --wait-only) WAIT_ONLY=true ;;
        --teardown)  TEARDOWN=true ;;
        --help|-h)
            echo "Usage: $0 [--binary] [--pds2] [--wait-only] [--teardown]"
            echo ""
            echo "  --binary     Start services from build/bin/ (no Docker)"
            echo "  --pds2       Also start a second PDS on port 2585 (for federation scenarios)"
            echo "  --wait-only  Don't start services, just wait for them to be healthy"
            echo "  --teardown   Stop all services"
            exit 0
            ;;
    esac
done

# Colors
if [[ -t 1 ]] && [[ "${NO_COLOR:-false}" != "true" ]]; then
    GREEN='\033[0;32m' YELLOW='\033[1;33m' CYAN='\033[0;36m' NC='\033[0m'
else
    GREEN='' YELLOW='' CYAN='' NC=''
fi

log()  { echo -e "${CYAN}[SETUP]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# ── Python deps for scenario runner ─────────────────────────────────────────
# requests is required by lib/client.py; websockets is needed for the firehose
# scenario. Install once into the user's site-packages so run_scenario.py works
# out of the box. Skipped during teardown.
if [[ "$TEARDOWN" != "true" ]]; then
    REQ_FILE="$SCRIPT_DIR/requirements.txt"
    if [[ -f "$REQ_FILE" ]]; then
        if ! python3 -c "import websockets, requests" >/dev/null 2>&1; then
            log "Installing scenario Python dependencies (requests, websockets)..."
            python3 -m pip install --user -q -r "$REQ_FILE" || \
                warn "pip install failed; firehose tests may skip"
        fi
    fi
fi

# ── Teardown ────────────────────────────────────────────────────────────────
if [[ "$TEARDOWN" == "true" ]]; then
    if [[ "$BINARY_MODE" == "true" ]]; then
        log "Stopping binary services..."
        for name in campagnola kaszlak zuk syrena; do
            if pgrep -f "$name serve" >/dev/null 2>&1; then
                pkill -f "$name serve" && ok "Stopped $name"
            fi
        done
        # Clean up PID file
        rm -f /tmp/atproto-scenario-pids.txt
    else
        log "Stopping Docker services..."
        docker compose -f "$COMPOSE_DIR/docker-compose.yml" down -v 2>/dev/null || true
    fi
    ok "Teardown complete"
    exit 0
fi

# ── Wait for services ────────────────────────────────────────────────────────
 wait_for() {
     local name=$1
     local url=$2
     local timeout=$3
     shift 3

     log "Waiting for $name to be healthy..."
     local deadline=$(( $(date +%s) + timeout ))
     while [[ $(date +%s) -lt $deadline ]]; do
         if curl -s -f "$url" "$@" >/dev/null; then
             ok "$name is healthy"
             return 0
         fi
         sleep 2
     done
     warn "$name not healthy after ${timeout}s (url: $url)"
     return 1
 }

# ── Binary mode ──────────────────────────────────────────────────────────────
if [[ "$BINARY_MODE" == "true" ]]; then
    log "Starting binary services..."

    # Check binaries exist
    for bin in campagnola kaszlak zuk syrena; do
        if [[ ! -x "$BUILD_BIN/$bin" ]]; then
            echo "ERROR: Binary not found: $BUILD_BIN/$bin"
            echo "Run: cmake --build build --target $bin"
            exit 1
        fi
    done

     # Create data directories
     DATA_ROOT="/tmp/atproto-run-data"
     rm -rf "$DATA_ROOT"
     mkdir -p "$DATA_ROOT"
     
     PLC_DATA="$DATA_ROOT/plc"
     PDS_DATA="$DATA_ROOT/pds"
     RELAY_DATA="$DATA_ROOT/relay"
     APPVIEW_DATA="$DATA_ROOT/appview"
     mkdir -p "$PLC_DATA" "$PDS_DATA" "$RELAY_DATA" "$APPVIEW_DATA"

    # PID file
    PID_FILE="/tmp/atproto-scenario-pids.txt"
    echo "# ATProto scenario PIDs (started $(date))" > "$PID_FILE"

    # Environment for PDS
    export PDS_USE_BIOMETRIC_PROTECTION=false
    export PDS_USE_KEYCHAIN=false
    export PDS_MASTER_SECRET="test-master-secret-123"
    export PDS_ADMIN_PASSWORD="test-admin-password"

    # ── Start PLC ────────────────────────────────────────────────────────────
    log "Starting PLC on port 2582..."
    "$BUILD_BIN/campagnola" serve --port 2582 --data-dir "$PLC_DATA" > /tmp/plc.log 2>&1 &
    echo "PLC_PID=$!" >> "$PID_FILE"
    sleep 2
    wait_for "PLC" "http://localhost:2582/_health" 30

    # ── Start PDS ────────────────────────────────────────────────────────────
    log "Starting PDS on port 2583..."
    "$BUILD_BIN/kaszlak" serve --config "$CONFIG_DIR/pds-config.json" --port 2583 --data-dir "$PDS_DATA" > /tmp/pds.log 2>&1 &
    echo "PDS_PID=$!" >> "$PID_FILE"
    sleep 3
    wait_for "PDS" "http://localhost:2583/xrpc/com.atproto.server.describeServer" 60

    # ── Start Relay ──────────────────────────────────────────────────────────
    log "Starting Relay on port 2584..."
    "$BUILD_BIN/zuk" serve --port 2584 \
        --upstream "ws://localhost:2583/xrpc/com.atproto.sync.subscribeRepos" \
        --data-dir "$RELAY_DATA" > /tmp/relay.log 2>&1 &
    echo "RELAY_PID=$!" >> "$PID_FILE"
    sleep 2
    wait_for "Relay" "http://localhost:2584/api/relay/health" 30

     # ── Start AppView ────────────────────────────────────────────────────────
     log "Starting AppView on port 3200..."
     export APPVIEW_ADMIN_SECRET="localdevadmin"
     export APPVIEW_MASTER_SECRET="test-master-secret-123"
     export APPVIEW_PLC_URL="http://localhost:2582"
    "$BUILD_BIN/syrena" serve \
        --relay "ws://localhost:2584/xrpc/com.atproto.sync.subscribeRepos" \
        --port 3200 \
        --data-dir "$APPVIEW_DATA" > /tmp/appview.log 2>&1 &
    echo "APPVIEW_PID=$!" >> "$PID_FILE"
    sleep 3
    # AppView health check uses admin endpoint
    wait_for "AppView" "http://localhost:3200/admin/backfill/status" 60 \
        -H "Authorization: Bearer localdevadmin"

     # ── Start PDS2 (optional) ────────────────────────────────────────────────
     if [[ "$WITH_PDS2" == "true" ]]; then
         PDS2_DATA="$DATA_ROOT/pds2"
         mkdir -p "$PDS2_DATA"
         log "Starting PDS2 on port 2585..."
        PDS_MASTER_SECRET="test-master-secret-456" \
        "$BUILD_BIN/kaszlak" serve --config "$CONFIG_DIR/pds2-config.json" --port 2585 --data-dir "$PDS2_DATA" > /tmp/pds2.log 2>&1 &
        echo "PDS2_PID=$!" >> "$PID_FILE"
        sleep 3
        wait_for "PDS2" "http://localhost:2585/xrpc/com.atproto.server.describeServer" 60
    fi

    echo ""
    ok "Binary network is ready!"
    echo ""
    echo "  PLC:     http://localhost:2582"
    echo "  PDS:     http://localhost:2583"
    echo "  Relay:   http://localhost:2584"
    echo "  AppView: http://localhost:3200"
    if [[ "$WITH_PDS2" == "true" ]]; then
        echo "  PDS2:    http://localhost:2585"
    fi
    echo ""
    echo "  Logs: /tmp/{plc,pds,relay,appview}.log"
    echo "  PIDs: $PID_FILE"
    echo ""
    echo "  To stop: $0 --teardown --binary"
    echo ""
    exit 0
fi

# ── Docker mode ──────────────────────────────────────────────────────────────
if [[ "$WAIT_ONLY" != "true" ]]; then
    log "Starting local network (Docker)..."
    COMPOSE_CMD="docker compose -f $COMPOSE_DIR/docker-compose.yml"
    if [[ "$WITH_PDS2" == "true" ]]; then
        COMPOSE_CMD="$COMPOSE_CMD -f $COMPOSE_DIR/docker-compose.scenarios.yml"
        log "Including second PDS (port 2585)"
    fi
    $COMPOSE_CMD up -d
fi

wait_for "PLC"     "http://localhost:2582/_health"                                60
wait_for "PDS"     "http://localhost:2583/xrpc/com.atproto.server.describeServer" 60
wait_for "Relay"   "http://localhost:2584/api/relay/health"                      60
wait_for "AppView" "http://localhost:3200/_health"                               90

if [[ "$WITH_PDS2" == "true" ]]; then
    wait_for "PDS2" "http://localhost:2585/xrpc/com.atproto.server.describeServer" 60
fi

echo ""
ok "Local network is ready!"
echo ""
echo "  PLC:     http://localhost:2582"
echo "  PDS:     http://localhost:2583"
echo "  Relay:   http://localhost:2584"
echo "  AppView: http://localhost:3200"
if [[ "$WITH_PDS2" == "true" ]]; then
    echo "  PDS2:    http://localhost:2585"
fi
echo ""
