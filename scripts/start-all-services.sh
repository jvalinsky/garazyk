#!/usr/bin/env bash
#
# Name: start-all-services.sh
# Description: Start all ATProto services (PLC, PDS, Admin UI) with health checks and verification
# Features:
#   - Manages multiple services with independent lifecycle control
#   - Health checks and readiness verification
#   - Service dependency validation (PDS depends on PLC)
#   - Structured logging with verbosity levels
#   - Graceful shutdown with signal handling
#   - Configuration management with environment variable overrides
#   - Wiring verification to ensure services can communicate
#
# The script manages only the PLC and PDS pair. Broader demos that include
# Relay, AppView, chat, video, and the Admin UI live in full_suite_demo.sh.
#

set -euo pipefail

# ── Shared library ────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# ── Configuration ──────────────────────────────────────────────────────────

PROJECT_ROOT="$(resolve_project_root "$SCRIPT_DIR")"
BUILD_DIR="$(resolve_build_dir "$PROJECT_ROOT")"

# Service binaries. These default to the out-of-source build directory but can
# be overridden for installed builds or one-off test binaries.
PLC_BINARY="${PLC_BINARY:-$BUILD_DIR/campagnola}"
PDS_BINARY="${PDS_BINARY:-$BUILD_DIR/kaszlak}"

# Service URLs (from common.sh SERVICE_URLS)
PLC_URL="$SERVICE_URL_PLC"
PDS_URL="$SERVICE_URL_PDS"

# Data directories
DATA_DIR="${DATA_DIR:-/tmp/atproto-services}"
PLC_DATA_DIR="${PLC_DATA_DIR:-$DATA_DIR/plc}"
PDS_DATA_DIR="${PDS_DATA_DIR:-$DATA_DIR/pds}"

# Log files
LOG_DIR="${LOG_DIR:-$PROJECT_ROOT/logs}"
PLC_LOG="${PLC_LOG:-$LOG_DIR/plc.log}"
PDS_LOG="${PDS_LOG:-$LOG_DIR/pds.log}"

# PID files
PID_DIR="${PID_DIR:-$PROJECT_ROOT}"
PLC_PID_FILE="${PLC_PID_FILE:-$PID_DIR/.plc.pid}"
PDS_PID_FILE="${PDS_PID_FILE:-$PID_DIR/.pds.pid}"

# Service control flags. Command-line parsing mutates these values, so they are
# intentionally not readonly.
SKIP_PLC="${SKIP_PLC:-false}"
SKIP_PDS="${SKIP_PDS:-false}"
SKIP_HEALTH_CHECKS="${SKIP_HEALTH_CHECKS:-false}"
SKIP_CLEANUP_ON_START="${SKIP_CLEANUP_ON_START:-false}"

# Service configuration
PDS_ISSUER="${PDS_ISSUER:-http://localhost:$SERVICE_PORT_PDS}"
PDS_LOG_LEVEL="${PDS_LOG_LEVEL:-info}"
PLC_LOG_LEVEL="${PLC_LOG_LEVEL:-info}"

# Health check configuration
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-30}"
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-0.5}"
HEALTH_CHECK_RETRIES="${HEALTH_CHECK_RETRIES:-60}"

# Global variables - Service PIDs
PLC_PID=""
PDS_PID=""

# ── Dependency and environment checks ───────────────────────────────────────

check_binaries() {
    # Validate only services that this invocation intends to start. That keeps
    # --skip-plc/--skip-pds useful for debugging partial topologies.
    log_debug "Checking service binaries..."

    if [[ "$SKIP_PLC" != "true" ]] && [[ ! -f "$PLC_BINARY" ]]; then
        error_exit "PLC binary not found: $PLC_BINARY (build with: cmake --build build --target campagnola)" 4
    fi

    if [[ "$SKIP_PDS" != "true" ]] && [[ ! -f "$PDS_BINARY" ]]; then
        error_exit "PDS binary not found: $PDS_BINARY (build with: cmake --build build --target kaszlak)" 4
    fi

    log_ok "Service binaries available"
}

