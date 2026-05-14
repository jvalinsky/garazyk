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
WITH_PHONE_VERIFICATION=false
WEB_CLIENT_PRESET=""
CLIENT_FLOW="none"
ALLOW_HYBRID_NETWORK=false
WEB_CLIENT_PORT="${WEB_CLIENT_PORT:-2591}"
WAIT_ONLY=false
TEARDOWN=false
KEEP_RUNNING=false
COLLECT_DIAGNOSTICS=false
SKIP_DOCKER_STAGE="${ATPROTO_E2E_SKIP_DOCKER_STAGE:-false}"
TOPOLOGY_PRESET=""

while [[ $# -gt 0 ]]; do
    # Keep argument parsing intentionally simple: scenario automation passes a
    # small fixed flag set and all per-service values come from common.sh envs.
    case "$1" in
        --binary)                BINARY_MODE=true ;;
        --pds2)                  WITH_PDS2=true ;;
        --with-phone-verification) WITH_PHONE_VERIFICATION=true ;;
        --web-client)
            [[ $# -ge 2 ]] || error_exit "--web-client requires a value" 2
            WEB_CLIENT_PRESET="$2"
            shift
            ;;
        --client-flow)
            [[ $# -ge 2 ]] || error_exit "--client-flow requires a value" 2
            CLIENT_FLOW="$2"
            shift
            ;;
        --allow-hybrid-network) ALLOW_HYBRID_NETWORK=true ;;
        --wait-only) WAIT_ONLY=true ;;
        --teardown)  TEARDOWN=true ;;
        --keep-running) KEEP_RUNNING=true ;;
        --collect-diagnostics) COLLECT_DIAGNOSTICS=true ;;
        --skip-docker-stage) SKIP_DOCKER_STAGE=true ;;
        --topology)
            [[ $# -ge 2 ]] || error_exit "--topology requires a value" 2
            TOPOLOGY_PRESET="$2"
            shift
            ;;
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
            echo "  --binary                 Start services from build/bin/ (no Docker)"
            echo "  --pds2                   Also start a second PDS on port $SERVICE_PORT_PDS2"
            echo "  --with-phone-verification Start mock Twilio server and configure PDS for phone verification"
            echo "  --web-client PRESET      Add a generated web-client compose service"
            echo "  --client-flow FLOW       Browser flow name for metadata (none/smoke/login/deep)"
            echo "  --allow-hybrid-network   Allow browser flows to call public ATProto hosts"
            echo "  --topology PRESET        Use a topology preset from scripts/scenarios/topologies/"
            echo "  --wait-only              Don't start services, just wait for them to be healthy"
            echo "  --teardown               Stop services for this run"
            echo "  --keep-running           Mark this run as intentionally long-lived"
            echo "  --collect-diagnostics    Capture health, logs, and compose state"
            echo "  --skip-docker-stage      Reuse existing staged Docker binaries"
            echo "  --run-id ID              Reuse or name the shared e2e run directory"
            echo "  --diagnostics-dir DIR    Write diagnostics to DIR"
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

TOPOLOGY_COMPOSE_FILE="$ATPROTO_E2E_RUN_DIR/docker-compose.topology.yml"
TOPOLOGY_SOURCES_JSON="$ATPROTO_E2E_RUN_DIR/topology_sources.json"
TOPOLOGY_MANIFEST_JSON="$ATPROTO_E2E_RUN_DIR/topology-manifest.json"
TOPOLOGY_MODE=false
if [[ -n "$TOPOLOGY_PRESET" || -f "$TOPOLOGY_MANIFEST_JSON" ]]; then
    TOPOLOGY_MODE=true
    export ATPROTO_TOPOLOGY_MANIFEST="$TOPOLOGY_MANIFEST_JSON"
fi

if [[ "$TOPOLOGY_MODE" == "true" ]]; then
    COMPOSE_FILES=("$TOPOLOGY_COMPOSE_FILE")
else
    COMPOSE_FILES=("$COMPOSE_DIR/docker-compose.yml")
fi
if [[ "$TOPOLOGY_MODE" != "true" && ( "$WITH_PDS2" == "true" || "$TEARDOWN" == "true" || "$COLLECT_DIAGNOSTICS" == "true" ) ]]; then
    COMPOSE_FILES+=("$COMPOSE_DIR/docker-compose.scenarios.yml")
fi
WEB_CLIENT_COMPOSE_FILE="$ATPROTO_E2E_RUN_DIR/web-client-compose.yml"
if [[ -n "$WEB_CLIENT_PRESET" && "$TEARDOWN" != "true" && "$COLLECT_DIAGNOSTICS" != "true" ]]; then
    render_args=(
        "$SCRIPT_DIR/render_web_client_compose.ts"
        --preset "$WEB_CLIENT_PRESET"
        --output "$WEB_CLIENT_COMPOSE_FILE"
        --run-dir "$ATPROTO_E2E_RUN_DIR"
        --repo-root "$REPO_ROOT"
    )
    if [[ "$TOPOLOGY_MODE" == "true" ]]; then
        render_args+=(--network "topology_net")
    fi
    if [[ "$ALLOW_HYBRID_NETWORK" == "true" ]]; then
        render_args+=(--allow-hybrid)
    fi
    deno run -A "${render_args[@]}"
fi
if [[ -f "$WEB_CLIENT_COMPOSE_FILE" ]]; then
    COMPOSE_FILES+=("$WEB_CLIENT_COMPOSE_FILE")
fi

# Compile topology preset to compose file if specified
if [[ -n "$TOPOLOGY_PRESET" && "$TEARDOWN" != "true" && "$COLLECT_DIAGNOSTICS" != "true" ]]; then
    log_info "Compiling topology preset: $TOPOLOGY_PRESET"
    compile_args=(
        "$SCRIPT_DIR/compile_topology.ts"
        --preset "$TOPOLOGY_PRESET"
        --output "$TOPOLOGY_COMPOSE_FILE"
        --run-dir "$ATPROTO_E2E_RUN_DIR"
        --repo-root "$REPO_ROOT"
        --sources-json "$TOPOLOGY_SOURCES_JSON"
        --manifest-json "$TOPOLOGY_MANIFEST_JSON"
    )
    if [[ "$WITH_PDS2" == "true" ]]; then
        compile_args+=(--include-pds2)
    fi
    deno run -A "${compile_args[@]}"
    export ATPROTO_TOPOLOGY="$TOPOLOGY_PRESET"
    export ATPROTO_TOPOLOGY_MANIFEST="$TOPOLOGY_MANIFEST_JSON"

    # Clone source repos if any adapters use source builds
    if [[ -f "$TOPOLOGY_SOURCES_JSON" ]]; then
        SOURCE_COUNT=$(python3 -c "import json; print(len(json.load(open('$TOPOLOGY_SOURCES_JSON'))))" 2>/dev/null || echo "0")
        if [[ "$SOURCE_COUNT" -gt 0 ]]; then
            log_info "Preparing $SOURCE_COUNT source build(s) for topology: $TOPOLOGY_PRESET"
            "$SCRIPT_DIR/prepare_topology.sh" \
                --preset "$TOPOLOGY_PRESET" \
                --run-dir "$ATPROTO_E2E_RUN_DIR" \
                --repo-root "$REPO_ROOT" \
                --sources-json "$TOPOLOGY_SOURCES_JSON"
        fi
    fi
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

docker_staging_needs_refresh() {
    local marker="$COMPOSE_DIR/staging/bin/$SERVICE_BINARY_PDS"
    if [[ ! -x "$marker" ]]; then
        return 0
    fi

    local newer_source
    newer_source=$(find \
        "$REPO_ROOT/Garazyk" \
        "$REPO_ROOT/CMakeLists.txt" \
        "$REPO_ROOT/docker/Dockerfile.gnustep" \
        -type f -newer "$marker" -print -quit 2>/dev/null || true)
    [[ -n "$newer_source" ]]
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
# Kill any stale host-local PDS binary processes holding our needed ports.
# Stale binary PDS processes (kaszlak) survive crashed/interrupted runs and
# block Docker port mapping, causing scenarios to hang on unreachable services.
# Only targets known Garazyk service binaries to avoid killing Docker infra.
stop_stale_host_processes() {
    local needed_ports=("$SERVICE_PORT_PLC" "$SERVICE_PORT_PDS" "$SERVICE_PORT_RELAY" "$SERVICE_PORT_APPVIEW" "8080")
    if [[ -n "$WEB_CLIENT_PRESET" ]]; then
        needed_ports+=("$WEB_CLIENT_PORT")
    fi
    if [[ "$WITH_PDS2" == "true" ]]; then
        needed_ports+=("$SERVICE_PORT_PDS2")
    fi
    if [[ "$WITH_PHONE_VERIFICATION" == "true" ]]; then
        needed_ports+=("8081")
    fi
    for port in "${needed_ports[@]}"; do
        local pids
        pids=$(lsof -ti :"$port" 2>/dev/null || true)
        if [[ -n "$pids" ]]; then
            local filtered_pids=""
            while read -r pid; do
                [[ -z "$pid" ]] && continue
                local cmd
                cmd=$(ps -p "$pid" -o comm= 2>/dev/null || true)
                case "$cmd" in
                    kaszlak|garazyk*|atproto*)
                        filtered_pids="$filtered_pids $pid"
                        ;;
                esac
            done <<< "$pids"
            if [[ -n "$filtered_pids" ]]; then
                log_warn "Stale host process(es) holding port $port (PID(s):$filtered_pids)"
                for pid in $filtered_pids; do
                    kill -9 "$pid" 2>/dev/null || true
                done
            fi
        fi
    done
    sleep 1
}

stop_stale_docker_e2e() {
    # Collect the ports we need.
    local needed_ports=("$SERVICE_PORT_PLC" "$SERVICE_PORT_PDS" "$SERVICE_PORT_RELAY" "$SERVICE_PORT_APPVIEW" "8080")
    if [[ -n "$WEB_CLIENT_PRESET" ]]; then
        needed_ports+=("$WEB_CLIENT_PORT")
    fi
    if [[ "$WITH_PDS2" == "true" ]]; then
        needed_ports+=("$SERVICE_PORT_PDS2")
    fi
    if [[ "$WITH_PHONE_VERIFICATION" == "true" ]]; then
        needed_ports+=("8081")
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
                if [[ -n "$project" && "$project" != "$ATPROTO_E2E_COMPOSE_PROJECT" && ! " ${stale_projects[@]:-} " =~ " $project " ]]; then
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

check_scenario_deno_dependencies() {
    if ! command -v deno >/dev/null 2>&1; then
        error_exit "Missing dependency: deno is required for scenario scripts" 3
    fi
}

if [[ "$COLLECT_DIAGNOSTICS" == "true" && "$TEARDOWN" != "true" ]]; then
    collect_local_diagnostics
    exit 0
fi

if [[ "$TEARDOWN" != "true" ]]; then
    check_scenario_deno_dependencies
fi

if [[ "$BINARY_MODE" == "true" && -n "$WEB_CLIENT_PRESET" ]]; then
    error_exit "--web-client is currently supported in Docker local-network mode only" 2
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

    check_binaries "$BUILD_BIN" plc pds relay appview video

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

    # PID file gives teardown a stable process list after this script exits and
    # the Deno scenario runner continues independently.
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

    # PLC rate limits (lower than production for scenario testing)
    export PLC_HOURLY_LIMIT="${PLC_HOURLY_LIMIT:-5}"
    export PLC_DAILY_LIMIT="${PLC_DAILY_LIMIT:-15}"
    export PLC_WEEKLY_LIMIT="${PLC_WEEKLY_LIMIT:-50}"

    # ── Start PLC ────────────────────────────────────────────────────────────
    log_info "Starting PLC on port $SERVICE_PORT_PLC..."
    "$BUILD_BIN/$SERVICE_BINARY_PLC" serve --port "$SERVICE_PORT_PLC" --data-dir "$PLC_DATA" > "$ATPROTO_E2E_LOG_DIR/plc.log" 2>&1 &
    echo "PLC_PID=$!" >> "$PID_FILE"
    sleep 2
    wait_for_http "$SERVICE_URL_PLC/_health" "PLC" 30

    # ── Mock Twilio server (optional) ────────────────────────────────────────
    MOCK_TWILIO_PID=""
    if [[ "$WITH_PHONE_VERIFICATION" == "true" ]]; then
        log_info "Starting mock Twilio server on port 8081..."
        deno run -A "$SCRIPT_DIR/../mock-twilio-server.ts" --port=8081 > "$ATPROTO_E2E_LOG_DIR/mock-twilio.log" 2>&1 &
        MOCK_TWILIO_PID=$!
        echo "MOCK_TWILIO_PID=$MOCK_TWILIO_PID" >> "$PID_FILE"
        sleep 1
        wait_for_http "http://127.0.0.1:8081/__control/health" "Mock Twilio" 15
    fi

    # ── Start PDS ────────────────────────────────────────────────────────────
    log_info "Starting PDS on port $SERVICE_PORT_PDS..."
    PDS_ALLOW_HTTP=1 \
    PDS_VIDEO_MODE=external \
    TWILIO_ACCOUNT_SID="${TWILIO_ACCOUNT_SID:-AC00000000000000000000000000000000}" \
    TWILIO_AUTH_TOKEN="${TWILIO_AUTH_TOKEN:-SK00000000000000000000000000000000}" \
    TWILIO_VERIFY_SERVICE_SID="${TWILIO_VERIFY_SERVICE_SID:-VA00000000000000000000000000000000}" \
    TWILIO_API_BASE_URL="${TWILIO_API_BASE_URL:-http://127.0.0.1:8081/v2/Service}" \
    "$BUILD_BIN/$SERVICE_BINARY_PDS" serve --config "$CONFIG_DIR/pds-config.json" --port "$SERVICE_PORT_PDS" --data-dir "$PDS_DATA" --foreground > "$ATPROTO_E2E_LOG_DIR/pds.log" 2>&1 &
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
    export APPVIEW_PDS_URL="$SERVICE_URL_PDS"
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
        log_info "Starting PDS2 on port $SERVICE_PORT_PDS2..."
        PDS_MASTER_SECRET="test-master-secret-456" \
        PDS_PLC_KEYS_DIR="$PDS2_DATA/keys" \
        PDS_ALLOW_HTTP=1 \
        "$BUILD_BIN/$SERVICE_BINARY_PDS" serve --config "$CONFIG_DIR/pds2-config.json" --port "$SERVICE_PORT_PDS2" --data-dir "$PDS2_DATA" --foreground > "$ATPROTO_E2E_LOG_DIR/pds2.log" 2>&1 &
        echo "PDS2_PID=$!" >> "$PID_FILE"
        sleep 3
        wait_for_service pds2 60
    fi

    # ── Start Jelcz video service (optional) ─────────────────────────────────
    if [[ -x "$BUILD_BIN/$SERVICE_BINARY_VIDEO" ]]; then
        VIDEO_DATA="$DATA_ROOT/video"
        mkdir -p "$VIDEO_DATA" "$VIDEO_DATA/blobs"
        log_info "Starting Jelcz video service on port $SERVICE_PORT_VIDEO..."
        JELCZ_DATA_DIR="$VIDEO_DATA" \
        JELCZ_BLOB_DIR="$VIDEO_DATA/blobs" \
        JELCZ_PDS_URL="$SERVICE_URL_PDS" \
        JELCZ_PLC_URL="$SERVICE_URL_PLC" \
        JELCZ_DID="did:web:localhost" \
        "$BUILD_BIN/$SERVICE_BINARY_VIDEO" serve --port "$SERVICE_PORT_VIDEO" \
            > "$ATPROTO_E2E_LOG_DIR/video.log" 2>&1 &
        echo "VIDEO_PID=$!" >> "$PID_FILE"
        sleep 2
        wait_for_http "$SERVICE_URL_VIDEO/_health" "Jelcz" 30 || \
            log_warn "Jelcz video service not healthy (scenario 36 will fail)"
    else
        log_warn "Jelcz binary not found; scenario 36 will be skipped"
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
    echo "  Video:   $SERVICE_URL_VIDEO"
    echo "  UI:      $SERVICE_URL_UI"
    if [[ "$WITH_PDS2" == "true" ]]; then
        echo "  PDS2:    $SERVICE_URL_PDS2"
    fi
    if [[ "$WITH_PHONE_VERIFICATION" == "true" ]]; then
        echo "  Mock Twilio: http://127.0.0.1:8081"
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
        log_info "Including second PDS (port $SERVICE_PORT_PDS2)"
    fi
    if [[ "$SKIP_DOCKER_STAGE" != "true" ]] && docker_staging_needs_refresh; then
        log_info "Staging Linux binaries for Docker local network..."
        "$REPO_ROOT/scripts/stage-docker-binaries.sh"
    elif [[ "$SKIP_DOCKER_STAGE" == "true" ]]; then
        log_warn "Reusing existing staged Docker binaries"
    else
        log_info "Staged Docker binaries are current"
    fi
    stop_stale_host_processes
    stop_stale_docker_e2e
    stop_docker_services
    "${COMPOSE_CMD[@]}" up -d --build
fi

if [[ "$TOPOLOGY_MODE" == "true" && -f "$TOPOLOGY_MANIFEST_JSON" ]]; then
    deno run -A "$SCRIPT_DIR/wait_topology.ts" \
        --manifest "$TOPOLOGY_MANIFEST_JSON" \
        --compose-project "$ATPROTO_E2E_COMPOSE_PROJECT" \
        --compose-file "$TOPOLOGY_COMPOSE_FILE" || error_exit "Topology services failed to start"
else
    wait_for_service plc 60
    wait_for_service pds 60
    wait_for_service relay 60
    wait_for_service appview 90 || error_exit "AppView failed to start within 90s"
fi
if [[ -n "$WEB_CLIENT_PRESET" ]]; then
    web_client_health_path="/"
    if [[ "$WEB_CLIENT_PRESET" == "garazyk-ui" ]]; then
        web_client_health_path="/lab"
    fi
    wait_for_http "http://127.0.0.1:$WEB_CLIENT_PORT$web_client_health_path" "web-client ($WEB_CLIENT_PRESET)" 120 || \
        error_exit "web-client failed to start within 120s"
fi

if [[ "$TOPOLOGY_MODE" != "true" && "$WITH_PDS2" == "true" ]]; then
    wait_for_service pds2 60
fi

echo ""
log_info "Waiting for services to settle..."
sleep 5
echo ""
echo "  Run:     $ATPROTO_E2E_RUN_DIR"
echo "  Project: $ATPROTO_E2E_COMPOSE_PROJECT"
if [[ "$TOPOLOGY_MODE" == "true" ]]; then
    echo "  Manifest: $TOPOLOGY_MANIFEST_JSON"
fi
if [[ "$KEEP_RUNNING" == "true" ]]; then
    echo "  Stop:    $0 --teardown --run-id $ATPROTO_E2E_RUN_ID"
fi
log_ok "Local network is ready!"
echo ""
echo "  PLC:     $SERVICE_URL_PLC"
echo "  PDS:     $SERVICE_URL_PDS"
echo "  Relay:   $SERVICE_URL_RELAY"
echo "  AppView: $SERVICE_URL_APPVIEW"
if [[ -n "$WEB_CLIENT_PRESET" ]]; then
    echo "  Web UI:  http://127.0.0.1:$WEB_CLIENT_PORT"
    echo "  Client:  $WEB_CLIENT_PRESET ($CLIENT_FLOW)"
fi
if [[ "$WITH_PDS2" == "true" ]]; then
    echo "  PDS2:    $SERVICE_URL_PDS2"
fi
echo ""
