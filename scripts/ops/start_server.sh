#!/usr/bin/env bash
#
# Name: start_server.sh
# Description: Start one local ATProto PDS server with PID/log management
# Version: 1.0.0
#
# This lightweight launcher is useful when debugging kaszlak by itself rather
# than bringing up the full local service graph. It validates the binary,
# refuses to overwrite a live PID file, redirects output to a stable log file,
# and removes its PID file during cleanup.
#

set -euo pipefail

# Configuration is environment-overridable so the same script can point at a
# local build, an installed binary, or a test-specific log/PID directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
source "$SCRIPT_DIR/../lib/common.sh"

PROJECT_ROOT="$(resolve_project_root "$SCRIPT_DIR")"
readonly PROJECT_ROOT
SERVER_BINARY="${SERVER_BINARY:-$PROJECT_ROOT/build/bin/kaszlak}"
readonly SERVER_BINARY
LOG_FILE="${LOG_FILE:-$PROJECT_ROOT/server.log}"
readonly LOG_FILE
PID_FILE="${PID_FILE:-$PROJECT_ROOT/server.pid}"
readonly PID_FILE
VERBOSE="${VERBOSE:-false}"
readonly VERBOSE

# Populated after the background process starts; cleanup uses it to avoid
# killing an unrelated PID from an old file.
SERVER_PID=""

cleanup() {
    # Stop only the child this invocation started. Existing services detected
    # by check_existing_server are left alone.
    log_debug "Cleaning up resources"

    # Stop server if running
    if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        log_info "Stopping server (PID: $SERVER_PID)"
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi

    # Remove PID file
    [[ -f "$PID_FILE" ]] && rm -f "$PID_FILE" 2>/dev/null || true
}

trap cleanup EXIT
trap 'error_exit "Script interrupted by user" 130' INT TERM

validate_server_binary() {
    # Fail before changing directories or creating PID files when the caller
    # points SERVER_BINARY at a missing or non-executable path.
    if [[ ! -f "$SERVER_BINARY" ]]; then
        error_exit "Server binary not found: $SERVER_BINARY" 5
    fi

    if [[ ! -x "$SERVER_BINARY" ]]; then
        error_exit "Server binary not executable: $SERVER_BINARY" 5
    fi

    log_debug "Server binary validated: $SERVER_BINARY"
}

check_existing_server() {
    # PID files are authoritative when they point at a live process. Stale files
    # are removed so a crashed prior run does not block local debugging.
    if [[ -f "$PID_FILE" ]]; then
        local existing_pid
        existing_pid=$(cat "$PID_FILE" 2>/dev/null || echo "")

        if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
            log_warn "Server already running with PID: $existing_pid"
            log_warn "Use stop_server.sh or kill $existing_pid manually"
            exit 1
        else
            log_warn "Removing stale PID file: $PID_FILE"
            rm -f "$PID_FILE"
        fi
    fi
}

start_server() {
    # The server runs from PROJECT_ROOT so relative config/default paths match
    # the expectations used by local development commands.
    log_info "Starting ATProto PDS server"

    # Change to project root
    cd "$PROJECT_ROOT"

    # Start server in background
    "$SERVER_BINARY" > "$LOG_FILE" 2>&1 &
    SERVER_PID=$!

    # Write PID to file
    echo "$SERVER_PID" > "$PID_FILE"

    # Verify server started
    sleep 2
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        error_exit "Server failed to start. Check logs: $LOG_FILE" 1
    fi

    log_info "Server started successfully with PID: $SERVER_PID"
    log_info "Log file: $LOG_FILE"
    log_info "PID file: $PID_FILE"
}

main() {
    log_info "Starting ATProto PDS server startup script"

    # Validate prerequisites
    check_dependencies
    validate_server_binary
    check_existing_server

    # Start server
    start_server

    log_info "Server startup completed successfully"
}

# Preserve "$@" for future options even though the current script has no custom
# argument parser.
main "$@"
