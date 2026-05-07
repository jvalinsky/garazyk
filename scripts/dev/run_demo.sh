#!/usr/bin/env bash
# run_demo.sh - Start a minimal local PLC/PDS pair and seed demo data.
#
# This developer helper is intentionally smaller than full_suite_demo.sh. It
# starts only the identity directory and PDS, wipes its temporary data root for
# a fresh run, seeds Alice/Bob records, and then leaves the processes attached
# until Ctrl+C so logs and endpoints remain available for manual inspection.
#
# Environment:
#   BUILD_DIR  Directory containing campagnola and kaszlak binaries.
#   DATA_DIR   Temporary data directory for the demo PDS state.

set -euo pipefail

# Shared library: path resolution, service constants, logging, and cleanup
# helpers. Sourcing keeps this file focused on the demo-specific sequence.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

PROJECT_ROOT="$(resolve_project_root "$SCRIPT_DIR")"
BUILD_DIR="$(resolve_build_dir "$PROJECT_ROOT")"

PLC_URL="$SERVICE_URL_PLC"
PDS_URL="$SERVICE_URL_PDS"
PLC_BIN="$BUILD_DIR/$SERVICE_BINARY_PLC"
PDS_BIN="$BUILD_DIR/$SERVICE_BINARY_PDS"
DATA_DIR="${DATA_DIR:-/tmp/objpds-demo-data}"

cleanup() {
    # Prefer PID files for children started by this script, then run the shared
    # stray-process cleanup to catch interrupted runs.
    log_info "Stopping servers..."
    if [[ -f plc.pid ]]; then
        kill "$(cat plc.pid)" 2>/dev/null || true
        rm -f plc.pid
    fi
    if [[ -f pds.pid ]]; then
        kill "$(cat pds.pid)" 2>/dev/null || true
        rm -f pds.pid
    fi
    kill_stray_processes plc pds
}

trap cleanup EXIT INT TERM

log_info "Cleaning up any existing stray servers..."
kill_stray_processes plc pds
rm -f plc.log pds.log
sleep 1

check_binaries "$BUILD_DIR" plc pds

# Clean previous state to avoid migration or partial-seed artifacts from a
# failed earlier run. The demo script is for disposable local data only.
rm -rf "$DATA_DIR"
mkdir -p "$DATA_DIR/service" # Pre-create service dir to be safe

log_info "Starting PLC server on port $SERVICE_PORT_PLC..."
"$PLC_BIN" --port "$SERVICE_PORT_PLC" > plc.log 2>&1 &
echo $! > plc.pid

log_info "Waiting for PLC server to be ready..."
if ! wait_for_http "$PLC_URL/_health" "PLC" 20; then
    log_error "PLC server failed to start. plc.log tail:"
    tail -n 80 plc.log || true
    exit 1
fi

log_info "Starting PDS server on port $SERVICE_PORT_PDS..."
export PDS_PLC_URL="$PLC_URL"
export PDS_ISSUER="$PDS_URL"
export PDS_LOG_LEVEL="debug"
# Pass a deliberately missing config file so command-line flags are the source
# of truth for this disposable demo run.
"$PDS_BIN" serve --port "$SERVICE_PORT_PDS" --data-dir "$DATA_DIR" --config /tmp/missing_config_to_force_args.json --log-level debug > pds.log 2>&1 &
echo $! > pds.pid

log_info "Waiting for PDS server to be ready..."
if ! wait_for_http "$PDS_URL/xrpc/com.atproto.server.describeServer" "PDS" 30; then
    log_error "PDS server failed to start. pds.log tail:"
    tail -n 80 pds.log || true
    exit 1
fi

# Give PDS a moment to finish initializing its PLC client before seeding.
sleep 2

log_info "Servers running. Running seed script..."
export PDS_URL="$PDS_URL"
export PDS_DATA_DIR="$DATA_DIR"
export PDS_BIN="$PDS_BIN"
python3 "$SCRIPT_DIR/demo_seed.py"

log_ok "Demo complete."
log_info "Servers are still running at $PDS_URL"
log_info "Press Ctrl+C to stop."

# Wait for background processes
wait
