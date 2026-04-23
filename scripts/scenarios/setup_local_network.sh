#!/usr/bin/env bash
# setup_local_network.sh — Start the ATProto local-network Docker environment
#
# Usage:
#   ./setup_local_network.sh              # Start PLC + PDS + Relay + AppView
#   ./setup_local_network.sh --pds2       # Also start second PDS for federation
#   ./setup_local_network.sh --wait-only  # Just wait for healthy, don't start
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_DIR="$REPO_ROOT/docker/local-network"

WITH_PDS2=false
WAIT_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --pds2)     WITH_PDS2=true ;;
        --wait-only) WAIT_ONLY=true ;;
        --help|-h)
            echo "Usage: $0 [--pds2] [--wait-only]"
            echo ""
            echo "  --pds2       Also start a second PDS on port 2585 (for federation scenarios)"
            echo "  --wait-only  Don't start services, just wait for them to be healthy"
            exit 0
            ;;
    esac
done

# Colors
if [[ -t 1 ]] && [[ "${NO_COLOR:-false}" != "true" ]]; then
    GREEN='\033[0;32m' YELLOW='\033[1;33m' CYAN='\033[0;36m' NC='\033[0m'
else
    GREEN='' YELLOW='' CYAN='' NC=''
fi

log()  { echo -e "${CYAN}[SETUP]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

if [[ "$WAIT_ONLY" != "true" ]]; then
    log "Starting local network..."
    COMPOSE_CMD="docker compose -f $COMPOSE_DIR/docker-compose.yml"
    if [[ "$WITH_PDS2" == "true" ]]; then
        COMPOSE_CMD="$COMPOSE_CMD -f $COMPOSE_DIR/docker-compose.scenarios.yml"
        log "Including second PDS (port 2585)"
    fi
    $COMPOSE_CMD up -d
fi

# Wait for services
wait_for() {
    local name="$1" url="$2" timeout="${3:-60}"
    log "Waiting for $name to be healthy..."
    deadline=$((SECONDS + timeout))
    while [[ $SECONDS -lt $deadline ]]; do
        if curl -sf "$url" >/dev/null 2>&1; then
            ok "$name is healthy"
            return 0
        fi
        sleep 2
    done
    warn "$name not healthy after ${timeout}s (url: $url)"
    return 1
}

wait_for "PLC"     "http://localhost:2582/_health"                                60
wait_for "PDS"     "http://localhost:2583/xrpc/com.atproto.server.describeServer" 60
wait_for "Relay"   "http://localhost:2584/api/relay/health"                      60
wait_for "AppView" "http://localhost:3200/_health"                               90

if [[ "$WITH_PDS2" == "true" ]]; then
    wait_for "PDS2" "http://localhost:2585/xrpc/com.atproto.server.describeServer" 60
fi

echo ""
ok "Local network is ready!"
echo ""
echo "  PLC:     http://localhost:2582"
echo "  PDS:     http://localhost:2583"
echo "  Relay:   http://localhost:2584"
echo "  AppView: http://localhost:3200"
if [[ "$WITH_PDS2" == "true" ]]; then
    echo "  PDS2:    http://localhost:2585"
fi
echo ""