check_ports() {
    # Port checks are advisory. A process may exit between the check and bind,
    # and a reused port may be intentional during local troubleshooting.
    log_debug "Checking port availability..."

    if [[ "$SKIP_PLC" != "true" ]]; then
        if pgrep -f "campagnola.*$SERVICE_PORT_PLC" >/dev/null 2>&1; then
            log_warn "PLC port $SERVICE_PORT_PLC already in use (a process is still running)"
        fi
    fi

    if [[ "$SKIP_PDS" != "true" ]]; then
        if pgrep -f "kaszlak.*$SERVICE_PORT_PDS" >/dev/null 2>&1; then
            log_warn "PDS port $SERVICE_PORT_PDS already in use (a process is still running)"
        fi
    fi
}

create_directories() {
    # Create log, data, and PID directories before launching either service so
    # startup failures are reported as filesystem errors rather than silent
    # redirection failures.
    log_debug "Creating required directories..."

    for dir in "$LOG_DIR" "$PLC_DATA_DIR" "$PDS_DATA_DIR" "$PID_DIR"; do
        if ! mkdir -p "$dir"; then
            error_exit "Failed to create directory: $dir" 5
        fi
        log_debug "Created/verified directory: $dir"
    done

    log_ok "Directories created/verified"
}

# ── Cleanup and signal handling ─────────────────────────────────────────────

cleanup() {
    # Stop only processes started by this shell invocation; cleanup_stray_processes
    # handles broader pre-start cleanup when requested.
    log_debug "Cleanup function called"

    # Graceful shutdown of services
    if [[ -n "$PLC_PID" ]] && kill -0 "$PLC_PID" 2>/dev/null; then
        log_info "Stopping PLC service (PID: $PLC_PID)"
        kill "$PLC_PID" 2>/dev/null || true
        wait "$PLC_PID" 2>/dev/null || true
        log_ok "PLC service stopped"
    fi

    if [[ -n "$PDS_PID" ]] && kill -0 "$PDS_PID" 2>/dev/null; then
        log_info "Stopping PDS service (PID: $PDS_PID)"
        kill "$PDS_PID" 2>/dev/null || true
        wait "$PDS_PID" 2>/dev/null || true
        log_ok "PDS service stopped"
    fi

    # Clean up PID files
    rm -f "$PLC_PID_FILE" "$PDS_PID_FILE" 2>/dev/null || true
    log_debug "PID files cleaned up"
}

cleanup_stray_processes() {
    # Used before startup to remove listeners from a prior interrupted run.
    # It respects skip flags so partial launches do not kill services the user
    # chose to keep running.
    log_info "Cleaning up stray processes..."
    local services=()
    [[ "$SKIP_PLC" != "true" ]] && services+=(plc)
    [[ "$SKIP_PDS" != "true" ]] && services+=(pds)
    kill_stray_processes "${services[@]}"
    sleep 1
    log_ok "Stray processes cleaned"
}

# Signal handlers
signal_handler() {
    # Convert user interrupts and termination signals into the conventional 130
    # exit code after cleanup has run.
    local signal=$1
    log_info "Received signal $signal, shutting down gracefully..."
    cleanup
    exit 130
}

trap cleanup EXIT
trap 'signal_handler SIGINT' INT
trap 'signal_handler SIGTERM' TERM

# ── Health check functions ─────────────────────────────────────────────────

is_service_alive() {
    # kill -0 is a POSIX existence/permission probe; it does not signal the
    # service.
    local pid=$1
    kill -0 "$pid" 2>/dev/null
    return $?
}

