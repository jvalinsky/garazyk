#!/usr/bin/env bash
#
# Name: services-control.sh
# Description: Service management utilities - stop, restart, status, logs
# Version: 1.0.0
# Usage: ./services-control.sh <command> [options]
#
# This companion to start-all-services.sh is deliberately read-mostly: status,
# logs, follow, and test commands inspect the current local PLC/PDS pair, while
# stop/restart/clean act only on the known local service ports and PID files.
#

set -euo pipefail

################################################################################
# Configuration
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

source "$SCRIPT_DIR/lib/common.sh"

PROJECT_ROOT="$(resolve_project_root "$SCRIPT_DIR")"
readonly PROJECT_ROOT

# Log files and PID files
LOG_DIR="${LOG_DIR:-$PROJECT_ROOT/logs}"
readonly LOG_DIR
PLC_LOG="${PLC_LOG:-$LOG_DIR/plc.log}"
readonly PLC_LOG
PDS_LOG="${PDS_LOG:-$LOG_DIR/pds.log}"
readonly PDS_LOG
PLC_PID_FILE="${PLC_PID_FILE:-$PROJECT_ROOT/.plc.pid}"
readonly PLC_PID_FILE
PDS_PID_FILE="${PDS_PID_FILE:-$PROJECT_ROOT/.pds.pid}"
readonly PDS_PID_FILE

# Binary paths (for restart)
BUILD_DIR="$(resolve_build_dir "$PROJECT_ROOT")"
readonly BUILD_DIR
PLC_BINARY="${PLC_BINARY:-$BUILD_DIR/$SERVICE_BINARY_PLC}"
readonly PLC_BINARY
PDS_BINARY="${PDS_BINARY:-$BUILD_DIR/$SERVICE_BINARY_PDS}"
readonly PDS_BINARY

# Data directories (for restart)
DATA_DIR="${DATA_DIR:-/tmp/atproto-services}"
PLC_DATA_DIR="${PLC_DATA_DIR:-$DATA_DIR/plc}"
PDS_DATA_DIR="${PDS_DATA_DIR:-$DATA_DIR/pds}"

# Service configuration (for restart)
PDS_ISSUER="${PDS_ISSUER:-http://localhost:$SERVICE_PORT_PDS}"
PDS_LOG_LEVEL="${PDS_LOG_LEVEL:-info}"

################################################################################
# Service utilities
################################################################################

get_plc_pid() {
    # Prefer the PID file written by start-all-services.sh. If it is missing,
    # fall back to a binary+port search so manually started local services can
    # still be inspected and stopped.
    if [[ -f "$PLC_PID_FILE" ]]; then
        local pid
        pid=$(cat "$PLC_PID_FILE" 2>/dev/null || true)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return 0
        fi
    fi

    # Try to find via process search
    local pid
    pid=$(pgrep -f "$SERVICE_BINARY_PLC.*$SERVICE_PORT_PLC" | head -1 || true)
    if [[ -n "$pid" ]]; then
        echo "$pid"
        return 0
    fi

    return 1
}

get_pds_pid() {
    # Mirror get_plc_pid for the PDS. PID-file validation prevents stale files
    # from reporting a service as running.
    if [[ -f "$PDS_PID_FILE" ]]; then
        local pid
        pid=$(cat "$PDS_PID_FILE" 2>/dev/null || true)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return 0
        fi
    fi

    # Try to find via process search
    local pid
    pid=$(pgrep -f "$SERVICE_BINARY_PDS.*$SERVICE_PORT_PDS" | head -1 || true)
    if [[ -n "$pid" ]]; then
        echo "$pid"
        return 0
    fi

    return 1
}

is_plc_running() {
    get_plc_pid >/dev/null 2>&1
}

is_pds_running() {
    get_pds_pid >/dev/null 2>&1
}

is_plc_healthy() {
    # Short timeouts keep status/test commands responsive when a process exists
    # but has not finished startup or is wedged.
    local timeout="${1:-2}"
    wait_for_http "$SERVICE_URL_PLC/_health" "PLC" "$timeout" >/dev/null 2>&1
}

