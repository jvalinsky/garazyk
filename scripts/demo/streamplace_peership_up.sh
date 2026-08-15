#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0
#
# Bring up Garazyk local ATProto + Streamplace + three jelcz peers.
# See docker/streamplace-peership/README.md

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly COMPOSE_FILE="${ROOT}/docker/streamplace-peership/docker-compose.yml"
readonly DEFAULT_ENV_FILE="${ROOT}/docker/streamplace-peership/.env"
# shellcheck source=streamplace_peership_runtime_env.sh
source "${SCRIPT_DIR}/streamplace_peership_runtime_env.sh"

PUBLISH=0
STATUS_ONLY=0
SKIP_ATPROTO=0
SKIP_STAGE=0
FRESH=0
ENV_FILE="${COMPOSE_ENV_FILE:-${DEFAULT_ENV_FILE}}"
PROJECT_NAME_OVERRIDE=""

usage() {
  cat <<'EOF'
Usage: streamplace_peership_up.sh [options]

  --env-file PATH      Explicit compose environment file (default: docker/streamplace-peership/.env)
  --project-name NAME  Compose project name; isolates containers and volumes
  --fresh              Generate a new acceptance project name with empty project-owned volumes
  --publish            Also start ffmpeg RTMP publisher (compose profile publish)
  --status             Print URLs / container health only
  --skip-atproto       Do not start local-network (network must already exist)
  --skip-stage         Do not run scripts/stage_binaries.ts
  -h, --help           Show help

Copy docker/streamplace-peership/.env.example to .env. It contains the tested
Streamplace digest; set an explicit immutable FFMPEG_IMAGE before --publish.
EOF
}

log() { printf '%s\n' "$*"; }
err() { printf 'error: %s\n' "$*" >&2; }

need_cmd() {
  local command_name
  for command_name in "$@"; do
    command -v "${command_name}" >/dev/null 2>&1 || {
      err "missing required command: ${command_name}"
      exit 1
    }
  done
}

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

  # The env file is an operator-controlled shell-compatible configuration file.
  # Source it before resolving status, network, ports, and project name so every
  # path below sees precisely the values supplied to Compose via --env-file.
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

ensure_demo_api_token() {
  if ! command -v openssl >/dev/null 2>&1; then
    err "openssl is required to generate required runtime capabilities; set them in ${ENV_FILE} instead"
    exit 1
  fi

  local generated=0
  if [[ -z "${JELCZ_DEMO_API_TOKEN:-}" ]]; then
    JELCZ_DEMO_API_TOKEN="$(openssl rand -hex 32)"
    export JELCZ_DEMO_API_TOKEN
    generated=1
  fi
  if [[ -z "${JELCZ_IROH_SIDECAR_CAPABILITY:-}" ]]; then
    JELCZ_IROH_SIDECAR_CAPABILITY="$(openssl rand -hex 32)"
    export JELCZ_IROH_SIDECAR_CAPABILITY
    generated=1
  fi
  if [[ "${generated}" -eq 0 ]]; then
    return 0
  fi
  peership_write_runtime_capabilities "${RUNTIME_ENV_FILE}" \
    "${JELCZ_DEMO_API_TOKEN}" "${JELCZ_IROH_SIDECAR_CAPABILITY}"
  RUNTIME_ENV_ACTIVE=1
  log "Generated missing per-project runtime capabilities in ${RUNTIME_ENV_FILE}"
}

validate_publish_image() {
  local image_reference="${FFMPEG_IMAGE:-}"
  if [[ -z "${image_reference}" ]]; then
    err "--publish requires FFMPEG_IMAGE in ${ENV_FILE}; use a tested immutable tag or digest"
    exit 2
  fi
  if [[ "${image_reference}" == *:latest || "${image_reference}" == latest ]]; then
    err "--publish refuses floating FFMPEG_IMAGE=${image_reference}; use a tested immutable tag or digest"
    exit 2
  fi
}

