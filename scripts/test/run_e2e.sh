#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

KEEP_RUNNING=false
COLLECT_DIAGNOSTICS=false

usage() {
    cat <<USAGE
Usage: $0 [--keep-running] [--collect-diagnostics] [--run-id ID] [--diagnostics-dir DIR]

  --keep-running          Leave native PLC/PDS running after setup and tests
  --collect-diagnostics   Capture diagnostics for the current run and exit
  --run-id ID             Reuse or name the shared e2e run directory
  --diagnostics-dir DIR   Write diagnostics to DIR
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
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
    atproto_e2e_load_latest_run_id "native-e2e"
fi
atproto_e2e_init_run
if [[ "$COLLECT_DIAGNOSTICS" != "true" ]]; then
    atproto_e2e_store_latest_run_id "native-e2e"
fi

PROJECT_ROOT="$(resolve_project_root "$SCRIPT_DIR")"
BUILD_DIR="$(resolve_build_dir "$PROJECT_ROOT")"
DATA_DIR="$ATPROTO_E2E_RUN_DIR/data/native-e2e"
CONFIG_DIR="$ATPROTO_E2E_RUN_DIR/config"
CONFIG_PATH="$CONFIG_DIR/pds-config.json"
PDS_LOG="$ATPROTO_E2E_LOG_DIR/pds.log"
PLC_LOG="$ATPROTO_E2E_LOG_DIR/plc.log"

collect_native_diagnostics() {
    atproto_collect_diagnostics "$ATPROTO_E2E_DIAGNOSTICS_DIR"
}

cleanup() {
    local status="${1:-0}"
    if [[ "$status" -ne 0 ]]; then
        collect_native_diagnostics || true
        echo "[E2E] Logs preserved at $ATPROTO_E2E_LOG_DIR"
        echo "[E2E] Diagnostics preserved at $ATPROTO_E2E_DIAGNOSTICS_DIR"
    fi

    if [[ "$KEEP_RUNNING" != "true" ]]; then
        echo "[E2E] Cleaning up native services..."
        if [[ -n "${SERVER_PID:-}" ]]; then
            kill "${SERVER_PID}" 2>/dev/null || true
            wait "${SERVER_PID}" 2>/dev/null || true
        fi
        if [[ -n "${PLC_PID:-}" ]]; then
            kill "${PLC_PID}" 2>/dev/null || true
            wait "${PLC_PID}" 2>/dev/null || true
        fi
        if [[ "$status" -eq 0 ]]; then
            rm -rf "$DATA_DIR" "$CONFIG_DIR"
        fi
    else
        echo "[E2E] Keeping services running for run id $ATPROTO_E2E_RUN_ID"
        echo "[E2E] Stop PIDs from $ATPROTO_E2E_PID_FILE or rerun with the same run id and Ctrl+C."
    fi
}

on_exit() {
    local status=$?
    cleanup "$status"
    exit "$status"
}

on_interrupt() {
    echo "[E2E] Interrupted; collecting diagnostics..."
    collect_native_diagnostics || true
    cleanup 130
    exit 130
}

trap on_exit EXIT
trap on_interrupt INT TERM

if [[ "$COLLECT_DIAGNOSTICS" == "true" ]]; then
    collect_native_diagnostics
    exit 0
fi

mkdir -p "$DATA_DIR" "$CONFIG_DIR" "$ATPROTO_E2E_LOG_DIR"
cat > "$CONFIG_PATH" <<EOF
{"server":{"data_dir":"${DATA_DIR}","host":"localhost","port":${SERVICE_PORT_PDS},"issuer":"http://localhost:${SERVICE_PORT_PDS}"},"plc":{"url":"${SERVICE_URL_PLC}"}}
EOF

export PDS_USE_BIOMETRIC_PROTECTION=false
export PDS_USE_KEYCHAIN=false

echo "[E2E] Building project..."
cmake --build "$PROJECT_ROOT/build" --target kaszlak campagnola

echo "[E2E] Starting PLC server..."
"$BUILD_DIR/campagnola" serve --port "$SERVICE_PORT_PLC" > "$PLC_LOG" 2>&1 &
PLC_PID=$!
printf 'PLC_PID=%s\n' "$PLC_PID" >> "$ATPROTO_E2E_PID_FILE"
wait_for_http "$SERVICE_URL_PLC/_health" "PLC" 30

echo "[E2E] Starting PDS server..."
"$BUILD_DIR/kaszlak" serve --config "$CONFIG_PATH" --port "$SERVICE_PORT_PDS" --data-dir "$DATA_DIR" > "$PDS_LOG" 2>&1 &
SERVER_PID=$!
printf 'PDS_PID=%s\n' "$SERVER_PID" >> "$ATPROTO_E2E_PID_FILE"
wait_for_http "$SERVICE_URL_PDS/xrpc/com.atproto.server.describeServer" "PDS" 60

echo "[E2E] Creating test accounts..."
"$BUILD_DIR/kaszlak" account create \
    --config "$CONFIG_PATH" \
    --handle "e2e1-$ATPROTO_E2E_RUN_ID.test" \
    --email "e2e1-$ATPROTO_E2E_RUN_ID@test.local" \
    --password hunter2 \
    --data-dir "$DATA_DIR" \
    --verbose

"$BUILD_DIR/kaszlak" account create \
    --config "$CONFIG_PATH" \
    --handle "e2e2-$ATPROTO_E2E_RUN_ID.test" \
    --email "e2e2-$ATPROTO_E2E_RUN_ID@test.local" \
    --password hunter2 \
    --data-dir "$DATA_DIR" \
    --verbose

echo "[E2E] Running integration tests..."
export PDS_URL="$SERVICE_URL_PDS"
export PLC_URL="$SERVICE_URL_PLC"
bash "$PROJECT_ROOT/Garazyk/Tests/plc_e2e/run-integration-tests.sh"