is_pds_healthy() {
    # describeServer is the useful PDS readiness check for local XRPC callers.
    local timeout="${1:-2}"
    wait_for_http "$SERVICE_URL_PDS/xrpc/com.atproto.server.describeServer" "PDS" "$timeout" >/dev/null 2>&1
}

################################################################################
# Commands
################################################################################

cmd_status() {
    # Produce a human-readable report that combines process presence, health
    # checks, public URLs, and log availability.
    log_info "Service Status Report"
    echo "" >&2

    # PLC status
    echo -e "${_LIB_BOLD}PLC Service (port $SERVICE_PORT_PLC)${_LIB_NC}:" >&2
    if is_plc_running; then
        local pid
        pid=$(get_plc_pid)
        echo -e "  Status: ${_LIB_GREEN}Running${_LIB_NC}" >&2
        echo -e "  PID: $pid" >&2
        echo -e "  URL: $SERVICE_URL_PLC" >&2

        if is_plc_healthy 2; then
            echo -e "  Health: ${_LIB_GREEN}Healthy${_LIB_NC}" >&2
        else
            echo -e "  Health: ${_LIB_YELLOW}Unhealthy${_LIB_NC}" >&2
        fi
    else
        echo -e "  Status: ${_LIB_RED}Not running${_LIB_NC}" >&2
    fi
    echo "" >&2

    # PDS status
    echo -e "${_LIB_BOLD}PDS Service (port $SERVICE_PORT_PDS)${_LIB_NC}:" >&2
    if is_pds_running; then
        local pid
        pid=$(get_pds_pid)
        echo -e "  Status: ${_LIB_GREEN}Running${_LIB_NC}" >&2
        echo -e "  PID: $pid" >&2
        echo -e "  URL: $SERVICE_URL_PDS" >&2
        echo -e "  Admin UI: $SERVICE_URL_PDS/admin" >&2
        echo -e "  Explorer UI: $SERVICE_URL_PDS/explore" >&2

        if is_pds_healthy 2; then
            echo -e "  Health: ${_LIB_GREEN}Healthy${_LIB_NC}" >&2
        else
            echo -e "  Health: ${_LIB_YELLOW}Unhealthy${_LIB_NC}" >&2
        fi
    else
        echo -e "  Status: ${_LIB_RED}Not running${_LIB_NC}" >&2
    fi
    echo "" >&2

    # Log files
    echo -e "${_LIB_BOLD}Log Files${_LIB_NC}:" >&2
    if [[ -f "$PLC_LOG" ]]; then
        local size
        size=$(du -h "$PLC_LOG" | awk '{print $1}')
        echo -e "  PLC: $PLC_LOG ($size)" >&2
    else
        echo -e "  PLC: ${_LIB_YELLOW}No log file${_LIB_NC}" >&2
    fi

    if [[ -f "$PDS_LOG" ]]; then
        local size
        size=$(du -h "$PDS_LOG" | awk '{print $1}')
        echo -e "  PDS: $PDS_LOG ($size)" >&2
    else
        echo -e "  PDS: ${_LIB_YELLOW}No log file${_LIB_NC}" >&2
    fi
}