validate_project_name() {
  local project_name="$1"
  if ! [[ "${project_name}" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
    err "invalid Compose project name: ${project_name} (use lowercase letters, digits, _ or -)"
    exit 2
  fi
}

resolve_atproto_net() {
  local requested_network="$1"
  if docker network inspect "${requested_network}" >/dev/null 2>&1; then
    printf '%s\n' "${requested_network}"
    return 0
  fi

  local found_network
  found_network="$(docker network ls --format '{{.Name}}' | grep -E '^local-network' | head -n1 || true)"
  if [[ -n "${found_network}" ]]; then
    printf '%s\n' "${found_network}"
    return 0
  fi
  return 1
}

print_status() {
  local network_name="$1"
  log "Compose project: ${COMPOSE_PROJECT_NAME}"
  log "ATProto network: ${network_name}"
  log ""
  log "Host URLs (published on ${LAB_BIND_ADDRESS:-127.0.0.1}):"
  log "  jelcz-a demo:     http://${LAB_PUBLIC_HOST:-127.0.0.1}:${JELCZ_A_HOST_PORT:-2596}/demo/streamplace"
  log "  jelcz-a overwatch: http://${LAB_PUBLIC_HOST:-127.0.0.1}:${JELCZ_A_HOST_PORT:-2596}/demo/streamplace/overwatch"
  log "  jelcz-b demo:     http://${LAB_PUBLIC_HOST:-127.0.0.1}:${JELCZ_B_HOST_PORT:-2597}/demo/streamplace"
  log "  jelcz-c demo:     http://${LAB_PUBLIC_HOST:-127.0.0.1}:${JELCZ_C_HOST_PORT:-2598}/demo/streamplace"
  log "  Streamplace:      http://${LAB_PUBLIC_HOST:-127.0.0.1}:${STREAMPLACE_HTTP_HOST_PORT:-38080}/"
  log "  PDS:              http://${LAB_PUBLIC_HOST:-127.0.0.1}:2583/xrpc/com.atproto.server.describeServer"
  log ""
  "${COMPOSE[@]}" ps || true
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
    --fresh) FRESH=1; shift ;;
    --publish) PUBLISH=1; shift ;;
    --status) STATUS_ONLY=1; shift ;;
    --skip-atproto) SKIP_ATPROTO=1; shift ;;
    --skip-stage) SKIP_STAGE=1; shift ;;
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

if [[ -n "${PROJECT_NAME_OVERRIDE}" ]]; then
  COMPOSE_PROJECT_NAME="${PROJECT_NAME_OVERRIDE}"
elif [[ "${FRESH}" -eq 1 ]]; then
  COMPOSE_PROJECT_NAME="streamplace-peership-acceptance-$(date -u +%Y%m%d%H%M%S)-$$"
else
  COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-streamplace-peership-demo}"
fi
export COMPOSE_PROJECT_NAME
validate_project_name "${COMPOSE_PROJECT_NAME}"

readonly DEFAULT_NET="${GARAZYK_ATPROTO_NET:-local-network_local_net}"
RUNTIME_ENV_FILE="$(dirname "${ENV_FILE}")/.env.${COMPOSE_PROJECT_NAME}.runtime"
RUNTIME_ENV_ACTIVE=0
load_runtime_env_if_present
if [[ "${STATUS_ONLY}" -eq 0 ]]; then
  if [[ "${PUBLISH}" -eq 1 ]]; then
    validate_publish_image
  fi
  ensure_demo_api_token
elif [[ -z "${JELCZ_DEMO_API_TOKEN:-}" || -z "${JELCZ_IROH_SIDECAR_CAPABILITY:-}" ]]; then
  # `docker compose ps` still interpolates the model.  These placeholders are
  # used only for missing values during read-only status inspection.
  if [[ -z "${JELCZ_DEMO_API_TOKEN:-}" ]]; then
    JELCZ_DEMO_API_TOKEN="status-inspection-placeholder"
  fi
  if [[ -z "${JELCZ_IROH_SIDECAR_CAPABILITY:-}" ]]; then
    JELCZ_IROH_SIDECAR_CAPABILITY="status-inspection-placeholder"
  fi
  export JELCZ_DEMO_API_TOKEN
  export JELCZ_IROH_SIDECAR_CAPABILITY
fi

COMPOSE_ENV_ARGS=(--env-file "${ENV_FILE}")
if [[ "${RUNTIME_ENV_ACTIVE}" -eq 1 ]]; then
  COMPOSE_ENV_ARGS+=(--env-file "${RUNTIME_ENV_FILE}")
