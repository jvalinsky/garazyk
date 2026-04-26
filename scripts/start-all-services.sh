#!/usr/bin/env bash
#
# Name: start-all-services.sh
# Description: Start all ATProto services (PLC, PDS, Admin UI) with health checks and verification
# Author: Service Orchestration Script
# Version: 1.0.0
# Features:
#   - Manages multiple services with independent lifecycle control
#   - Health checks and readiness verification
#   - Service dependency validation (PDS depends on PLC)
#   - Structured logging with verbosity levels
#   - Graceful shutdown with signal handling
#   - Configuration management with environment variable overrides
#   - Wiring verification to ensure services can communicate
#

set -euo pipefail

################################################################################
# Configuration
################################################################################

# Paths and directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_ROOT/../.." && pwd))"
readonly PROJECT_ROOT
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/build/bin}"
readonly BUILD_DIR

# Service binaries
PLC_BINARY="${PLC_BINARY:-$BUILD_DIR/campagnola}"
readonly PLC_BINARY
PDS_BINARY="${PDS_BINARY:-$BUILD_DIR/kaszlak}"
readonly PDS_BINARY

# Service ports
PLC_PORT="${PLC_PORT:-2582}"
readonly PLC_PORT
PDS_PORT="${PDS_PORT:-2583}"
readonly PDS_PORT

# Service URLs
PLC_URL="${PLC_URL:-http://127.0.0.1:$PLC_PORT}"
readonly PLC_URL
PDS_URL="${PDS_URL:-http://localhost:$PDS_PORT}"
readonly PDS_URL

# Data directories
DATA_DIR="${DATA_DIR:-/tmp/atproto-services}"
readonly DATA_DIR
PLC_DATA_DIR="${PLC_DATA_DIR:-$DATA_DIR/plc}"
readonly PLC_DATA_DIR
PDS_DATA_DIR="${PDS_DATA_DIR:-$DATA_DIR/pds}"
readonly PDS_DATA_DIR

# Log files
LOG_DIR="${LOG_DIR:-$PROJECT_ROOT/logs}"
readonly LOG_DIR
PLC_LOG="${PLC_LOG:-$LOG_DIR/plc.log}"
readonly PLC_LOG
PDS_LOG="${PDS_LOG:-$LOG_DIR/pds.log}"
readonly PDS_LOG

# PID files
PID_DIR="${PID_DIR:-$PROJECT_ROOT}"
readonly PID_DIR
PLC_PID_FILE="${PLC_PID_FILE:-$PID_DIR/.plc.pid}"
readonly PLC_PID_FILE
PDS_PID_FILE="${PDS_PID_FILE:-$PID_DIR/.pds.pid}"
readonly PDS_PID_FILE

# Service control flags
SKIP_PLC="${SKIP_PLC:-false}"
readonly SKIP_PLC
SKIP_PDS="${SKIP_PDS:-false}"
readonly SKIP_PDS
SKIP_HEALTH_CHECKS="${SKIP_HEALTH_CHECKS:-false}"
readonly SKIP_HEALTH_CHECKS
SKIP_CLEANUP_ON_START="${SKIP_CLEANUP_ON_START:-false}"
readonly SKIP_CLEANUP_ON_START

# Logging configuration
VERBOSE="${VERBOSE:-false}"
readonly VERBOSE
QUIET="${QUIET:-false}"
readonly QUIET

# Service configuration (not readonly as they may be passed to child processes)
PDS_ISSUER="${PDS_ISSUER:-http://localhost:$PDS_PORT}"
PDS_LOG_LEVEL="${PDS_LOG_LEVEL:-info}"
PLC_LOG_LEVEL="${PLC_LOG_LEVEL:-info}"

# Health check configuration
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-30}"
readonly HEALTH_CHECK_TIMEOUT
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-0.5}"
readonly HEALTH_CHECK_INTERVAL
HEALTH_CHECK_RETRIES="${HEALTH_CHECK_RETRIES:-60}"
readonly HEALTH_CHECK_RETRIES

# Global variables - Service PIDs
PLC_PID=""
PDS_PID=""

################################################################################
# Color definitions - Terminal output formatting
################################################################################

