#!/usr/bin/env bash
# setup_local_network.sh — Start the ATProto local-network environment
#
# The scenario runner uses this script as its one process boundary for
# environment management. Docker mode matches the compose-based integration
# topology; binary mode runs freshly built local executables against disposable
# data directories so uncommitted service changes can be tested.
#
# Usage:
#   ./setup_local_network.sh              # Start PLC + PDS + Relay + AppView (Docker)
#   ./setup_local_network.sh --binary     # Start from build/bin/ (no Docker)
#   ./setup_local_network.sh --pds2       # Also start second PDS for federation
#   ./setup_local_network.sh --wait-only  # Just wait for healthy, don't start
#   ./setup_local_network.sh --teardown   # Stop all services

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

REPO_ROOT="$(resolve_project_root "$SCRIPT_DIR")"
COMPOSE_DIR="$REPO_ROOT/docker/local-network"
CONFIG_DIR="$SCRIPT_DIR/config"
BUILD_BIN="$(resolve_build_dir "$REPO_ROOT")"

BINARY_MODE=false
WITH_PDS2=false
WAIT_ONLY=false
TEARDOWN=false

for arg in "$@"; do
    # Keep argument parsing intentionally simple: scenario automation passes a
    # small fixed flag set and all per-service values come from common.sh envs.
    case "$arg" in
        --binary)    BINARY_MODE=true ;;
        --pds2)      WITH_PDS2=true ;;
        --wait-only) WAIT_ONLY=true ;;
        --teardown)  TEARDOWN=true ;;
        --help|-h)
            echo "Usage: $0 [--binary] [--pds2] [--wait-only] [--teardown]"
            echo ""
            echo "  --binary     Start services from build/bin/ (no Docker)"
            echo "  --pds2       Also start a second PDS on port $SERVICE_PORT_CHAT (for federation scenarios)"
            echo "  --wait-only  Don't start services, just wait for them to be healthy"
            echo "  --teardown   Stop all services"
            exit 0
            ;;
    esac
done

# ── Python deps for scenario runner ─────────────────────────────────────────
# requests is required by lib/client.py; websockets is needed for the firehose
# scenario. Install once into the user's site-packages so run_scenario.py works
# out of the box. Skipped during teardown.
if [[ "$TEARDOWN" != "true" ]]; then
    REQ_FILE="$SCRIPT_DIR/requirements.txt"
    if [[ -f "$REQ_FILE" ]]; then
        if ! python3 -c "import websockets, requests" >/dev/null 2>&1; then
            log_info "Installing scenario Python dependencies (requests, websockets)..."
            python3 -m pip install --user -q -r "$REQ_FILE" || \
                log_warn "pip install failed; firehose tests may skip"
        fi
    fi
fi

wait_for_admin_http() {
    # AppView readiness is exposed through an admin route in local scenarios.
    # The generic wait_for_http helper cannot attach this bearer token.
    local url="$1"
    local label="${2:-$url}"
    local timeout="${3:-30}"
    local deadline=$(( $(date +%s) + timeout ))

    log_info "Waiting for $label to be healthy..."
    while [[ $(date +%s) -lt $deadline ]]; do
        if curl -s -f -H "Authorization: Bearer ${APPVIEW_ADMIN_SECRET:-localdevadmin}" "$url" >/dev/null 2>&1; then
            log_ok "$label is healthy"
            return 0
        fi
        sleep 2
    done

    log_warn "$label not healthy after ${timeout}s (url: $url)"
    return 1
}

# ── Teardown ────────────────────────────────────────────────────────────────
if [[ "$TEARDOWN" == "true" ]]; then
    if [[ "$BINARY_MODE" == "true" ]]; then
        log_info "Stopping binary services..."
        kill_stray_processes plc pds relay appview
        pkill -f "$SERVICE_BINARY_PDS serve.*$SERVICE_PORT_CHAT" 2>/dev/null || true
        rm -f /tmp/atproto-scenario-pids.txt
    else
        log_info "Stopping Docker services..."
        docker compose -f "$COMPOSE_DIR/docker-compose.yml" down -v 2>/dev/null || true
    fi
    log_ok "Teardown complete"
    exit 0
fi

