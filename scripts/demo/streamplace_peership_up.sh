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
readonly DEFAULT_NET="${GARAZYK_ATPROTO_NET:-local-network_local_net}"

PUBLISH=0
STATUS_ONLY=0
SKIP_ATPROTO=0
SKIP_STAGE=0

usage() {
  cat <<'EOF'
Usage: streamplace_peership_up.sh [options]

  --publish       Also start ffmpeg RTMP publisher (compose profile publish)
  --status        Print URLs / container health only
  --skip-atproto  Do not start local-network (network must already exist)
  --skip-stage    Do not run scripts/stage_binaries.ts
  -h, --help      Show help

EOF
}

log() { printf '%s\n' "$*"; }
err() { printf 'error: %s\n' "$*" >&2; }

need_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || {
      err "missing required command: $c"
      exit 1
    }
  done
}

resolve_atproto_net() {
  if docker network inspect "${DEFAULT_NET}" >/dev/null 2>&1; then
    printf '%s\n' "${DEFAULT_NET}"
    return 0
  fi
  # Fallback: first docker network matching local-network*
  local found
  found="$(docker network ls --format '{{.Name}}' | grep -E '^local-network' | head -n1 || true)"
  if [[ -n "${found}" ]]; then
    printf '%s\n' "${found}"
    return 0
  fi
  return 1
}

print_status() {
  local net="${GARAZYK_ATPROTO_NET:-${DEFAULT_NET}}"
  log "ATProto network: ${net}"
  log ""
  log "URLs:"
  log "  jelcz-a demo:  http://127.0.0.1:${JELCZ_A_PORT:-2596}/demo/streamplace"
  log "  jelcz-b demo:  http://127.0.0.1:${JELCZ_B_PORT:-2597}/demo/streamplace"
  log "  jelcz-c demo:  http://127.0.0.1:${JELCZ_C_PORT:-2598}/demo/streamplace"
  log "  Streamplace:   http://127.0.0.1:${STREAMPLACE_HTTP_PORT:-38080}/"
  log "  PDS:           http://127.0.0.1:2583/xrpc/com.atproto.server.describeServer"
  log ""
  docker compose -f "${COMPOSE_FILE}" ps || true
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --publish) PUBLISH=1 ;;
    --status) STATUS_ONLY=1 ;;
    --skip-atproto) SKIP_ATPROTO=1 ;;
    --skip-stage) SKIP_STAGE=1 ;;
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
  shift
done

need_cmd docker curl
if [[ "${STATUS_ONLY}" -eq 1 ]]; then
  print_status
  exit 0
fi

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  err "compose file missing: ${COMPOSE_FILE}"
  exit 1
fi

if [[ "${SKIP_STAGE}" -eq 0 ]]; then
  need_cmd deno
  log "Staging Linux jelcz binaries…"
  (cd "${ROOT}" && deno run -A scripts/stage_binaries.ts)
else
  if [[ ! -x "${ROOT}/docker/local-network/staging/bin/jelcz" ]]; then
    err "jelcz staging binary missing; run without --skip-stage or stage_binaries.ts"
    exit 1
  fi
fi

if [[ "${SKIP_ATPROTO}" -eq 0 ]]; then
  log "Starting Garazyk local ATProto network…"
  "${ROOT}/scripts/scenarios/setup_local_network.sh"
else
  log "Skipping ATProto start (--skip-atproto)"
fi

NET="$(resolve_atproto_net)" || {
  err "Docker network ${DEFAULT_NET} not found. Start ATProto first or set GARAZYK_ATPROTO_NET."
  exit 1
}
export GARAZYK_ATPROTO_NET="${NET}"
log "Using Docker network: ${GARAZYK_ATPROTO_NET}"

# Load optional .env next to compose
if [[ -f "${ROOT}/docker/streamplace-peership/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT}/docker/streamplace-peership/.env"
  set +a
fi

COMPOSE=(docker compose -f "${COMPOSE_FILE}")
PROFILES=()
if [[ "${PUBLISH}" -eq 1 ]]; then
  PROFILES+=(--profile publish)
fi

log "Building / starting Streamplace + jelcz peers…"
"${COMPOSE[@]}" "${PROFILES[@]}" up -d --build

log "Waiting for health…"
for url in \
  "http://127.0.0.1:${STREAMPLACE_HTTP_PORT:-38080}/api/healthz" \
  "http://127.0.0.1:${JELCZ_A_PORT:-2596}/_health" \
  "http://127.0.0.1:${JELCZ_B_PORT:-2597}/_health" \
  "http://127.0.0.1:${JELCZ_C_PORT:-2598}/_health"
do
  ok=0
  for _ in $(seq 1 60); do
    if curl -fsS -o /dev/null "$url" 2>/dev/null; then
      ok=1
      break
    fi
    # Streamplace sometimes only serves /
    if [[ "$url" == *healthz ]]; then
      if curl -fsS -o /dev/null "http://127.0.0.1:${STREAMPLACE_HTTP_PORT:-38080}/" 2>/dev/null; then
        ok=1
        break
      fi
    fi
    sleep 2
  done
  if [[ "$ok" -ne 1 ]]; then
    err "timeout waiting for ${url}"
    "${COMPOSE[@]}" logs --tail=80 || true
    exit 1
  fi
  log "  ready: ${url}"
done

print_status
log ""
log "Next: ./scripts/demo/streamplace_peership_smoke.sh"