cmd_stop() {
    # Stop targets by resolved PID rather than broad pkill. The clean command
    # performs wider stale-process cleanup when needed.
    local target="${1:-all}"

    case "$target" in
        plc)
            if is_plc_running; then
                local pid
                pid=$(get_plc_pid)
                log_info "Stopping PLC service (PID: $pid)..."
                if kill "$pid" 2>/dev/null; then
                    log_ok "PLC service stopped"
                    rm -f "$PLC_PID_FILE"
                else
                    log_error "Failed to stop PLC service"
                    return 1
                fi
            else
                log_warn "PLC service not running"
            fi
            ;;
        pds)
            if is_pds_running; then
                local pid
                pid=$(get_pds_pid)
                log_info "Stopping PDS service (PID: $pid)..."
                if kill "$pid" 2>/dev/null; then
                    log_ok "PDS service stopped"
                    rm -f "$PDS_PID_FILE"
                else
                    log_error "Failed to stop PDS service"
                    return 1
                fi
            else
                log_warn "PDS service not running"
            fi
            ;;
        all)
            if is_plc_running; then
                local pid
                pid=$(get_plc_pid)
                log_info "Stopping PLC service (PID: $pid)..."
                if kill "$pid" 2>/dev/null; then
                    log_ok "PLC service stopped"
                    rm -f "$PLC_PID_FILE"
                else
                    log_error "Failed to stop PLC service"
                    return 1
                fi
            else
                log_warn "PLC service not running"
            fi

            if is_pds_running; then
                local pid
                pid=$(get_pds_pid)
                log_info "Stopping PDS service (PID: $pid)..."
                if kill "$pid" 2>/dev/null; then
                    log_ok "PDS service stopped"
                    rm -f "$PDS_PID_FILE"
                else
                    log_error "Failed to stop PDS service"
                    return 1
                fi
            else
                log_warn "PDS service not running"
            fi
            ;;
        *)
            log_error "Unknown service: $target"
            return 1
            ;;
    esac

    return 0
}

cmd_restart() {
    # Restart services by stopping them and starting them directly (not via
    # start-all-services.sh, which blocks on `wait` and is unsuitable for
    # scripted restarts).  Health checks confirm readiness before returning.
    local target="${1:-all}"

    cmd_stop "$target" || return 1

    sleep 2

    log_info "Restarting services..."

    case "$target" in
        plc)
            if [[ ! -f "$PLC_BINARY" ]]; then
                log_error "PLC binary not found: $PLC_BINARY"
                return 1
            fi
            mkdir -p "$PLC_DATA_DIR"
            cd "$PLC_DATA_DIR" || { log_error "Cannot cd to $PLC_DATA_DIR"; return 1; }
            "$PLC_BINARY" serve --port "$SERVICE_PORT_PLC" \
                >> "$PLC_LOG" 2>&1 &
            local pid=$!
            echo "$pid" > "$PLC_PID_FILE"
            log_info "PLC restarted (PID: $pid)"
            wait_for_http "$SERVICE_URL_PLC/_health" "PLC" 30
            ;;
        pds)
            if [[ ! -f "$PDS_BINARY" ]]; then
                log_error "PDS binary not found: $PDS_BINARY"
                return 1
            fi
            mkdir -p "$PDS_DATA_DIR"
            cd "$PDS_DATA_DIR" || { log_error "Cannot cd to $PDS_DATA_DIR"; return 1; }
            PDS_PLC_URL="$SERVICE_URL_PLC" PDS_ISSUER="$PDS_ISSUER" \
            "$PDS_BINARY" serve --port "$SERVICE_PORT_PDS" \
                --data-dir "$PDS_DATA_DIR" --log-level "$PDS_LOG_LEVEL" \
                >> "$PDS_LOG" 2>&1 &
            local pid=$!
            echo "$pid" > "$PDS_PID_FILE"
            log_info "PDS restarted (PID: $pid)"
            wait_for_http "$SERVICE_URL_PDS/xrpc/com.atproto.server.describeServer" "PDS" 30
            ;;
        all)
            cmd_restart plc
            sleep 2
            cmd_restart pds
            ;;
        *)
            log_error "Unknown service: $target"
            return 1
            ;;
    esac
}

cmd_logs() {
    # Print bounded log tails by default; callers can request a larger line
    # count without opening a following tail session.
    local service="${1:-all}"
    local lines="${2:-50}"

    case "$service" in
        plc)
            if [[ -f "$PLC_LOG" ]]; then
                echo -e "${_LIB_BOLD}PLC Logs (last $lines lines)${_LIB_NC}:" >&2
                tail -n "$lines" "$PLC_LOG"
            else
                log_error "PLC log file not found: $PLC_LOG"
                return 1
            fi
            ;;
        pds)
            if [[ -f "$PDS_LOG" ]]; then
                echo -e "${_LIB_BOLD}PDS Logs (last $lines lines)${_LIB_NC}:" >&2
                tail -n "$lines" "$PDS_LOG"
            else
                log_error "PDS log file not found: $PDS_LOG"
                return 1
            fi
            ;;
        all)
            if [[ -f "$PLC_LOG" ]]; then
                echo -e "${_LIB_BOLD}PLC Logs (last $lines lines)${_LIB_NC}:" >&2
                tail -n "$lines" "$PLC_LOG"
                echo ""
            fi

            if [[ -f "$PDS_LOG" ]]; then
                echo -e "${_LIB_BOLD}PDS Logs (last $lines lines)${_LIB_NC}:" >&2
                tail -n "$lines" "$PDS_LOG"
            fi
            ;;
        *)
            log_error "Unknown service: $service"
            return 1
            ;;
    esac
}

