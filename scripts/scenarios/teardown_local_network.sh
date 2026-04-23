#!/usr/bin/env bash
# teardown_local_network.sh — Stop the ATProto local-network Docker environment
#
# Usage:
#   ./teardown_local_network.sh              # Stop services, keep data
#   ./teardown_local_network.sh --wipe       # Stop and wipe volumes
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_DIR="$REPO_ROOT/docker/local-network"

WIPE=false

for arg in "$@"; do
    case "$arg" in
        --wipe|-w) WIPE=true ;;
        --help|-h)
            echo "Usage: $0 [--wipe]"
            echo ""
            echo "  --wipe  Also remove Docker volumes (destroys all data)"
            exit 0
            ;;
    esac
done

# Colors
if [[ -t 1 ]] && [[ "${NO_COLOR:-false}" != "true" ]]; then
    CYAN='\033[0;36m' YELLOW='\033[1;33m' GREEN='\033[0;32m' NC='\033[0m'
else
    CYAN='' YELLOW='' GREEN='' NC=''
fi

log()  { echo -e "${CYAN}[TEARDOWN]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }

COMPOSE_CMD="docker compose -f $COMPOSE_DIR/docker-compose.yml"

# Check if scenarios override exists and include it if so
if [[ -f "$COMPOSE_DIR/docker-compose.scenarios.yml" ]]; then
    COMPOSE_CMD="$COMPOSE_CMD -f $COMPOSE_DIR/docker-compose.scenarios.yml"
fi

if [[ "$WIPE" == "true" ]]; then
    log "Stopping local network and wiping volumes..."
    $COMPOSE_CMD down -v
    ok "Local network stopped and volumes wiped"
else
    log "Stopping local network (preserving volumes)..."
    $COMPOSE_CMD down
    ok "Local network stopped (volumes preserved)"
fi