# ── Binary mode ──────────────────────────────────────────────────────────────
if [[ "$BINARY_MODE" == "true" ]]; then
    log_info "Starting binary services..."

    check_binaries "$BUILD_BIN" plc pds relay appview

    # Binary mode is disposable by design. Starting from an empty data root keeps
    # scenario runs independent and avoids stale repo/account state.
    DATA_ROOT="/tmp/atproto-run-data"
    rm -rf "$DATA_ROOT"
    mkdir -p "$DATA_ROOT"

    PLC_DATA="$DATA_ROOT/plc"
    PDS_DATA="$DATA_ROOT/pds"
    RELAY_DATA="$DATA_ROOT/relay"
    APPVIEW_DATA="$DATA_ROOT/appview"
    mkdir -p "$PLC_DATA" "$PDS_DATA" "$RELAY_DATA" "$APPVIEW_DATA"

    # PID file gives teardown a stable list of processes even after this script
    # exits and the scenario runner continues in a separate Python process.
    PID_FILE="/tmp/atproto-scenario-pids.txt"
    echo "# ATProto scenario PIDs (started $(date))" > "$PID_FILE"

    # Disable host-specific secure storage so local binary scenarios can run in
    # non-interactive shells and CI without Keychain/biometric prompts.
    export PDS_USE_BIOMETRIC_PROTECTION=false
    export PDS_USE_KEYCHAIN=false
    export PDS_MASTER_SECRET="test-master-secret-123"
    export PDS_ADMIN_PASSWORD="test-admin-password"

    # ── Start PLC ────────────────────────────────────────────────────────────
    log_info "Starting PLC on port $SERVICE_PORT_PLC..."
    "$BUILD_BIN/$SERVICE_BINARY_PLC" serve --port "$SERVICE_PORT_PLC" --data-dir "$PLC_DATA" > /tmp/plc.log 2>&1 &
    echo "PLC_PID=$!" >> "$PID_FILE"
    sleep 2
    wait_for_http "$SERVICE_URL_PLC/_health" "PLC" 30

    # ── Start PDS ────────────────────────────────────────────────────────────
    log_info "Starting PDS on port $SERVICE_PORT_PDS..."
    "$BUILD_BIN/$SERVICE_BINARY_PDS" serve --config "$CONFIG_DIR/pds-config.json" --port "$SERVICE_PORT_PDS" --data-dir "$PDS_DATA" > /tmp/pds.log 2>&1 &
    echo "PDS_PID=$!" >> "$PID_FILE"
    sleep 3
    wait_for_http "$SERVICE_URL_PDS/xrpc/com.atproto.server.describeServer" "PDS" 60

    # ── Start Relay ──────────────────────────────────────────────────────────
    log_info "Starting Relay on port $SERVICE_PORT_RELAY..."
    "$BUILD_BIN/$SERVICE_BINARY_RELAY" serve --port "$SERVICE_PORT_RELAY" \
        --upstream "${SERVICE_URL_PDS/http/ws}/xrpc/com.atproto.sync.subscribeRepos" \
        --data-dir "$RELAY_DATA" > /tmp/relay.log 2>&1 &
    echo "RELAY_PID=$!" >> "$PID_FILE"
    sleep 2
    wait_for_http "$SERVICE_URL_RELAY/api/relay/health" "Relay" 30

    # ── Start AppView ────────────────────────────────────────────────────────
    log_info "Starting AppView on port $SERVICE_PORT_APPVIEW..."
    export APPVIEW_ADMIN_SECRET="localdevadmin"
    export APPVIEW_MASTER_SECRET="test-master-secret-123"
    export APPVIEW_PLC_URL="$SERVICE_URL_PLC"
    "$BUILD_BIN/$SERVICE_BINARY_APPVIEW" serve \
        --relay "${SERVICE_URL_PDS/http/ws}/xrpc/com.atproto.sync.subscribeRepos" \
        --port "$SERVICE_PORT_APPVIEW" \
        --data-dir "$APPVIEW_DATA" > /tmp/appview.log 2>&1 &
    echo "APPVIEW_PID=$!" >> "$PID_FILE"
    sleep 3
    # AppView health check uses admin endpoint
    wait_for_admin_http "$SERVICE_URL_APPVIEW/admin/backfill/status" "AppView" 60

    # ── Start PDS2 (optional) ────────────────────────────────────────────────
    if [[ "$WITH_PDS2" == "true" ]]; then
        PDS2_DATA="$DATA_ROOT/pds2"
        mkdir -p "$PDS2_DATA"
        log_info "Starting PDS2 on port $SERVICE_PORT_CHAT..."
        PDS_MASTER_SECRET="test-master-secret-456" \
        "$BUILD_BIN/$SERVICE_BINARY_PDS" serve --config "$CONFIG_DIR/pds2-config.json" --port "$SERVICE_PORT_CHAT" --data-dir "$PDS2_DATA" > /tmp/pds2.log 2>&1 &
        echo "PDS2_PID=$!" >> "$PID_FILE"
        sleep 3
        wait_for_http "$SERVICE_URL_CHAT/xrpc/com.atproto.server.describeServer" "PDS2" 60
    fi

    echo ""
    log_ok "Binary network is ready!"
    echo ""
    echo "  PLC:     $SERVICE_URL_PLC"
    echo "  PDS:     $SERVICE_URL_PDS"
    echo "  Relay:   $SERVICE_URL_RELAY"
    echo "  AppView: $SERVICE_URL_APPVIEW"
    if [[ "$WITH_PDS2" == "true" ]]; then
        echo "  PDS2:    $SERVICE_URL_CHAT"
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
    log_info "Starting local network (Docker)..."
    # Build the compose command as an array so optional topology files do not
    # require eval or string-splitting.
    COMPOSE_CMD=(docker compose -f "$COMPOSE_DIR/docker-compose.yml")
    if [[ "$WITH_PDS2" == "true" ]]; then
        COMPOSE_CMD+=(-f "$COMPOSE_DIR/docker-compose.scenarios.yml")
        log_info "Including second PDS (port $SERVICE_PORT_CHAT)"
    fi
    "${COMPOSE_CMD[@]}" up -d
fi

wait_for_http "$SERVICE_URL_PLC/_health" "PLC" 60
wait_for_http "$SERVICE_URL_PDS/xrpc/com.atproto.server.describeServer" "PDS" 60
wait_for_http "$SERVICE_URL_RELAY/api/relay/health" "Relay" 60
wait_for_http "$SERVICE_URL_APPVIEW/_health" "AppView" 90

if [[ "$WITH_PDS2" == "true" ]]; then
    wait_for_http "$SERVICE_URL_CHAT/xrpc/com.atproto.server.describeServer" "PDS2" 60
fi

echo ""
log_ok "Local network is ready!"
echo ""
echo "  PLC:     $SERVICE_URL_PLC"
echo "  PDS:     $SERVICE_URL_PDS"
echo "  Relay:   $SERVICE_URL_RELAY"
echo "  AppView: $SERVICE_URL_APPVIEW"
if [[ "$WITH_PDS2" == "true" ]]; then
    echo "  PDS2:    $SERVICE_URL_CHAT"
fi
echo ""