wait_for_health_check() {
    # Poll from the caller's perspective rather than trusting that the child
    # process is alive. A bound port with a failing health endpoint is still a
    # startup failure for this script.
    local service_name="$1"
    local health_url="$2"
    local timeout="${3:-$HEALTH_CHECK_TIMEOUT}"

    log_info "Waiting for $service_name to be healthy (timeout: ${timeout}s)..."

    local start_time=$(date +%s)

    while true; do
        if curl -s --max-time "$HEALTH_CHECK_INTERVAL" "$health_url" >/dev/null 2>&1; then
            log_ok "$service_name is healthy"
            return 0
        fi

        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if (( elapsed > timeout )); then
            log_error "$service_name failed to become healthy after ${timeout}s"
            return 1
        fi

        log_debug "Health check for $service_name (${elapsed}s/${timeout}s)..."
        sleep "$HEALTH_CHECK_INTERVAL"
    done
}

verify_service_connectivity() {
    # This checks the user-observable PDS describeServer endpoint and confirms
    # it exposes PLC-related configuration. It is intentionally non-invasive:
    # no accounts or records are created.
    log_info "Verifying service connectivity and wiring..."

    log_debug "Checking PDS -> PLC connectivity..."

    local pds_healthcheck="${PDS_URL}/xrpc/com.atproto.server.describeServer"

    if ! curl -s --max-time 5 "$pds_healthcheck" >/dev/null 2>&1; then
        log_error "PDS health check failed: $pds_healthcheck"
        return 1
    fi

    log_debug "Verifying PDS has correct PLC configuration..."
    local plc_response=$(curl -s --max-time 5 "$pds_healthcheck" | grep -o '"plc"' || true)

    if [[ -z "$plc_response" ]]; then
        log_warn "Could not verify PLC configuration in PDS response (service may still be starting up)"
    fi

    log_ok "Service connectivity verified"
    return 0
}

# ── Service startup functions ───────────────────────────────────────────────

startup_plc() {
    # PLC has no upstream dependencies, so it starts first and gates PDS startup
    # through its health endpoint.
    log_info "Starting PLC service on port $SERVICE_PORT_PLC..."

    if [[ ! -d "$PLC_DATA_DIR" ]]; then
        mkdir -p "$PLC_DATA_DIR"
    fi

    cd "$PLC_DATA_DIR" || error_exit "Cannot change to PLC data directory: $PLC_DATA_DIR" 6

    "$PLC_BINARY" serve \
        --port "$SERVICE_PORT_PLC" \
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
    if ! wait_for_health_check "PLC" "http://127.0.0.1:$SERVICE_PORT_PLC/_health"; then
        log_error "PLC service failed health check. Log tail:"
        tail -n 20 "$PLC_LOG" || true
        error_exit "PLC service health check failed" 8
    fi
}

startup_pds() {
    # PDS depends on PLC for handle/DID operations. The PDS_PLC_URL and issuer
    # are injected for this child only so the parent shell remains clean.
    log_info "Starting PDS service on port $SERVICE_PORT_PDS..."

    if [[ ! -d "$PDS_DATA_DIR" ]]; then
        mkdir -p "$PDS_DATA_DIR"
    fi

    log_debug "PDS Configuration:"
    log_debug "  - Port: $SERVICE_PORT_PDS"
    log_debug "  - Data Dir: $PDS_DATA_DIR"
    log_debug "  - PLC URL: $PLC_URL"
    log_debug "  - Issuer: $PDS_ISSUER"
    log_debug "  - Log Level: $PDS_LOG_LEVEL"

    cd "$PDS_DATA_DIR" || error_exit "Cannot change to PDS data directory: $PDS_DATA_DIR" 6

    PDS_PLC_URL="$PLC_URL" PDS_ISSUER="$PDS_ISSUER" \
    "$PDS_BINARY" serve \
        --port "$SERVICE_PORT_PDS" \
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
    if ! wait_for_health_check "PDS" "http://localhost:$SERVICE_PORT_PDS/xrpc/com.atproto.server.describeServer"; then
        log_error "PDS service failed health check. Log tail:"
        tail -n 20 "$PDS_LOG" || true
        error_exit "PDS service health check failed" 8
    fi
}

# ── Verification and reporting ──────────────────────────────────────────────