fi
COMPOSE=(docker compose "${COMPOSE_ENV_ARGS[@]}" --project-name "${COMPOSE_PROJECT_NAME}" -f "${COMPOSE_FILE}")

need_cmd docker curl
if [[ ! -f "${COMPOSE_FILE}" ]]; then
  err "compose file missing: ${COMPOSE_FILE}"
  exit 1
fi

if [[ "${STATUS_ONLY}" -eq 1 ]]; then
  print_status "${DEFAULT_NET}"
  exit 0
fi

if [[ "${SKIP_STAGE}" -eq 0 ]]; then
  need_cmd deno
  log "Staging Linux jelcz binaries…"
  (cd "${ROOT}" && deno run -A scripts/stage_binaries.ts)
elif [[ ! -x "${ROOT}/docker/local-network/staging/bin/jelcz" ]]; then
  err "jelcz staging binary missing; run without --skip-stage or stage_binaries.ts"
  exit 1
fi

if [[ "${SKIP_ATPROTO}" -eq 0 ]]; then
  log "Starting Garazyk local ATProto network…"
  "${ROOT}/scripts/scenarios/setup_local_network.sh"
else
  log "Skipping ATProto start (--skip-atproto)"
fi

NETWORK_NAME="$(resolve_atproto_net "${DEFAULT_NET}")" || {
  err "Docker network ${DEFAULT_NET} not found. Start ATProto first or set GARAZYK_ATPROTO_NET."
  exit 1
}
export GARAZYK_ATPROTO_NET="${NETWORK_NAME}"
log "Using Docker network: ${GARAZYK_ATPROTO_NET}"

log "Validating Compose configuration…"
if [[ "${PUBLISH}" -eq 1 ]]; then
  "${COMPOSE[@]}" --profile publish config -q
else
  "${COMPOSE[@]}" config -q
fi

log "Building / starting Streamplace + jelcz peers (project: ${COMPOSE_PROJECT_NAME})…"
if [[ "${PUBLISH}" -eq 1 ]]; then
  "${COMPOSE[@]}" --profile publish up -d --build
else
  "${COMPOSE[@]}" up -d --build
fi

log "Waiting for health…"
for url in \
  "http://${LAB_PUBLIC_HOST:-127.0.0.1}:${STREAMPLACE_HTTP_HOST_PORT:-38080}/api/healthz" \
  "http://${LAB_PUBLIC_HOST:-127.0.0.1}:${JELCZ_A_HOST_PORT:-2596}/_health" \
  "http://${LAB_PUBLIC_HOST:-127.0.0.1}:${JELCZ_B_HOST_PORT:-2597}/_health" \
  "http://${LAB_PUBLIC_HOST:-127.0.0.1}:${JELCZ_C_HOST_PORT:-2598}/_health"
do
  ready=0
  for _ in $(seq 1 60); do
    if curl -fsS -o /dev/null "${url}" 2>/dev/null; then
      ready=1
      break
    fi
    if [[ "${url}" == *healthz ]] && curl -fsS -o /dev/null "http://${LAB_PUBLIC_HOST:-127.0.0.1}:${STREAMPLACE_HTTP_HOST_PORT:-38080}/" 2>/dev/null; then
      ready=1
      break
    fi
    sleep 2
  done
  if [[ "${ready}" -ne 1 ]]; then
    err "timeout waiting for ${url}"
    "${COMPOSE[@]}" logs --tail=80 || true
    exit 1
  fi
  log "  ready: ${url}"
done

print_status "${NETWORK_NAME}"
log ""
if [[ "${RUNTIME_ENV_ACTIVE}" -eq 1 ]]; then
  printf -v RUNTIME_ENV_FILE_SHELL '%q' "${RUNTIME_ENV_FILE}"
  log "Next: source ./scripts/demo/streamplace_peership_runtime_env.sh; peership_load_runtime_capabilities ${RUNTIME_ENV_FILE_SHELL}; COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME} ./scripts/demo/streamplace_peership_smoke.sh"
else
  log "Next: COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME} ./scripts/demo/streamplace_peership_smoke.sh"
fi
if [[ "${FRESH}" -eq 1 ]]; then
  log "Fresh acceptance state is project-owned. Remove it with: ./scripts/demo/streamplace_peership_down.sh --project-name ${COMPOSE_PROJECT_NAME} --wipe"
fi
