#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The docker/e2e PLC fixture exposes /xrpc/_health on port 2580, unlike the
# scenario local-network PLC on port 2582.
PLC_PORT="${PLC_PORT:-2580}"
PLC_HEALTH_PATH="${PLC_HEALTH_PATH:-/xrpc/_health}"
APPVIEW_ADMIN_SECRET="${APPVIEW_ADMIN_SECRET:-e2e-secret}"
export PLC_PORT PLC_HEALTH_PATH APPVIEW_ADMIN_SECRET

source "$SCRIPT_DIR/../lib/common.sh"

PROJECT_ROOT="$(resolve_project_root "$SCRIPT_DIR")"
E2E_DIR="$PROJECT_ROOT/docker/e2e"
COMPOSE_FILE="$E2E_DIR/docker-compose.yml"

BUILD_ONLY=false
KEEP_RUNNING=false
COLLECT_DIAGNOSTICS=false

usage() {
    cat <<USAGE
Usage: $0 [--build-only] [--keep-running] [--collect-diagnostics] [--run-id ID] [--diagnostics-dir DIR]

  --build-only            Build Docker image and exit
  --keep-running          Leave services running after tests
  --collect-diagnostics   Capture diagnostics for the current run and exit
  --run-id ID             Reuse or name the shared e2e run directory
  --diagnostics-dir DIR   Write diagnostics to DIR
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --build-only) BUILD_ONLY=true ;;
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
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
    shift
done

if [[ "$COLLECT_DIAGNOSTICS" == "true" ]]; then
    atproto_e2e_load_latest_run_id "docker-e2e"
fi
atproto_e2e_init_run
if [[ "$COLLECT_DIAGNOSTICS" != "true" && "$BUILD_ONLY" != "true" ]]; then
    atproto_e2e_store_latest_run_id "docker-e2e"
fi
COMPOSE_CMD=(docker compose -p "$ATPROTO_E2E_COMPOSE_PROJECT" -f "$COMPOSE_FILE")

collect_diagnostics() {
    atproto_collect_diagnostics "$ATPROTO_E2E_DIAGNOSTICS_DIR" \
        "$E2E_DIR" "$ATPROTO_E2E_COMPOSE_PROJECT" "$COMPOSE_FILE"
}

cleanup() {
    local status="${1:-0}"
    if [[ "$status" -ne 0 ]]; then
        collect_diagnostics || true
    fi
    if [[ "$KEEP_RUNNING" != "true" ]]; then
        log_info "Cleaning up Docker e2e services..."
        (cd "$E2E_DIR" && "${COMPOSE_CMD[@]}" down --volumes --remove-orphans 2>/dev/null || true)
    else
        log_info "Keeping services running for run id $ATPROTO_E2E_RUN_ID"
        log_info "Stop with: $0 --run-id $ATPROTO_E2E_RUN_ID --collect-diagnostics && docker compose -p $ATPROTO_E2E_COMPOSE_PROJECT -f $COMPOSE_FILE down --volumes --remove-orphans"
    fi
}

on_exit() {
    local status=$?
    cleanup "$status"
    exit "$status"
}

on_interrupt() {
    log_warn "Interrupted; collecting diagnostics before shutdown"
    collect_diagnostics || true
    cleanup 130
    exit 130
}

trap on_exit EXIT
trap on_interrupt INT TERM

wait_for_url() {
    local name="$1"
    local url="$2"
    local max_attempts="${3:-30}"
    if (( $# >= 3 )); then
        shift 3
    else
        shift "$#"
    fi
    local attempt=1

    log_info "Waiting for $name at $url..."
    while [[ "$attempt" -le "$max_attempts" ]]; do
        if curl -sS -f "$@" "$url" >/dev/null 2>&1; then
            log_ok "$name is ready"
            return 0
        fi
        sleep 2
        attempt=$((attempt + 1))
    done

    log_error "$name failed to become ready after $max_attempts attempts"
    return 1
}

build_images() {
    check_dependencies docker
    log_info "Building Docker image nspds:local..."
    docker build -f "$PROJECT_ROOT/docker/Dockerfile.gnustep" -t nspds:local "$PROJECT_ROOT"
    log_ok "Docker image built"
}

start_services() {
    check_dependencies docker curl
    log_info "Starting Docker e2e services with project $ATPROTO_E2E_COMPOSE_PROJECT..."
    (cd "$E2E_DIR" && "${COMPOSE_CMD[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true)
    (cd "$E2E_DIR" && "${COMPOSE_CMD[@]}" up -d --build)
}

run_tests() {
    log_info "Running Docker e2e integration tests..."
    local failed=0

    log_info "Test 1: PLC health check..."
    if curl -sf "$SERVICE_URL_PLC$SERVICE_HEALTH_PLC" >/dev/null; then
        log_ok "PLC health check passed"
    else
        log_error "PLC health check failed"
        failed=$((failed + 1))
    fi

    log_info "Test 2: PDS health check..."
    if curl -sf "$SERVICE_URL_PDS/xrpc/com.atproto.server.describeServer" >/dev/null; then
        log_ok "PDS health check passed"
    else
        log_error "PDS health check failed"
        failed=$((failed + 1))
    fi

    log_info "Test 3: PDS describeServer response..."
    local pds_response
    pds_response=$(curl -sS "$SERVICE_URL_PDS/xrpc/com.atproto.server.describeServer")
    if echo "$pds_response" | grep -q "did"; then
        log_ok "PDS describeServer returned a DID"
    else
        log_error "PDS describeServer returned invalid response"
        failed=$((failed + 1))
    fi

    log_info "Test 4: Relay health endpoint..."
    if curl -sf "$SERVICE_URL_RELAY/api/relay/health" >/dev/null; then
        log_ok "Relay health endpoint responded"
    else
        log_error "Relay health endpoint failed"
        failed=$((failed + 1))
    fi

    log_info "Test 5: Create account on PDS..."
    local test_handle="test-${ATPROTO_E2E_RUN_ID}-e2e"
    local create_response
    create_response=$(curl -sS -X POST "$SERVICE_URL_PDS/xrpc/com.atproto.server.createAccount" \
        -H "Content-Type: application/json" \
        -d "{\"handle\":\"$test_handle.garazyk.xyz\",\"email\":\"$test_handle@test.local\",\"password\":\"testpass123\"}")

    if echo "$create_response" | grep -q "accessJwt"; then
        log_ok "Account creation succeeded"
    else
        log_warn "Account creation did not return accessJwt: $(echo "$create_response" | atproto_redact_stream)"
    fi

    if [[ "$failed" -eq 0 ]]; then
        log_ok "All critical Docker e2e tests passed"
        return 0
    fi
    log_error "$failed critical Docker e2e test(s) failed"
    return 1
}

if [[ "$COLLECT_DIAGNOSTICS" == "true" ]]; then
    collect_diagnostics
    exit 0
fi

if [[ "$BUILD_ONLY" == "true" ]]; then
    build_images
    exit 0
fi

build_images
start_services

wait_for_url "PLC" "$SERVICE_URL_PLC$SERVICE_HEALTH_PLC"
wait_for_url "PDS" "$SERVICE_URL_PDS/xrpc/com.atproto.server.describeServer"
wait_for_url "Relay" "$SERVICE_URL_RELAY/api/relay/health"
wait_for_url "AppView" "$SERVICE_URL_APPVIEW/admin/backfill/status" 45 \
    -H "Authorization: Bearer $APPVIEW_ADMIN_SECRET"

run_tests