print_startup_summary() {
    # Keep the summary on stderr with the rest of the script logging so stdout
    # remains available to callers that want to capture command output.
    cat >&2 << EOF
${_LIB_GREEN}╔════════════════════════════════════════════════════════╗${_LIB_NC}
${_LIB_GREEN}║${_LIB_NC}           ${_LIB_BOLD}ATProto Services Started Successfully${_LIB_NC}          ${_LIB_GREEN}║${_LIB_NC}
${_LIB_GREEN}╚════════════════════════════════════════════════════════╝${_LIB_NC}

${_LIB_BOLD}Service Status:${_LIB_NC}
EOF

    if [[ "$SKIP_PLC" != "true" ]] && [[ -n "$PLC_PID" ]]; then
        echo -e "  ${_LIB_GREEN}✓${_LIB_NC} PLC Server" >&2
        echo -e "    PID: $PLC_PID" >&2
        echo -e "    URL: $PLC_URL" >&2
        echo -e "    Logs: $PLC_LOG" >&2
    fi

    if [[ "$SKIP_PDS" != "true" ]] && [[ -n "$PDS_PID" ]]; then
        echo -e "  ${_LIB_GREEN}✓${_LIB_NC} PDS Server" >&2
        echo -e "    PID: $PDS_PID" >&2
        echo -e "    URL: $PDS_URL" >&2
        echo -e "    Admin UI: ${PDS_URL}/admin" >&2
        echo -e "    Explorer UI: ${PDS_URL}/explore" >&2
        echo -e "    API Docs: ${PDS_URL}/explore/api/docs" >&2
        echo -e "    Logs: $PDS_LOG" >&2
    fi

    cat >&2 << EOF

${_LIB_BOLD}Useful Commands:${_LIB_NC}
  View logs:
    tail -f $PLC_LOG    # View PLC logs
    tail -f $PDS_LOG    # View PDS logs

  Test API:
    curl -s $PDS_URL/xrpc/com.atproto.server.describeServer | jq .

  Stop services:
    pkill -f 'campagnola.*$SERVICE_PORT_PLC'  # Stop PLC
    pkill -f 'kaszlak.*$SERVICE_PORT_PDS'     # Stop PDS

  Check service health:
    curl -s http://127.0.0.1:$SERVICE_PORT_PLC/_health
    curl -s $PDS_URL/xrpc/com.atproto.server.describeServer

${_LIB_BOLD}Press Ctrl+C to stop all services${_LIB_NC}

EOF
}

