#!/usr/bin/env bash
#
# Name: services-control.sh
# Description: Service management utilities - stop, restart, status, logs
# Version: 1.0.0
# Usage: ./services-control.sh <command> [options]
#

set -euo pipefail

################################################################################
# Configuration
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_ROOT/../.." && pwd))"
readonly PROJECT_ROOT

# Ports and process identifiers
PLC_PORT="${PLC_PORT:-2582}"
readonly PLC_PORT
PDS_PORT="${PDS_PORT:-2583}"
readonly PDS_PORT

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

# URLs
PLC_URL="${PLC_URL:-http://127.0.0.1:$PLC_PORT}"
readonly PLC_URL
PDS_URL="${PDS_URL:-http://localhost:$PDS_PORT}"
readonly PDS_URL

# Logging configuration
VERBOSE="${VERBOSE:-false}"
readonly VERBOSE

################################################################################
# Color definitions
################################################################################

if [[ -t 1 ]] && [[ "${NO_COLOR:-false}" != "true" ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly CYAN='\033[0;36m'
    readonly BOLD='\033[1m'
    readonly NC='\033[0m'
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly CYAN=''
    readonly BOLD=''
    readonly NC=''
fi

################################################################################
# Logging functions
################################################################################

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $1" >&2
    fi
}

log_info() {
    echo -e "${CYAN}[INFO]${NC}  $1" >&2
}

log_success() {
    echo -e "${GREEN}[OK]${NC}    $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC}  $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

################################################################################
# Service utilities
################################################################################

get_plc_pid() {
    if [[ -f "$PLC_PID_FILE" ]]; then
        local pid=$(cat "$PLC_PID_FILE" 2>/dev/null || true)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return 0
        fi
    fi

    # Try to find via process search
    local pid=$(pgrep -f "campagnola.*$PLC_PORT" | head -1 || true)
    if [[ -n "$pid" ]]; then
        echo "$pid"
        return 0
    fi

    return 1
}

get_pds_pid() {
    if [[ -f "$PDS_PID_FILE" ]]; then
        local pid=$(cat "$PDS_PID_FILE" 2>/dev/null || true)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return 0
        fi
    fi

    # Try to find via process search
    local pid=$(pgrep -f "kaszlak.*$PDS_PORT" | head -1 || true)
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
    curl -s --max-time 2 "$PLC_URL/_health" >/dev/null 2>&1
}

is_pds_healthy() {
    curl -s --max-time 2 "$PDS_URL/xrpc/com.atproto.server.describeServer" >/dev/null 2>&1
}

################################################################################
# Commands
################################################################################

cmd_status() {
    log_info "Service Status Report"
    echo "" >&2

    # PLC status
    echo -e "${BOLD}PLC Service (port $PLC_PORT)${NC}:" >&2
    if is_plc_running; then
        local pid=$(get_plc_pid)
        echo -e "  Status: ${GREEN}Running${NC}" >&2
        echo -e "  PID: $pid" >&2
        echo -e "  URL: $PLC_URL" >&2

        if is_plc_healthy; then
            echo -e "  Health: ${GREEN}Healthy${NC}" >&2
        else
            echo -e "  Health: ${YELLOW}Unhealthy${NC}" >&2
        fi
    else
        echo -e "  Status: ${RED}Not running${NC}" >&2
    fi
    echo "" >&2

    # PDS status
    echo -e "${BOLD}PDS Service (port $PDS_PORT)${NC}:" >&2
    if is_pds_running; then
        local pid=$(get_pds_pid)
        echo -e "  Status: ${GREEN}Running${NC}" >&2
        echo -e "  PID: $pid" >&2
        echo -e "  URL: $PDS_URL" >&2
        echo -e "  Admin UI: $PDS_URL/admin" >&2
        echo -e "  Explorer UI: $PDS_URL/explore" >&2

        if is_pds_healthy; then
            echo -e "  Health: ${GREEN}Healthy${NC}" >&2
        else
            echo -e "  Health: ${YELLOW}Unhealthy${NC}" >&2
        fi
    else
        echo -e "  Status: ${RED}Not running${NC}" >&2
    fi
    echo "" >&2

    # Log files
    echo -e "${BOLD}Log Files${NC}:" >&2
    if [[ -f "$PLC_LOG" ]]; then
        local size=$(du -h "$PLC_LOG" | awk '{print $1}')
        echo -e "  PLC: $PLC_LOG ($size)" >&2
    else
        echo -e "  PLC: ${YELLOW}No log file${NC}" >&2
    fi

    if [[ -f "$PDS_LOG" ]]; then
        local size=$(du -h "$PDS_LOG" | awk '{print $1}')
        echo -e "  PDS: $PDS_LOG ($size)" >&2
    else
        echo -e "  PDS: ${YELLOW}No log file${NC}" >&2
    fi
}

cmd_stop() {
    local target="${1:-all}"

    case "$target" in
        plc)
            if is_plc_running; then
                local pid=$(get_plc_pid)
                log_info "Stopping PLC service (PID: $pid)..."
                if kill "$pid" 2>/dev/null; then
                    log_success "PLC service stopped"
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
                local pid=$(get_pds_pid)
                log_info "Stopping PDS service (PID: $pid)..."
                if kill "$pid" 2>/dev/null; then
                    log_success "PDS service stopped"
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
                local pid=$(get_plc_pid)
                log_info "Stopping PLC service (PID: $pid)..."
                if kill "$pid" 2>/dev/null; then
                    log_success "PLC service stopped"
                    rm -f "$PLC_PID_FILE"
                else
                    log_error "Failed to stop PLC service"
                    return 1
                fi
            else
                log_warn "PLC service not running"
            fi

            if is_pds_running; then
                local pid=$(get_pds_pid)
                log_info "Stopping PDS service (PID: $pid)..."
                if kill "$pid" 2>/dev/null; then
                    log_success "PDS service stopped"
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
    local target="${1:-all}"

    cmd_stop "$target" || return 1

    sleep 2

    log_info "Restarting services..."

    case "$target" in
        plc)
            "$SCRIPT_DIR/start-all-services.sh" --skip-pds
            ;;
        pds)
            "$SCRIPT_DIR/start-all-services.sh" --skip-plc
            ;;
        all)
            "$SCRIPT_DIR/start-all-services.sh"
            ;;
    esac
}