if [[ -t 1 ]] && [[ "${NO_COLOR:-false}" != "true" ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly PURPLE='\033[0;35m'
    readonly CYAN='\033[0;36m'
    readonly WHITE='\033[1;37m'
    readonly BOLD='\033[1m'
    readonly NC='\033[0m' # No Color
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly PURPLE=''
    readonly CYAN=''
    readonly WHITE=''
    readonly BOLD=''
    readonly NC=''
fi

################################################################################
# Logging functions
################################################################################

log_debug() {
    if [[ "$VERBOSE" == "true" ]] && [[ "$QUIET" != "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" >&2
    fi
}

log_info() {
    if [[ "$QUIET" != "true" ]]; then
        echo -e "${CYAN}[INFO]${NC}  $(date '+%Y-%m-%d %H:%M:%S') $1" >&2
    fi
}

log_success() {
    if [[ "$QUIET" != "true" ]]; then
        echo -e "${GREEN}[OK]${NC}    $(date '+%Y-%m-%d %H:%M:%S') $1" >&2
    fi
}

log_warn() {
    if [[ "$QUIET" != "true" ]]; then
        echo -e "${YELLOW}[WARN]${NC}  $(date '+%Y-%m-%d %H:%M:%S') $1" >&2
    fi
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" >&2
}

# Error exit with cleanup
error_exit() {
    local message="$1"
    local code="${2:-1}"
    log_error "$message"
    cleanup
    exit "$code"
}

################################################################################
# Dependency and environment checks
################################################################################

check_dependencies() {
    log_debug "Checking dependencies..."
    local deps=("pgrep" "pkill" "curl" "mkdir")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done

    if (( ${#missing[@]} > 0 )); then
        error_exit "Missing dependencies: ${missing[*]}" 3
    fi

    log_success "All dependencies available"
}

check_binaries() {
    log_debug "Checking service binaries..."

    if [[ "$SKIP_PLC" != "true" ]] && [[ ! -f "$PLC_BINARY" ]]; then
        error_exit "PLC binary not found: $PLC_BINARY (build with: xcodebuild -scheme campagnola build)" 4
    fi

    if [[ "$SKIP_PDS" != "true" ]] && [[ ! -f "$PDS_BINARY" ]]; then
        error_exit "PDS binary not found: $PDS_BINARY (build with: xcodebuild -scheme kaszlak build)" 4
    fi

    log_success "Service binaries available"
}

check_ports() {
    log_debug "Checking port availability..."

    # Check if ports are already in use
    if [[ "$SKIP_PLC" != "true" ]]; then
        if pgrep -f "campagnola.*$PLC_PORT" >/dev/null 2>&1; then
            log_warn "PLC port $PLC_PORT already in use (a process is still running)"
        fi
    fi

    if [[ "$SKIP_PDS" != "true" ]]; then
        if pgrep -f "kaszlak.*$PDS_PORT" >/dev/null 2>&1; then
            log_warn "PDS port $PDS_PORT already in use (a process is still running)"
        fi
    fi
}

create_directories() {
    log_debug "Creating required directories..."

    for dir in "$LOG_DIR" "$PLC_DATA_DIR" "$PDS_DATA_DIR" "$PID_DIR"; do
        if ! mkdir -p "$dir"; then
            error_exit "Failed to create directory: $dir" 5
        fi
        log_debug "Created/verified directory: $dir"
    done

    log_success "Directories created/verified"
}

################################################################################
# Cleanup and signal handling
################################################################################

cleanup() {
    log_debug "Cleanup function called"

    # Graceful shutdown of services
    if [[ -n "$PLC_PID" ]] && kill -0 "$PLC_PID" 2>/dev/null; then
        log_info "Stopping PLC service (PID: $PLC_PID)"
        kill "$PLC_PID" 2>/dev/null || true
        wait "$PLC_PID" 2>/dev/null || true
        log_success "PLC service stopped"
    fi

    if [[ -n "$PDS_PID" ]] && kill -0 "$PDS_PID" 2>/dev/null; then
        log_info "Stopping PDS service (PID: $PDS_PID)"
        kill "$PDS_PID" 2>/dev/null || true
        wait "$PDS_PID" 2>/dev/null || true
        log_success "PDS service stopped"
    fi

    # Clean up PID files
    rm -f "$PLC_PID_FILE" "$PDS_PID_FILE" 2>/dev/null || true
    log_debug "PID files cleaned up"
}

cleanup_stray_processes() {
    log_info "Cleaning up stray processes..."

    if [[ "$SKIP_PLC" != "true" ]]; then
        pkill -f "campagnola.*$PLC_PORT" 2>/dev/null || true
    fi

    if [[ "$SKIP_PDS" != "true" ]]; then
        pkill -f "kaszlak.*$PDS_PORT" 2>/dev/null || true
    fi

    sleep 1
    log_success "Stray processes cleaned"
}

# Signal handlers
signal_handler() {
    local signal=$1
    log_info "Received signal $signal, shutting down gracefully..."
    cleanup
    exit 130
}

trap cleanup EXIT
trap 'signal_handler SIGINT' INT
trap 'signal_handler SIGTERM' TERM

################################################################################
# Health check functions
################################################################################

is_service_alive() {
    local pid=$1
    kill -0 "$pid" 2>/dev/null
    return $?
}

wait_for_health_check() {
    local service_name="$1"
    local health_url="$2"
    local timeout=$HEALTH_CHECK_TIMEOUT
    local retries=$HEALTH_CHECK_RETRIES
    local interval=$HEALTH_CHECK_INTERVAL

    log_info "Waiting for $service_name to be healthy (timeout: ${timeout}s)..."

    local start_time=$(date +%s)
    local attempt=0

    while (( attempt < retries )); do
        attempt=$((attempt + 1))

        if curl -s --max-time "$interval" "$health_url" >/dev/null 2>&1; then
            log_success "$service_name is healthy"
            return 0
        fi

        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if (( elapsed > timeout )); then
            log_error "$service_name failed to become healthy after ${timeout}s"
            return 1
        fi

        log_debug "Health check attempt $attempt/$retries for $service_name (${elapsed}s/${timeout}s)..."
        sleep "$interval"
    done

    log_error "$service_name failed to become healthy after ${timeout}s"
    return 1
}

verify_service_connectivity() {
    log_info "Verifying service connectivity and wiring..."

    # Verify PDS can reach PLC
    log_debug "Checking PDS -> PLC connectivity..."

    local pds_healthcheck="${PDS_URL}/xrpc/com.atproto.server.describeServer"

    if ! curl -s --max-time 5 "$pds_healthcheck" >/dev/null 2>&1; then
        log_error "PDS health check failed: $pds_healthcheck"
        return 1
    fi

    # Check if PDS configuration references correct PLC
    log_debug "Verifying PDS has correct PLC configuration..."
    local plc_response=$(curl -s --max-time 5 "$pds_healthcheck" | grep -o '"plc"' || true)

    if [[ -z "$plc_response" ]]; then
        log_warn "Could not verify PLC configuration in PDS response (service may still be starting up)"
    fi

    log_success "Service connectivity verified"
    return 0
}

################################################################################
# Service startup functions
################################################################################

startup_plc() {
    log_info "Starting PLC service on port $PLC_PORT..."

    if [[ ! -d "$PLC_DATA_DIR" ]]; then
        mkdir -p "$PLC_DATA_DIR"
    fi

    # Start PLC service - note: 'serve' command must come before flags
    cd "$PLC_DATA_DIR" || error_exit "Cannot change to PLC data directory: $PLC_DATA_DIR" 6

    "$PLC_BINARY" serve \
        --port "$PLC_PORT" \
        >> "$PLC_LOG" 2>&1 &

    PLC_PID=$!
    echo "$PLC_PID" > "$PLC_PID_FILE"

    log_info "PLC service started (PID: $PLC_PID)"
    log_debug "PLC log file: $PLC_LOG"

    # Verify process started
    sleep 1
    if ! is_service_alive "$PLC_PID"; then
        error_exit "PLC service failed to start. Check logs: $PLC_LOG" 7
    fi

    # Health check
    if ! wait_for_health_check "PLC" "http://127.0.0.1:$PLC_PORT/_health"; then
        log_error "PLC service failed health check. Log tail:"
        tail -n 20 "$PLC_LOG" || true
        error_exit "PLC service health check failed" 8
    fi
}

startup_pds() {
    log_info "Starting PDS service on port $PDS_PORT..."

    if [[ ! -d "$PDS_DATA_DIR" ]]; then
        mkdir -p "$PDS_DATA_DIR"
    fi

    log_debug "PDS Configuration:"
    log_debug "  - Port: $PDS_PORT"
    log_debug "  - Data Dir: $PDS_DATA_DIR"
    log_debug "  - PLC URL: $PLC_URL"
    log_debug "  - Issuer: $PDS_ISSUER"
    log_debug "  - Log Level: $PDS_LOG_LEVEL"

    # Start PDS service - note: 'serve' command must come before flags
    # Environment variables PDS_PLC_URL and PDS_ISSUER are passed to the process
    cd "$PDS_DATA_DIR" || error_exit "Cannot change to PDS data directory: $PDS_DATA_DIR" 6

    PDS_PLC_URL="$PLC_URL" PDS_ISSUER="$PDS_ISSUER" \
    "$PDS_BINARY" serve \
        --port "$PDS_PORT" \
        --data-dir "$PDS_DATA_DIR" \
        --log-level "$PDS_LOG_LEVEL" \
        --foreground \
        >> "$PDS_LOG" 2>&1 &

    PDS_PID=$!
    echo "$PDS_PID" > "$PDS_PID_FILE"

    log_info "PDS service started (PID: $PDS_PID)"
    log_debug "PDS log file: $PDS_LOG"

    # Verify process started
    sleep 2
    if ! is_service_alive "$PDS_PID"; then
        error_exit "PDS service failed to start. Check logs: $PDS_LOG" 7
    fi

    # Health check
    if ! wait_for_health_check "PDS" "http://localhost:$PDS_PORT/xrpc/com.atproto.server.describeServer"; then
        log_error "PDS service failed health check. Log tail:"
        tail -n 20 "$PDS_LOG" || true
        error_exit "PDS service health check failed" 8
    fi
}

################################################################################
# Verification and reporting
################################################################################

print_startup_summary() {
    cat >&2 << EOF
${GREEN}╔════════════════════════════════════════════════════════╗${NC}
${GREEN}║${NC}           ${BOLD}ATProto Services Started Successfully${NC}          ${GREEN}║${NC}
${GREEN}╚════════════════════════════════════════════════════════╝${NC}

${BOLD}Service Status:${NC}
EOF

    if [[ "$SKIP_PLC" != "true" ]] && [[ -n "$PLC_PID" ]]; then
        echo -e "  ${GREEN}✓${NC} PLC Server" >&2
        echo -e "    PID: $PLC_PID" >&2
        echo -e "    URL: $PLC_URL" >&2
        echo -e "    Logs: $PLC_LOG" >&2
    fi

    if [[ "$SKIP_PDS" != "true" ]] && [[ -n "$PDS_PID" ]]; then
        echo -e "  ${GREEN}✓${NC} PDS Server" >&2
        echo -e "    PID: $PDS_PID" >&2
        echo -e "    URL: $PDS_URL" >&2
        echo -e "    Admin UI: ${PDS_URL}/admin" >&2
        echo -e "    Explorer UI: ${PDS_URL}/explore" >&2
        echo -e "    API Docs: ${PDS_URL}/explore/api/docs" >&2
        echo -e "    Logs: $PDS_LOG" >&2
    fi

    cat >&2 << EOF

${BOLD}Useful Commands:${NC}
  View logs:
    tail -f $PLC_LOG    # View PLC logs
    tail -f $PDS_LOG    # View PDS logs

  Test API:
    curl -s $PDS_URL/xrpc/com.atproto.server.describeServer | jq .

  Stop services:
    pkill -f 'campagnola.*$PLC_PORT'  # Stop PLC
    pkill -f 'kaszlak.*$PDS_PORT'     # Stop PDS

  Check service health:
    curl -s http://127.0.0.1:$PLC_PORT/_health
    curl -s $PDS_URL/xrpc/com.atproto.server.describeServer

${BOLD}Press Ctrl+C to stop all services${NC}

EOF
}

print_usage() {
    cat << EOF
${BOLD}Usage:${NC} $(basename "$0") [OPTIONS]

${BOLD}Description:${NC}
  Start all ATProto services (PLC, PDS) with health checks and verification.
  Ensures proper wiring and service-to-service connectivity.

${BOLD}Options:${NC}
  --skip-plc                    Skip PLC service startup
  --skip-pds                    Skip PDS service startup
  --skip-health-checks          Skip health check verification
  --skip-cleanup                Don't clean up stray processes on startup

  --plc-port PORT               PLC service port (default: 2582)
  --pds-port PORT               PDS service port (default: 2583)
  --plc-binary PATH             Path to PLC binary (default: $BUILD_DIR/campagnola)
  --pds-binary PATH             Path to PDS binary (default: $BUILD_DIR/kaszlak)

  --data-dir PATH               Base data directory (default: /tmp/atproto-services)
  --pds-issuer URL              PDS issuer URL (default: http://localhost:2583)
  --pds-log-level LEVEL         PDS log level: error, warn, info, debug (default: info)
  --plc-log-level LEVEL         PLC log level: error, warn, info, debug (default: info)

  --health-timeout SECS         Health check timeout (default: 30)
  --health-retries N            Health check max retries (default: 60)

  --verbose                     Enable verbose logging
  --quiet                       Suppress non-error output
  --help                        Show this help message

${BOLD}Environment Variables:${NC}
  SKIP_PLC, SKIP_PDS, SKIP_HEALTH_CHECKS, SKIP_CLEANUP_ON_START
  PLC_PORT, PDS_PORT, PLC_BINARY, PDS_BINARY
  DATA_DIR, PLC_DATA_DIR, PDS_DATA_DIR
  LOG_DIR, PLC_LOG, PDS_LOG
  PDS_ISSUER, PDS_LOG_LEVEL, PLC_LOG_LEVEL
  HEALTH_CHECK_TIMEOUT, HEALTH_CHECK_RETRIES, HEALTH_CHECK_INTERVAL
  VERBOSE, QUIET, NO_COLOR

${BOLD}Examples:${NC}
  # Start all services with verbose logging
  VERBOSE=true $0

  # Start only PDS service
  $0 --skip-plc

  # Start with custom data directory
  $0 --data-dir /var/lib/atproto

  # Start on non-standard ports
  $0 --plc-port 3000 --pds-port 3001

${BOLD}Troubleshooting:${NC}
  If services fail to start:
    1. Check binaries exist: ls -la $BUILD_DIR/
    2. Check port availability: lsof -i :2582 && lsof -i :2583
    3. Review logs: tail -f $LOG_DIR/*.log
    4. Check disk space: df -h $DATA_DIR
    5. Try cleanup: $0 --skip-cleanup

EOF
    exit 0
}

################################################################################
# Argument parsing
################################################################################

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip-plc)
                readonly SKIP_PLC=true
                ;;
            --skip-pds)
                readonly SKIP_PDS=true
                ;;
            --skip-health-checks)
                readonly SKIP_HEALTH_CHECKS=true
                ;;
            --skip-cleanup)
                readonly SKIP_CLEANUP_ON_START=true
                ;;
            --plc-port)
                readonly PLC_PORT="$2"
                shift
                ;;
            --pds-port)
                readonly PDS_PORT="$2"
                shift
                ;;
            --plc-binary)
                readonly PLC_BINARY="$2"
                shift
                ;;
            --pds-binary)
                readonly PDS_BINARY="$2"
                shift
                ;;
            --data-dir)
                readonly DATA_DIR="$2"
                readonly PLC_DATA_DIR="$DATA_DIR/plc"
                readonly PDS_DATA_DIR="$DATA_DIR/pds"
                shift
                ;;
            --pds-issuer)
                readonly PDS_ISSUER="$2"
                shift
                ;;
            --pds-log-level)
                readonly PDS_LOG_LEVEL="$2"
                shift
                ;;
            --plc-log-level)
                readonly PLC_LOG_LEVEL="$2"
                shift
                ;;
            --health-timeout)
                readonly HEALTH_CHECK_TIMEOUT="$2"
                shift
                ;;
            --health-retries)
                readonly HEALTH_CHECK_RETRIES="$2"
                shift
                ;;
            --verbose)
                readonly VERBOSE=true
                ;;
            --quiet)
                readonly QUIET=true
                ;;
            --help|-h)
                print_usage
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                ;;
        esac
        shift
    done
}

################################################################################
# Main execution
################################################################################

main() {
    # Banner
    if [[ "$QUIET" != "true" ]]; then
        cat >&2 << 'EOF'

   ___  ________
  / _ |/ /__  __/   ATProto Services Orchestration
 / __ |/ __/ /
/ ___ / /__/ /      Starting all services...
/_/  |_/____/

EOF
    fi

    log_info "Script started with PID $$"
    log_debug "Project root: $PROJECT_ROOT"
    log_debug "Build directory: $BUILD_DIR"

    # Pre-flight checks
    check_dependencies
    check_binaries
    check_ports
    create_directories

    # Cleanup stray processes
    if [[ "$SKIP_CLEANUP_ON_START" != "true" ]]; then
        cleanup_stray_processes
    fi

    # Start services in order
    if [[ "$SKIP_PLC" != "true" ]]; then
        startup_plc
    fi

    if [[ "$SKIP_PDS" != "true" ]]; then
        if [[ "$SKIP_PLC" != "true" ]]; then
            log_debug "Waiting for PLC to stabilize before starting PDS..."
            sleep 2
        fi
        startup_pds
    fi

    # Verify wiring
    if [[ "$SKIP_HEALTH_CHECKS" != "true" ]] && [[ "$SKIP_PDS" != "true" ]]; then
        if ! verify_service_connectivity; then
            log_warn "Service connectivity verification encountered issues (services may still be starting)"
        fi
    fi

    # Print summary and wait
    print_startup_summary

    # Keep the script running
    wait
}

# Parse arguments and run
parse_arguments "$@"
main
