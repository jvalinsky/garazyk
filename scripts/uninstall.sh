#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This operation requires root privileges."
        log_info "Run with sudo: sudo $0 $@"
        exit 1
    fi
}

stop_services() {
    log_info "Stopping services..."

    launchctl unload /Library/LaunchDaemons/com.atproto.pds.plist 2>/dev/null && log_info "Stopped LaunchDaemon" || log_warn "Daemon not loaded or already stopped"
    launchctl unload ~/Library/LaunchAgents/com.atproto.pds.user.plist 2>/dev/null && log_info "Stopped LaunchAgent" || log_warn "Agent not loaded or already stopped"

    launchctl stop com.atproto.pds 2>/dev/null || true
}

remove_launchd() {
    log_info "Removing launchd configuration..."

    rm -f /Library/LaunchDaemons/com.atproto.pds.plist && log_info "Removed LaunchDaemon plist" || log_warn "Daemon plist not found"
    rm -f ~/Library/LaunchAgents/com.atproto.pds.user.plist && log_info "Removed LaunchAgent plist" || log_warn "Agent plist not found"
}

remove_binary() {
    log_info "Removing binary..."

    rm -f /usr/local/bin/september && log_info "Removed binary" || log_warn "Binary not found at /usr/local/bin/september"
}

remove_data() {
    log_info "Removing data directory..."

    if [[ "${REMOVE_DATA:-false}" == "true" ]]; then
        rm -rf /var/db/september && log_info "Removed data directory" || log_warn "Data directory not found"
    else
        log_info "Skipped data removal (use --purge to remove)"
    fi
}

remove_config() {
    log_info "Removing configuration..."

    if [[ "${REMOVE_CONFIG:-false}" == "true" ]]; then
        rm -rf /usr/local/etc/september && log_info "Removed configuration" || log_warn "Config directory not found"
    else
        log_info "Skipped config removal (use --purge to remove)")
    fi
}

remove_user() {
    log_info "Removing system user..."

    if [[ "${REMOVE_USER:-true}" == "true" ]]; then
        if id "_pds" &> /dev/null; then
            dscl . -delete "/Users/_pds" && log_info "Removed user '_pds'" || log_warn "Failed to remove user"
        fi
        if dscl . -read "/Groups/_pds" &> /dev/null; then
            dscl . -delete "/Groups/_pds" && log_info "Removed group '_pds'" || log_warn "Failed to remove group"
        fi
    else
        log_info "Skipped user removal (use --remove-user to remove)")
    fi
}

print_summary() {
    echo ""
    echo "============================================"
    echo -e "${GREEN}Uninstallation Complete${NC}"
    echo "============================================"
    echo ""
    echo "Removed:"
    echo "  - Services stopped and unloaded"
    echo "  - LaunchDaemons plists removed"
    echo "  - LaunchAgents plists removed"
    if [[ "${REMOVE_DATA:-false}" == "true" ]]; then
        echo "  - Data directory removed"
    else
        echo "  - Data directory preserved (${DATA_DIR:-/var/db/september})"
    fi
    echo ""
    echo "To complete removal:"
    echo "  rm -rf ${DATA_DIR:-/var/db/september}  # Remove data directory"
    echo "============================================"
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Uninstall ATProto PDS from macOS.

OPTIONS:
    --purge         Remove data directory and configuration
    --keep-user     Don't remove the _pds system user
    --help          Show this help

EXAMPLES:
    $0                          # Remove service, keep data
    sudo $0 --purge             # Remove everything
    sudo $0 --keep-user         # Remove service, keep user account

EOF
    exit 0
}

main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --purge)
                REMOVE_DATA="true"
                REMOVE_CONFIG="true"
                shift
                ;;
            --keep-user)
                REMOVE_USER="false"
                shift
                ;;
            --help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done

    echo "ATProto PDS Uninstaller"
    echo "======================="

    check_root
    stop_services
    remove_launchd
    remove_binary
    remove_data
    remove_config
    remove_user
    print_summary
}

main "$@"