cmd_logs_follow() {
    # Long-running follow mode intentionally lets tail own the foreground until
    # the user interrupts it.
    local service="${1:-all}"

    case "$service" in
        plc)
            if [[ -f "$PLC_LOG" ]]; then
                log_info "Following PLC logs (Ctrl+C to stop)..."
                tail -f "$PLC_LOG"
            else
                log_error "PLC log file not found: $PLC_LOG"
                return 1
            fi
            ;;
        pds)
            if [[ -f "$PDS_LOG" ]]; then
                log_info "Following PDS logs (Ctrl+C to stop)..."
                tail -f "$PDS_LOG"
            else
                log_error "PDS log file not found: $PDS_LOG"
                return 1
            fi
            ;;
        all)
            log_info "Following all service logs (Ctrl+C to stop)..."

            if [[ ! -f "$PLC_LOG" ]] || [[ ! -f "$PDS_LOG" ]]; then
                log_error "One or more log files not found"
                return 1
            fi

            tail -f "$PLC_LOG" "$PDS_LOG"
            ;;
        *)
            log_error "Unknown service: $service"
            return 1
            ;;
    esac
}

cmd_test() {
    # Run non-mutating checks against the running local services. These tests
    # verify reachability and basic configuration without creating accounts.
    log_info "Running connectivity tests..."
    echo "" >&2

    local failed=0

    # Test PLC health
    echo -e "${_LIB_BOLD}PLC Health Check${_LIB_NC}:" >&2
    if is_plc_healthy 5; then
        log_ok "PLC is responding"
    else
        log_error "PLC is not responding to health check"
        failed=$((failed + 1))
    fi
    echo "" >&2

    # Test PDS health
    echo -e "${_LIB_BOLD}PDS Health Check${_LIB_NC}:" >&2
    if is_pds_healthy 5; then
        log_ok "PDS is responding to describeServer"
    else
        log_error "PDS is not responding to describeServer"
        failed=$((failed + 1))
    fi
    echo "" >&2

    # Test service configuration
    echo -e "${_LIB_BOLD}PDS Configuration${_LIB_NC}:" >&2
    local describe
    describe=$(curl -s --max-time 5 "$SERVICE_URL_PDS/xrpc/com.atproto.server.describeServer" || echo "{}")

    if echo "$describe" | grep -q "issuer"; then
        echo -e "  Issuer: $(echo "$describe" | grep -o '"issuer":"[^"]*' | cut -d'"' -f4)" >&2
        log_ok "PDS configuration valid"
    else
        log_warn "Could not parse PDS configuration"
    fi
    echo "" >&2

    # Test Admin UI availability
    echo -e "${_LIB_BOLD}Admin UI Availability${_LIB_NC}:" >&2
    if curl -s --max-time 5 -I "$SERVICE_URL_PDS/admin" 2>/dev/null | head -1 | grep -q "200\|301\|302"; then
        log_ok "Admin UI is accessible"
    else
        log_warn "Admin UI may not be accessible"
    fi
    echo "" >&2

    # Test Explorer UI availability
    echo -e "${_LIB_BOLD}Explorer UI Availability${_LIB_NC}:" >&2
    if curl -s --max-time 5 -I "$SERVICE_URL_PDS/explore" 2>/dev/null | head -1 | grep -q "200\|301\|302"; then
        log_ok "Explorer UI is accessible"
    else
        log_warn "Explorer UI may not be accessible"
    fi
    echo "" >&2

    if [[ $failed -gt 0 ]]; then
        log_error "Some tests failed ($failed failures)"
        return 1
    fi

    log_ok "All tests passed"
    return 0
}

cmd_clean() {
    # Clean is the broadest command: stop known services, remove stale PID files,
    # then use common.sh to clear remaining local listeners on the shared ports.
    log_info "Cleaning up..."

    # Stop services
    cmd_stop "all" 2>/dev/null || true

    # Clear PID files
    rm -f "$PLC_PID_FILE" "$PDS_PID_FILE"
    log_debug "Removed PID files"

    # Clear stray processes
    kill_stray_processes plc pds
    log_debug "Cleaned up stray processes"

    log_ok "Cleanup complete"
}

cmd_help() {
    cat << EOF
${_LIB_BOLD}Service Control Tool${_LIB_NC}

${_LIB_BOLD}Usage:${_LIB_NC} $(basename "$0") <command> [options]

${_LIB_BOLD}Commands:${_LIB_NC}

  ${_LIB_BOLD}status${_LIB_NC}
    Show status of all services
    Usage: $(basename "$0") status

  ${_LIB_BOLD}stop [service]${_LIB_NC}
    Stop services (plc, pds, or all)
    Usage: $(basename "$0") stop [plc|pds|all]
    Example: $(basename "$0") stop pds

  ${_LIB_BOLD}restart [service]${_LIB_NC}
    Restart services (plc, pds, or all)
    Usage: $(basename "$0") restart [plc|pds|all]
    Example: $(basename "$0") restart

  ${_LIB_BOLD}logs [service] [lines]${_LIB_NC}
    View service logs (default: last 50 lines)
    Usage: $(basename "$0") logs [plc|pds|all] [lines]
    Example: $(basename "$0") logs pds 100

  ${_LIB_BOLD}follow [service]${_LIB_NC}
    Follow service logs in real-time
    Usage: $(basename "$0") follow [plc|pds|all]
    Example: $(basename "$0") follow all

  ${_LIB_BOLD}test${_LIB_NC}
    Run connectivity and health tests
    Usage: $(basename "$0") test

  ${_LIB_BOLD}clean${_LIB_NC}
    Stop all services and clean up
    Usage: $(basename "$0") clean

  ${_LIB_BOLD}help${_LIB_NC}
    Show this help message
    Usage: $(basename "$0") help

${_LIB_BOLD}Environment Variables:${_LIB_NC}
  PLC_PORT (default: $SERVICE_PORT_PLC)
  PDS_PORT (default: $SERVICE_PORT_PDS)
  LOG_DIR (default: \$PROJECT_ROOT/logs)
  VERBOSE (true|false, default: false)

${_LIB_BOLD}Examples:${_LIB_NC}
  # Check service status
  $(basename "$0") status

  # View PDS logs in real-time
  $(basename "$0") follow pds

  # Run connectivity tests
  $(basename "$0") test

  # Restart PDS after debugging
  $(basename "$0") restart pds

${_LIB_BOLD}URLs:${_LIB_NC}
  PLC: $SERVICE_URL_PLC
  PDS: $SERVICE_URL_PDS
  Admin UI: $SERVICE_URL_PDS/admin
  Explorer UI: $SERVICE_URL_PDS/explore

EOF
}

################################################################################
# Main
################################################################################

main() {
    # Keep command dispatch simple and explicit so unknown commands fail before
    # any service-control side effects happen.
    local command="${1:-help}"

    case "$command" in
        status)
            cmd_status
            ;;
        stop)
            cmd_stop "${2:-all}"
            ;;
        restart)
            cmd_restart "${2:-all}"
            ;;
        logs)
            cmd_logs "${2:-all}" "${3:-50}"
            ;;
        follow)
            cmd_logs_follow "${2:-all}"
            ;;
        test)
            cmd_test
            ;;
        clean)
            cmd_clean
            ;;
        help|--help|-h)
            cmd_help
            ;;
        *)
            log_error "Unknown command: $command"
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
