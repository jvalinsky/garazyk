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
KEEP_RUNNING=false
COLLECT_DIAGNOSTICS=false

while [[ $# -gt 0 ]]; do
    # Keep argument parsing intentionally simple: scenario automation passes a
    # small fixed flag set and all per-service values come from common.sh envs.
    case "$1" in
        --binary)    BINARY_MODE=true ;;
        --pds2)      WITH_PDS2=true ;;
        --wait-only) WAIT_ONLY=true ;;
        --teardown)  TEARDOWN=true ;;
        --keep-running) KEEP_RUNNING=true ;;
        --collect-diagnostics) COLLECT_DIAGNOSTICS=true ;;
        --run-id)
            [[ $# -ge 2 ]] || error_exit "--run-id requires a value" 2
            ATPROTO_E2E_RUN_ID="$2"
            shift
            ;;
        --diagnostics-dir)
            [[ $# -ge 2 ]] || error_exit "--diagnostics-dir requires a value" 2
            ATPROTO_E2E_DIAGNOSTICS_DIR="$2"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--binary] [--pds2] [--wait-only] [--teardown] [--run-id ID] [--diagnostics-dir DIR]"
            echo ""
            echo "  --binary               Start services from build/bin/ (no Docker)"
            echo "  --pds2                 Also start a second PDS on port $SERVICE_PORT_CHAT"
            echo "  --wait-only            Don't start services, just wait for them to be healthy"
            echo "  --teardown             Stop services for this run"
            echo "  --keep-running         Mark this run as intentionally long-lived"
            echo "  --collect-diagnostics  Capture health, logs, and compose state"
            echo "  --run-id ID            Reuse or name the shared e2e run directory"
            echo "  --diagnostics-dir DIR  Write diagnostics to DIR"
            exit 0
            ;;
        *)
            error_exit "Unknown argument: $1" 2
            ;;
    esac
    shift
done

if [[ "$TEARDOWN" == "true" || "$COLLECT_DIAGNOSTICS" == "true" ]]; then
    atproto_e2e_load_latest_run_id "scenario"
fi
atproto_e2e_init_run
if [[ "$TEARDOWN" != "true" && "$COLLECT_DIAGNOSTICS" != "true" && "$WAIT_ONLY" != "true" ]]; then
    atproto_e2e_store_latest_run_id "scenario"
fi

COMPOSE_FILES=("$COMPOSE_DIR/docker-compose.yml")
if [[ "$WITH_PDS2" == "true" || "$TEARDOWN" == "true" || "$COLLECT_DIAGNOSTICS" == "true" ]]; then
    COMPOSE_FILES+=("$COMPOSE_DIR/docker-compose.scenarios.yml")
fi

build_compose_cmd() {
    COMPOSE_CMD=(docker compose -p "$ATPROTO_E2E_COMPOSE_PROJECT")
    local compose_file
    for compose_file in "${COMPOSE_FILES[@]}"; do
        COMPOSE_CMD+=(-f "$compose_file")
    done
}

build_compose_cmd

collect_local_diagnostics() {
    atproto_collect_diagnostics "$ATPROTO_E2E_DIAGNOSTICS_DIR" \
        "$COMPOSE_DIR" "$ATPROTO_E2E_COMPOSE_PROJECT" "${COMPOSE_FILES[@]}"
}

stop_binary_services() {
    if [[ -f "$ATPROTO_E2E_PID_FILE" ]]; then
        while read -r line; do
            if [[ "$line" =~ ^[A-Z0-9_]+_PID=([0-9]+)$ ]]; then
                kill "${BASH_REMATCH[1]}" 2>/dev/null || true
                wait "${BASH_REMATCH[1]}" 2>/dev/null || true
            fi
        done < "$ATPROTO_E2E_PID_FILE"
    fi
    rm -f "$ATPROTO_E2E_PID_FILE"
}

stop_docker_services() {
    "${COMPOSE_CMD[@]}" down -v --remove-orphans 2>/dev/null || true
}

# Tear down stale garazyk-e2e Docker compose projects from previous runs.
#
# Each e2e run gets a unique compose project name (garazyk-e2e-<timestamp>-<pid>).
# If a previous run crashes or is interrupted, its containers survive and hold
# the service ports, causing the next run to fail with "port already allocated".
# This function finds any garazyk-e2e containers bound to our known ports and
# tears down their entire compose project.
stop_stale_docker_e2e() {
    # Collect the ports we need.
    local needed_ports=("$SERVICE_PORT_PLC" "$SERVICE_PORT_PDS" "$SERVICE_PORT_RELAY" "$SERVICE_PORT_APPVIEW" "8080")
    if [[ "$WITH_PDS2" == "true" ]]; then
        needed_ports+=("$SERVICE_PORT_CHAT")
    fi

    # Find garazyk-e2e containers holding any of our ports.
    local stale_projects=()
    for port in "${needed_ports[@]}"; do
        local container_id
        container_id=$(docker ps --filter "publish=$port" --filter "name=garazyk-e2e" --format "{{.ID}}" 2>/dev/null || true)
        if [[ -n "$container_id" ]]; then
            while read -r cid; do
                [[ -z "$cid" ]] && continue
                local project
                project=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' "$cid" 2>/dev/null || true)
                if [[ -n "$project" && "$project" != "$ATPROTO_E2E_COMPOSE_PROJECT" && " ${stale_projects[*]} " != *" $project "* ]]; then
                    stale_projects+=("$project")
                fi
            done <<< "$container_id"
        fi
    done

    if (( ${#stale_projects[@]} == 0 )); then
        return 0
    fi

    log_warn "Found stale e2e containers holding needed ports: ${stale_projects[*]}"
    for project in "${stale_projects[@]}"; do
        log_info "Tearing down stale compose project: $project"
        docker compose -p "$project" -f "$COMPOSE_DIR/docker-compose.yml" down -v --remove-orphans 2>/dev/null || true
    done
}

on_exit() {
    local status=$?
    if [[ "$status" -ne 0 ]]; then
        log_warn "setup_local_network.sh failed; collecting diagnostics"
        collect_local_diagnostics || true
    fi
}

on_interrupt() {
    log_warn "Interrupted; collecting diagnostics and stopping owned services"
    collect_local_diagnostics || true
    if [[ "$BINARY_MODE" == "true" ]]; then
        stop_binary_services
    else
        stop_docker_services
    fi
    exit 130
}

trap on_exit EXIT
trap on_interrupt INT TERM

check_scenario_python_dependencies() {
    if ! python3 -c "import requests" >/dev/null 2>&1; then
        error_exit "Missing Python dependency: requests (install with: python3 -m pip install -r $SCRIPT_DIR/requirements.txt)" 3
    fi
    if ! python3 -c "import websockets" >/dev/null 2>&1; then
        log_warn "Optional Python dependency missing: websockets (scenario 09 may skip firehose checks)"
    fi
}

if [[ "$COLLECT_DIAGNOSTICS" == "true" && "$TEARDOWN" != "true" ]]; then
    collect_local_diagnostics
    exit 0
fi

if [[ "$TEARDOWN" != "true" ]]; then
    check_scenario_python_dependencies
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
    if [[ "$COLLECT_DIAGNOSTICS" == "true" ]]; then
        collect_local_diagnostics || true
    fi
    if [[ "$BINARY_MODE" == "true" ]]; then
        log_info "Stopping binary services..."
        stop_binary_services
    else
        log_info "Stopping Docker services..."
        stop_docker_services
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
    DATA_ROOT="$ATPROTO_E2E_RUN_DIR/data"
    stop_binary_services
    rm -rf "$DATA_ROOT"
    mkdir -p "$DATA_ROOT"

    PLC_DATA="$DATA_ROOT/plc"
    PDS_DATA="$DATA_ROOT/pds"
    RELAY_DATA="$DATA_ROOT/relay"
    APPVIEW_DATA="$DATA_ROOT/appview"
    mkdir -p "$PLC_DATA" "$PDS_DATA" "$RELAY_DATA" "$APPVIEW_DATA"

    # PID file gives teardown a stable list of processes even after this script
    # exits and the scenario runner continues in a separate Python process.
    PID_FILE="$ATPROTO_E2E_PID_FILE"
    echo "# ATProto scenario PIDs (started $(date))" > "$PID_FILE"

    # Disable host-specific secure storage so local binary scenarios can run in
    # non-interactive shells and CI without Keychain/biometric prompts.
    export PDS_RUNNING_TESTS=true
    export PDS_USE_BIOMETRIC_PROTECTION=false
    export PDS_USE_KEYCHAIN=false
    export PDS_MASTER_SECRET="test-master-secret-123"
    export PDS_ADMIN_PASSWORD="test-admin-password"
    export PDS_PLC_KEYS_DIR="$PDS_DATA/keys"

    # ── Start PLC ────────────────────────────────────────────────────────────
    log_info "Starting PLC on port $SERVICE_PORT_PLC..."
    "$BUILD_BIN/$SERVICE_BINARY_PLC" serve --port "$SERVICE_PORT_PLC" --data-dir "$PLC_DATA" > "$ATPROTO_E2E_LOG_DIR/plc.log" 2>&1 &
    echo "PLC_PID=$!" >> "$PID_FILE"
    sleep 2
    wait_for_http "$SERVICE_URL_PLC/_health" "PLC" 30

    # ── Start PDS ────────────────────────────────────────────────────────────
    log_info "Starting PDS on port $SERVICE_PORT_PDS..."
    "$BUILD_BIN/$SERVICE_BINARY_PDS" serve --config "$CONFIG_DIR/pds-config.json" --port "$SERVICE_PORT_PDS" --data-dir "$PDS_DATA" > "$ATPROTO_E2E_LOG_DIR/pds.log" 2>&1 &
    echo "PDS_PID=$!" >> "$PID_FILE"
    sleep 3
    wait_for_http "$SERVICE_URL_PDS/xrpc/com.atproto.server.describeServer" "PDS" 60

    # ── Start Relay ──────────────────────────────────────────────────────────
    log_info "Starting Relay on port $SERVICE_PORT_RELAY..."
    "$BUILD_BIN/$SERVICE_BINARY_RELAY" serve --port "$SERVICE_PORT_RELAY" \
        --upstream "${SERVICE_URL_PDS/http/ws}/xrpc/com.atproto.sync.subscribeRepos" \
        --data-dir "$RELAY_DATA" > "$ATPROTO_E2E_LOG_DIR/relay.log" 2>&1 &
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
        --data-dir "$APPVIEW_DATA" > "$ATPROTO_E2E_LOG_DIR/appview.log" 2>&1 &
    echo "APPVIEW_PID=$!" >> "$PID_FILE"
    sleep 3
    # AppView health check uses admin endpoint — this is fatal because
    # scenarios that proxy app.bsky.* endpoints will fail without it.
    wait_for_admin_http "$SERVICE_URL_APPVIEW/admin/backfill/status" "AppView" 60 || \
        error_exit "AppView failed to start within 60s"

    # ── Start UI Server ────────────────────────────────────────────────────
    if [[ -x "$BUILD_BIN/$SERVICE_BINARY_UI" ]]; then
        log_info "Starting UI server on port $SERVICE_PORT_UI..."
        UI_DATA="$DATA_ROOT/ui"
        mkdir -p "$UI_DATA"
        GARAZYK_UI_PDS_URL="$SERVICE_URL_PDS" \
        GARAZYK_UI_PLC_URL="$SERVICE_URL_PLC" \
        GARAZYK_UI_RELAY_URL="$SERVICE_URL_RELAY" \
        GARAZYK_UI_APPVIEW_URL="$SERVICE_URL_APPVIEW" \
        GARAZYK_UI_ADMIN_PASSWORD="changeme" \
        "$BUILD_BIN/$SERVICE_BINARY_UI" serve --port "$SERVICE_PORT_UI" \
            > "$ATPROTO_E2E_LOG_DIR/ui.log" 2>&1 &
        echo "UI_PID=$!" >> "$PID_FILE"
        sleep 2
        wait_for_http "$SERVICE_URL_UI/lab" "UI Server" 30 || \
            log_warn "UI Server not healthy (scenario 11 will fail)"
    else
        log_warn "UI server binary not found; scenario 11 will be skipped"
    fi

    # ── Start PDS2 (optional) ────────────────────────────────────────────────
    if [[ "$WITH_PDS2" == "true" ]]; then
        PDS2_DATA="$DATA_ROOT/pds2"
        mkdir -p "$PDS2_DATA"
        log_info "Starting PDS2 on port $SERVICE_PORT_CHAT..."
        PDS_MASTER_SECRET="test-master-secret-456" \
        PDS_PLC_KEYS_DIR="$PDS2_DATA/keys" \
        "$BUILD_BIN/$SERVICE_BINARY_PDS" serve --config "$CONFIG_DIR/pds2-config.json" --port "$SERVICE_PORT_CHAT" --data-dir "$PDS2_DATA" > "$ATPROTO_E2E_LOG_DIR/pds2.log" 2>&1 &
        echo "PDS2_PID=$!" >> "$PID_FILE"
        sleep 3
        wait_for_http "$SERVICE_URL_CHAT/xrpc/com.atproto.server.describeServer" "PDS2" 60
    fi

    echo ""
    log_info "Waiting for services to settle..."
    sleep 5
    log_ok "Binary network is ready!"
    echo ""
    echo "  PLC:     $SERVICE_URL_PLC"
    echo "  PDS:     $SERVICE_URL_PDS"
    echo "  Relay:   $SERVICE_URL_RELAY"
    echo "  AppView: $SERVICE_URL_APPVIEW"
    echo "  UI:      $SERVICE_URL_UI"
    if [[ "$WITH_PDS2" == "true" ]]; then
        echo "  PDS2:    $SERVICE_URL_CHAT"
    fi
    echo ""
    echo "  Run:  $ATPROTO_E2E_RUN_DIR"
    echo "  Logs: $ATPROTO_E2E_LOG_DIR"
    echo "  PIDs: $PID_FILE"
    echo ""
    echo "  To stop: $0 --teardown --binary"
    echo ""
    exit 0
fi

# ── Docker mode ──────────────────────────────────────────────────────────────
if [[ "$WAIT_ONLY" != "true" ]]; then
    log_info "Starting local network (Docker)..."
    if [[ "$WITH_PDS2" == "true" ]]; then
        log_info "Including second PDS (port $SERVICE_PORT_CHAT)"
    fi
    stop_stale_docker_e2e
    stop_docker_services
    "${COMPOSE_CMD[@]}" up -d
fi

wait_for_service plc 60
wait_for_service pds 60
wait_for_service relay 60
wait_for_service appview 90 || error_exit "AppView failed to start within 90s"

if [[ "$WITH_PDS2" == "true" ]]; then
    wait_for_http "$SERVICE_URL_CHAT/xrpc/com.atproto.server.describeServer" "PDS2" 60
fi

echo ""
log_info "Waiting for services to settle..."
sleep 5
echo ""
echo "  Run:     $ATPROTO_E2E_RUN_DIR"
echo "  Project: $ATPROTO_E2E_COMPOSE_PROJECT"
if [[ "$KEEP_RUNNING" == "true" ]]; then
    echo "  Stop:    $0 --teardown --run-id $ATPROTO_E2E_RUN_ID"
fi
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
