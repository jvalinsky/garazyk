#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0
#
# Tear down the Streamplace peership compose stack.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly COMPOSE_FILE="${ROOT}/docker/streamplace-peership/docker-compose.yml"

ATPROTO=0

usage() {
  cat <<'EOF'
Usage: streamplace_peership_down.sh [--atproto] [--wipe]

  --atproto  Also tear down Garazyk local-network
  --wipe     docker compose down -v (peership volumes)

EOF
}

WIPE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --atproto) ATPROTO=1 ;;
    --wipe) WIPE=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'error: unknown option: %s\n' "$1" >&2
      usage
      exit 2
      ;;
  esac
  shift
done

if [[ -f "${ROOT}/docker/streamplace-peership/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT}/docker/streamplace-peership/.env"
  set +a
fi

export GARAZYK_ATPROTO_NET="${GARAZYK_ATPROTO_NET:-local-network_local_net}"

DOWN=(docker compose -f "${COMPOSE_FILE}" --profile publish down)
if [[ "${WIPE}" -eq 1 ]]; then
  DOWN+=(-v)
fi
"${DOWN[@]}" || true

if [[ "${ATPROTO}" -eq 1 ]]; then
  "${ROOT}/scripts/scenarios/setup_local_network.sh" --teardown || true
fi

printf 'Peership stack stopped.\n'