cmd_logs() {
    local service="${1:-all}"
    local lines="${2:-50}"

    case "$service" in
        plc)
            if [[ -f "$PLC_LOG" ]]; then
                echo -e "${BOLD}PLC Logs (last $lines lines)${NC}:" >&2
                tail -n "$lines" "$PLC_LOG"
            else
                log_error "PLC log file not found: $PLC_LOG"
                return 1
            fi
            ;;
        pds)
            if [[ -f "$PDS_LOG" ]]; then
                echo -e "${BOLD}PDS Logs (last $lines lines)${NC}:" >&2
                tail -n "$lines" "$PDS_LOG"
            else
                log_error "PDS log file not found: $PDS_LOG"
                return 1
            fi
            ;;
        all)
            if [[ -f "$PLC_LOG" ]]; then
                echo -e "${BOLD}PLC Logs (last $lines lines)${NC}:" >&2
                tail -n "$lines" "$PLC_LOG"
                echo ""
            fi

            if [[ -f "$PDS_LOG" ]]; then
                echo -e "${BOLD}PDS Logs (last $lines lines)${NC}:" >&2
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
    log_info "Running connectivity tests..."
    echo "" >&2

    local failed=0

    # Test PLC health
    echo -e "${BOLD}PLC Health Check${NC}:" >&2
    if curl -s --max-time 5 "$PLC_URL/_health" >/dev/null 2>&1; then
        log_success "PLC is responding"
    else
        log_error "PLC is not responding to health check"
        failed=$((failed + 1))
    fi
    echo "" >&2

    # Test PDS health
    echo -e "${BOLD}PDS Health Check${NC}:" >&2
    if curl -s --max-time 5 "$PDS_URL/xrpc/com.atproto.server.describeServer" >/dev/null 2>&1; then
        log_success "PDS is responding to describeServer"
    else
        log_error "PDS is not responding to describeServer"
        failed=$((failed + 1))
    fi
    echo "" >&2

    # Test service configuration
    echo -e "${BOLD}PDS Configuration${NC}:" >&2
    local describe=$(curl -s --max-time 5 "$PDS_URL/xrpc/com.atproto.server.describeServer" || echo "{}")

    if echo "$describe" | grep -q "issuer"; then
        echo -e "  Issuer: $(echo "$describe" | grep -o '"issuer":"[^"]*' | cut -d'"' -f4)" >&2
        log_success "PDS configuration valid"
    else
        log_warn "Could not parse PDS configuration"
    fi
    echo "" >&2

    # Test Admin UI availability
    echo -e "${BOLD}Admin UI Availability${NC}:" >&2
    if curl -s --max-time 5 -I "$PDS_URL/admin" 2>/dev/null | head -1 | grep -q "200\|301\|302"; then
        log_success "Admin UI is accessible"
    else
        log_warn "Admin UI may not be accessible"
    fi
    echo "" >&2

    # Test Explorer UI availability
    echo -e "${BOLD}Explorer UI Availability${NC}:" >&2
    if curl -s --max-time 5 -I "$PDS_URL/explore" 2>/dev/null | head -1 | grep -q "200\|301\|302"; then
        log_success "Explorer UI is accessible"
    else
        log_warn "Explorer UI may not be accessible"
    fi
    echo "" >&2

    if [[ $failed -gt 0 ]]; then
        log_error "Some tests failed ($failed failures)"
        return 1
    fi

    log_success "All tests passed"
    return 0
}

