#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/scenarios/setup_local_network.sh"

usage() {
    cat <<USAGE
Usage: $0 {start|stop|restart|status|logs|diagnostics} [--run-id ID] [--pds2]

This wrapper now delegates lifecycle management to scripts/scenarios/setup_local_network.sh
so Docker projects, cleanup, and diagnostics use the shared ATProto e2e harness.
USAGE
}

cmd="${1:-start}"
if [[ $# -gt 0 ]]; then
    shift
fi

case "$cmd" in
    start)
        exec "$SETUP_SCRIPT" --keep-running "$@"
        ;;
    stop)
        exec "$SETUP_SCRIPT" --teardown "$@"
        ;;
    restart)
        "$SETUP_SCRIPT" --teardown "$@"
        exec "$SETUP_SCRIPT" --keep-running "$@"
        ;;
    status|diagnostics)
        exec "$SETUP_SCRIPT" --collect-diagnostics "$@"
        ;;
    logs)
        echo "Logs are collected by diagnostics. Run: $0 diagnostics $*" >&2
        exit 0
        ;;
    --help|-h|help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