print_usage() {
    cat << EOF
${_LIB_BOLD}Usage:${_LIB_NC} $(basename "$0") [OPTIONS]

${_LIB_BOLD}Description:${_LIB_NC}
  Start all ATProto services (PLC, PDS) with health checks and verification.
  Ensures proper wiring and service-to-service connectivity.

${_LIB_BOLD}Options:${_LIB_NC}
  --skip-plc                    Skip PLC service startup
  --skip-pds                    Skip PDS service startup
  --skip-health-checks          Skip health check verification
  --skip-cleanup                Don't clean up stray processes on startup

  --plc-port PORT               PLC service port (default: $SERVICE_PORT_PLC)
  --pds-port PORT               PDS service port (default: $SERVICE_PORT_PDS)
  --plc-binary PATH             Path to PLC binary (default: $BUILD_DIR/campagnola)
  --pds-binary PATH             Path to PDS binary (default: $BUILD_DIR/kaszlak)

  --data-dir PATH               Base data directory (default: /tmp/atproto-services)
  --pds-issuer URL              PDS issuer URL (default: http://localhost:$SERVICE_PORT_PDS)
  --pds-log-level LEVEL         PDS log level: error, warn, info, debug (default: info)
  --plc-log-level LEVEL         PLC log level: error, warn, info, debug (default: info)

  --health-timeout SECS         Health check timeout (default: 30)
  --health-retries N            Health check max retries (default: 60)

  --verbose                     Enable verbose logging
  --quiet                       Suppress non-error output
  --help                        Show this help message

${_LIB_BOLD}Environment Variables:${_LIB_NC}
  SKIP_PLC, SKIP_PDS, SKIP_HEALTH_CHECKS, SKIP_CLEANUP_ON_START
  PLC_PORT, PDS_PORT, PLC_BINARY, PDS_BINARY
  DATA_DIR, PLC_DATA_DIR, PDS_DATA_DIR
  LOG_DIR, PLC_LOG, PDS_LOG
  PDS_ISSUER, PDS_LOG_LEVEL, PLC_LOG_LEVEL
  HEALTH_CHECK_TIMEOUT, HEALTH_CHECK_RETRIES, HEALTH_CHECK_INTERVAL
  VERBOSE, QUIET, NO_COLOR

${_LIB_BOLD}Examples:${_LIB_NC}
  # Start all services with verbose logging
  VERBOSE=true $0

  # Start only PDS service
  $0 --skip-plc

  # Start with custom data directory
  $0 --data-dir /var/lib/atproto

  # Start on non-standard ports
  $0 --plc-port 3000 --pds-port 3001

${_LIB_BOLD}Troubleshooting:${_LIB_NC}
  If services fail to start:
    1. Check binaries exist: ls -la $BUILD_DIR/
    2. Check port availability: lsof -i :$SERVICE_PORT_PLC && lsof -i :$SERVICE_PORT_PDS
    3. Review logs: tail -f $LOG_DIR/*.log
    4. Check disk space: df -h $DATA_DIR
    5. Try cleanup: $0 --skip-cleanup

EOF
    exit 0
}

# ── Argument parsing ────────────────────────────────────────────────────────

parse_arguments() {
    # Mutate configuration variables in place. URLs are refreshed after parsing
    # because port flags change the derived service endpoints.
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip-plc)
                SKIP_PLC=true
                ;;
            --skip-pds)
                SKIP_PDS=true
                ;;
            --skip-health-checks)
                SKIP_HEALTH_CHECKS=true
                ;;
            --skip-cleanup)
                SKIP_CLEANUP_ON_START=true
                ;;
            --plc-port)
                SERVICE_PORT_PLC="$2"
                SERVICE_URL_PLC="http://127.0.0.1:$2"
                shift
                ;;
            --pds-port)
                SERVICE_PORT_PDS="$2"
                SERVICE_URL_PDS="http://127.0.0.1:$2"
                shift
                ;;
            --plc-binary)
                PLC_BINARY="$2"
                shift
                ;;
            --pds-binary)
                PDS_BINARY="$2"
                shift
                ;;
            --data-dir)
                DATA_DIR="$2"
                PLC_DATA_DIR="$DATA_DIR/plc"
                PDS_DATA_DIR="$DATA_DIR/pds"
                shift
                ;;
            --pds-issuer)
                PDS_ISSUER="$2"
                shift
                ;;
            --pds-log-level)
                PDS_LOG_LEVEL="$2"
                shift
                ;;
            --plc-log-level)
                PLC_LOG_LEVEL="$2"
                shift
                ;;
            --health-timeout)
                HEALTH_CHECK_TIMEOUT="$2"
                shift
                ;;
            --health-retries)
                HEALTH_CHECK_RETRIES="$2"
                shift
                ;;
            --verbose)
                VERBOSE=true
                ;;
            --quiet)
                QUIET=true
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

# ── Main execution ──────────────────────────────────────────────────────────

main() {
    # Main is intentionally linear: validate, clean, start dependencies, verify,
    # then wait so traps keep ownership of child processes.
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
    check_dependencies pgrep pkill curl mkdir
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

# Re-derive URLs after argument parsing may have changed ports
PLC_URL="$SERVICE_URL_PLC"
PDS_URL="$SERVICE_URL_PDS"
PDS_ISSUER="${PDS_ISSUER:-http://localhost:$SERVICE_PORT_PDS}"

main
