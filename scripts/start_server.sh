#!/usr/bin/env bash
#
# Name: start_server.sh
# Description: Start the ATProto PDS server with proper process management
# Author: Professional Bash Script Example
# Version: 1.0.0
# Date: 2024-01-01
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly PROJECT_ROOT
SERVER_BINARY="${SERVER_BINARY:-$PROJECT_ROOT/build/bin/kaszlak}"
readonly SERVER_BINARY
LOG_FILE="${LOG_FILE:-$PROJECT_ROOT/server.log}"
readonly LOG_FILE
PID_FILE="${PID_FILE:-$PROJECT_ROOT/server.pid}"
readonly PID_FILE
VERBOSE="${VERBOSE:-false}"
readonly VERBOSE

# Global variables
SERVER_PID=""

# Color definitions
if [[ -t 1 ]] && [[ "${NO_COLOR:-false}" != "true" ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly PURPLE='\033[0;35m'
    readonly CYAN='\033[0;36m'
    readonly WHITE='\033[1;37m'
    readonly NC='\033[0m' # No Color
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly PURPLE=''
    readonly CYAN=''
    readonly WHITE=''
    readonly NC=''
fi

# Logging functions with colors
log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $1" >&2
    fi
}
log_info()  { echo -e "${CYAN}[INFO]${NC} $1" >&2; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Error exit function
error_exit() {
    local message="$1"
    local code="${2:-1}"
    log_error "$message"
    cleanup
    exit "$code"
}

# Cleanup function
cleanup() {
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

# Trap signals
trap cleanup EXIT
trap 'error_exit "Script interrupted by user" 130' INT TERM

# Dependency check
check_dependencies() {
    local deps=("pgrep" "pkill")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done

    if (( ${#missing[@]} > 0 )); then
        error_exit "Missing dependencies: ${missing[*]}" 3
    fi
}

# Validate server binary
validate_server_binary() {
    if [[ ! -f "$SERVER_BINARY" ]]; then
        error_exit "Server binary not found: $SERVER_BINARY" 5
    fi

    if [[ ! -x "$SERVER_BINARY" ]]; then
        error_exit "Server binary not executable: $SERVER_BINARY" 5
    fi

    log_debug "Server binary validated: $SERVER_BINARY"
}

# Check if server is already running
check_existing_server() {
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

# Start server
start_server() {
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

# Main function
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

# Run main function with all arguments
main "$@"
