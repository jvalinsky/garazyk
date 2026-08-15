#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0
#
# Tear down one Streamplace peership compose project without affecting other
# concurrent lab projects.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly COMPOSE_FILE="${ROOT}/docker/streamplace-peership/docker-compose.yml"
readonly DEFAULT_ENV_FILE="${ROOT}/docker/streamplace-peership/.env"
# shellcheck source=streamplace_peership_runtime_env.sh
source "${SCRIPT_DIR}/streamplace_peership_runtime_env.sh"

ATPROTO=0
WIPE=0
ENV_FILE="${COMPOSE_ENV_FILE:-${DEFAULT_ENV_FILE}}"
PROJECT_NAME_OVERRIDE=""

usage() {
  cat <<'EOF'
Usage: streamplace_peership_down.sh [options]

  --env-file PATH      Explicit compose environment file (default: docker/streamplace-peership/.env)
  --project-name NAME  Compose project to stop (default: COMPOSE_PROJECT_NAME from env file)
  --atproto            Also tear down Garazyk local-network
  --wipe               Remove this project's named volumes as well
  -h, --help           Show help

`--wipe` is scoped to the selected Compose project. It is appropriate for a
--fresh acceptance run; omit it to retain the persistent demo state.
EOF
}

err() { printf 'error: %s\n' "$*" >&2; }

need_option_value() {
  local option_name="$1"
  local value="${2:-}"
  if [[ -z "${value}" || "${value}" == --* ]]; then
    err "${option_name} requires a value"
    exit 2
  fi
}

load_env_file() {
  if [[ ! -f "${ENV_FILE}" ]]; then
    err "environment file missing: ${ENV_FILE} (copy docker/streamplace-peership/.env.example to .env)"
    exit 1
  fi
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
}

load_runtime_env_if_present() {
  if [[ -e "${RUNTIME_ENV_FILE}" || -L "${RUNTIME_ENV_FILE}" ]]; then
    peership_load_runtime_capabilities "${RUNTIME_ENV_FILE}"
    RUNTIME_ENV_ACTIVE=1
  fi
}

validate_project_name() {
  local project_name="$1"
  if ! [[ "${project_name}" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
    err "invalid Compose project name: ${project_name} (use lowercase letters, digits, _ or -)"
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      need_option_value "$1" "${2:-}"
      ENV_FILE="$2"
      shift 2
      ;;
    --project-name)
      need_option_value "$1" "${2:-}"
      PROJECT_NAME_OVERRIDE="$2"
      shift 2
      ;;
    --atproto) ATPROTO=1; shift ;;
    --wipe) WIPE=1; shift ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      err "unknown option: $1"
      usage
      exit 2
      ;;
  esac
done

load_env_file
COMPOSE_PROJECT_NAME="${PROJECT_NAME_OVERRIDE:-${COMPOSE_PROJECT_NAME:-streamplace-peership-demo}}"
export COMPOSE_PROJECT_NAME
validate_project_name "${COMPOSE_PROJECT_NAME}"
RUNTIME_ENV_FILE="$(dirname "${ENV_FILE}")/.env.${COMPOSE_PROJECT_NAME}.runtime"
RUNTIME_ENV_ACTIVE=0
load_runtime_env_if_present

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  err "compose file missing: ${COMPOSE_FILE}"
  exit 1
fi

COMPOSE_ENV_ARGS=(--env-file "${ENV_FILE}")
if [[ "${RUNTIME_ENV_ACTIVE}" -eq 1 ]]; then
  COMPOSE_ENV_ARGS+=(--env-file "${RUNTIME_ENV_FILE}")
fi
COMPOSE=(docker compose "${COMPOSE_ENV_ARGS[@]}" --project-name "${COMPOSE_PROJECT_NAME}" -f "${COMPOSE_FILE}")
DOWN=("${COMPOSE[@]}" --profile publish down)
if [[ "${WIPE}" -eq 1 ]]; then
  DOWN+=(-v)
fi
"${DOWN[@]}"
if [[ "${WIPE}" -eq 1 && "${RUNTIME_ENV_ACTIVE}" -eq 1 ]]; then
  rm -f "${RUNTIME_ENV_FILE}"
fi

if [[ "${ATPROTO}" -eq 1 ]]; then
  "${ROOT}/scripts/scenarios/setup_local_network.sh" --teardown
fi

printf 'Peership project %s stopped%s.\n' "${COMPOSE_PROJECT_NAME}" "$([[ "${WIPE}" -eq 1 ]] && printf ' and volumes removed')"