cmd_clean() {
    log_info "Cleaning up..."

    # Stop services
    cmd_stop "all" 2>/dev/null || true

    # Clear PID files
    rm -f "$PLC_PID_FILE" "$PDS_PID_FILE"
    log_debug "Removed PID files"

    # Clear stray processes
    pkill -f "campagnola.*$PLC_PORT" 2>/dev/null || true
    pkill -f "kaszlak.*$PDS_PORT" 2>/dev/null || true
    log_debug "Cleaned up stray processes"

    log_success "Cleanup complete"
}

cmd_help() {
    cat << EOF
${BOLD}Service Control Tool${NC}

${BOLD}Usage:${NC} $(basename "$0") <command> [options]

${BOLD}Commands:${NC}

  ${BOLD}status${NC}
    Show status of all services
    Usage: $(basename "$0") status

  ${BOLD}stop [service]${NC}
    Stop services (plc, pds, or all)
    Usage: $(basename "$0") stop [plc|pds|all]
    Example: $(basename "$0") stop pds

  ${BOLD}restart [service]${NC}
    Restart services (plc, pds, or all)
    Usage: $(basename "$0") restart [plc|pds|all]
    Example: $(basename "$0") restart

  ${BOLD}logs [service] [lines]${NC}
    View service logs (default: last 50 lines)
    Usage: $(basename "$0") logs [plc|pds|all] [lines]
    Example: $(basename "$0") logs pds 100

  ${BOLD}follow [service]${NC}
    Follow service logs in real-time
    Usage: $(basename "$0") follow [plc|pds|all]
    Example: $(basename "$0") follow all

  ${BOLD}test${NC}
    Run connectivity and health tests
    Usage: $(basename "$0") test

  ${BOLD}clean${NC}
    Stop all services and clean up
    Usage: $(basename "$0") clean

  ${BOLD}help${NC}
    Show this help message
    Usage: $(basename "$0") help

${BOLD}Environment Variables:${NC}
  PLC_PORT (default: 2582)
  PDS_PORT (default: 2583)
  LOG_DIR (default: \$PROJECT_ROOT/logs)
  VERBOSE (true|false, default: false)

${BOLD}Examples:${NC}
  # Check service status
  $(basename "$0") status

  # View PDS logs in real-time
  $(basename "$0") follow pds

  # Run connectivity tests
  $(basename "$0") test

  # Restart PDS after debugging
  $(basename "$0") restart pds

${BOLD}URLs:${NC}
  PLC: http://127.0.0.1:2582
  PDS: http://localhost:2583
  Admin UI: http://localhost:2583/admin
  Explorer UI: http://localhost:2583/explore

EOF
}

################################################################################
# Main
################################################################################

main() {
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
