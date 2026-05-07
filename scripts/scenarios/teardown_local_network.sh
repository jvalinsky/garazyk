#!/usr/bin/env bash
# teardown_local_network.sh — Stop the ATProto local-network Docker environment
#
# Usage:
#   ./teardown_local_network.sh              # Stop services, keep data
#   ./teardown_local_network.sh --wipe       # Stop and wipe volumes
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

REPO_ROOT="$(resolve_project_root "$SCRIPT_DIR")"
COMPOSE_DIR="$REPO_ROOT/docker/local-network"

WIPE=false
WITH_PDS2=false
COLLECT_DIAGNOSTICS=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --wipe|-w) WIPE=true ;;
        --pds2) WITH_PDS2=true ;;
        --collect-diagnostics) COLLECT_DIAGNOSTICS=true ;;
        --run-id)
            [[ $# -ge 2 ]] || error_exit "--run-id requires a value" 2
            ATPROTO_E2E_RUN_ID="$2"
            shift
            ;;
        --diagnostics-dir)
            [[ $# -ge 2 ]] || error_exit "--diagnostics-dir requires a value" 2
            ATPROTO_E2E_DIAGNOSTICS_DIR="$2"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--wipe] [--pds2] [--collect-diagnostics] [--run-id ID] [--diagnostics-dir DIR]"
            echo ""
            echo "  --wipe                 Also remove Docker volumes (destroys all data)"
            echo "  --pds2                 Include second-PDS scenario compose file"
            echo "  --collect-diagnostics  Capture status, health, and logs before teardown"
            echo "  --run-id ID            Teardown the compose project for this run id"
            echo "  --diagnostics-dir DIR  Write diagnostics to DIR"
            exit 0
            ;;
        *)
            error_exit "Unknown argument: $1" 2
            ;;
    esac
    shift
done

atproto_e2e_load_latest_run_id "scenario"
atproto_e2e_init_run

COMPOSE_FILES=("$COMPOSE_DIR/docker-compose.yml")
if [[ "$WITH_PDS2" == "true" || -f "$COMPOSE_DIR/docker-compose.scenarios.yml" ]]; then
    COMPOSE_FILES+=("$COMPOSE_DIR/docker-compose.scenarios.yml")
fi

COMPOSE_CMD=(docker compose -p "$ATPROTO_E2E_COMPOSE_PROJECT")
for compose_file in "${COMPOSE_FILES[@]}"; do
    COMPOSE_CMD+=(-f "$compose_file")
done

if [[ "$COLLECT_DIAGNOSTICS" == "true" ]]; then
    atproto_collect_diagnostics "$ATPROTO_E2E_DIAGNOSTICS_DIR" \
        "$COMPOSE_DIR" "$ATPROTO_E2E_COMPOSE_PROJECT" "${COMPOSE_FILES[@]}" || true
fi

if [[ "$WIPE" == "true" ]]; then
    log_info "Stopping local network and wiping volumes..."
    "${COMPOSE_CMD[@]}" down -v --remove-orphans
    log_ok "Local network stopped and volumes wiped"
else
    log_info "Stopping local network (preserving volumes)..."
    "${COMPOSE_CMD[@]}" down --remove-orphans
    log_ok "Local network stopped (volumes preserved)"
fi
