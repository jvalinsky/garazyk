#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0
#
# Docker acceptance smoke for the jelcz-a authenticated origin-publication path.
# It intentionally tests the already-running peership lab; it never starts a
# host jelcz and does not treat relay discovery as evidence.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly COMPOSE_FILE="${ROOT}/docker/streamplace-peership/docker-compose.yml"
readonly DEFAULT_ENV_FILE="${ROOT}/docker/streamplace-peership/.env"
readonly BLOCKED_EXIT=77
# shellcheck source=streamplace_peership_runtime_env.sh
source "${SCRIPT_DIR}/streamplace_peership_runtime_env.sh"

ENV_FILE="${COMPOSE_ENV_FILE:-${DEFAULT_ENV_FILE}}"
PROJECT_NAME_OVERRIDE=""
PDS_URL_OVERRIDE=""

COMPOSE=()
ACCESS_JWT=""
APP_PASSWORD_NAME=""
ANNOUNCED_RKEY=""
COMPOSE_RECREATED=0
CLEANUP_RUNNING=0
ORIGINAL_ORIGIN_ANNOUNCE=""
ORIGINAL_ORIGIN_IDENTIFIER=""
ORIGINAL_ORIGIN_APP_PASSWORD=""
ORIGINAL_ORIGIN_PDS_URL=""
ORIGINAL_ORIGIN_SERVER_DID=""
ORIGINAL_ORIGIN_HTTPS_BASE=""

usage() {
  cat <<'EOF'
Usage: streamplace_peership_federation_smoke.sh [options]

Exercise the Docker jelcz-a demo's authenticated origin announcement against
the already-running Garazyk local-network PDS. The script creates a temporary
PDS account and app password, recreates only jelcz-a with those credentials,
publishes one tools.garazyk.video.origin record, reads it from the PDS, and
retracts it.

Options:
  --env-file PATH      Compose environment file (default: docker/streamplace-peership/.env)
  --project-name NAME  Existing peership Compose project (default: env value)
  --pds-url URL        Host-reachable local PDS URL (default: http://LAB_PUBLIC_HOST:2583)
  -h, --help           Show help

Compose maps these environment variables into jelcz-a and this smoke verifies
that contract before it can run: JELCZ_ORIGIN_ANNOUNCE, JELCZ_ORIGIN_ANNOUNCE_IDENTIFIER,
JELCZ_ORIGIN_ANNOUNCE_APP_PASSWORD, JELCZ_ORIGIN_ANNOUNCE_PDS_URL, and
JELCZ_ORIGIN_ANNOUNCE_SERVER_DID. JELCZ_DEMO_API_TOKEN is used when supplied.
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
  local option_name="$1" value="${2:-}"
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
  fi
}

json_field() {
  python3 -c 'import json,sys; value=json.load(sys.stdin).get(sys.argv[1], ""); print(value if value is not None else "")' "$2" <<<"$1"
}

url_encode() {
  python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

compose_injects() {
  local variable_name="$1"
  grep -Eq "^[[:space:]]+${variable_name}:" "${COMPOSE_FILE}"
}

blocked_by_compose() {
  cat >&2 <<'EOF'
SKIP/BLOCKED: Docker jelcz-a cannot receive origin-announcer credentials.

The current docker/streamplace-peership/docker-compose.yml maps
JELCZ_DEMO_API_TOKEN but does not map the origin-announcer environment into
jelcz-a. Supplying variables only to this host script or to --env-file does not
put them in an already-running container, so this smoke will not substitute a
host jelcz or claim relay discovery.

To unblock, add these exact entries to the jelcz-a environment (or its shared
jelcz environment anchor) and recreate jelcz-a:

  JELCZ_ORIGIN_ANNOUNCE: "${JELCZ_ORIGIN_ANNOUNCE:-}"
  JELCZ_ORIGIN_ANNOUNCE_IDENTIFIER: "${JELCZ_ORIGIN_ANNOUNCE_IDENTIFIER:-}"
  JELCZ_ORIGIN_ANNOUNCE_APP_PASSWORD: "${JELCZ_ORIGIN_ANNOUNCE_APP_PASSWORD:-}"
  JELCZ_ORIGIN_ANNOUNCE_PDS_URL: "${JELCZ_ORIGIN_ANNOUNCE_PDS_URL:-http://local-pds:2583}"
  JELCZ_ORIGIN_ANNOUNCE_SERVER_DID: "${JELCZ_ORIGIN_ANNOUNCE_SERVER_DID:-}"
  # Optional; leave blank for this HTTP-only Compose lab:
  JELCZ_ORIGIN_ANNOUNCE_HTTPS_BASE: "${JELCZ_ORIGIN_ANNOUNCE_HTTPS_BASE:-}"

The smoke itself creates a disposable local PDS account and app password, then
temporarily supplies the identifier, app password, PDS URL, and DID through
that Compose boundary. It retracts the record and revokes the app password on
both success and failure.
EOF
  exit "${BLOCKED_EXIT}"
}

demo_mutation_curl() {
  if [[ -n "${JELCZ_DEMO_API_TOKEN:-}" ]]; then
    curl -H "Authorization: Bearer ${JELCZ_DEMO_API_TOKEN}" "$@"
  else
    curl "$@"
  fi
}

restore_jelcz_a_origin_configuration() {
  [[ "${COMPOSE_RECREATED}" -eq 1 ]] || return 0
  JELCZ_ORIGIN_ANNOUNCE="${ORIGINAL_ORIGIN_ANNOUNCE}"
  JELCZ_ORIGIN_ANNOUNCE_IDENTIFIER="${ORIGINAL_ORIGIN_IDENTIFIER}"
  JELCZ_ORIGIN_ANNOUNCE_APP_PASSWORD="${ORIGINAL_ORIGIN_APP_PASSWORD}"
  JELCZ_ORIGIN_ANNOUNCE_PDS_URL="${ORIGINAL_ORIGIN_PDS_URL}"
  JELCZ_ORIGIN_ANNOUNCE_SERVER_DID="${ORIGINAL_ORIGIN_SERVER_DID}"
  JELCZ_ORIGIN_ANNOUNCE_HTTPS_BASE="${ORIGINAL_ORIGIN_HTTPS_BASE}"
  export JELCZ_ORIGIN_ANNOUNCE JELCZ_ORIGIN_ANNOUNCE_IDENTIFIER
  export JELCZ_ORIGIN_ANNOUNCE_APP_PASSWORD JELCZ_ORIGIN_ANNOUNCE_PDS_URL
  export JELCZ_ORIGIN_ANNOUNCE_SERVER_DID JELCZ_ORIGIN_ANNOUNCE_HTTPS_BASE
  "${COMPOSE[@]}" up -d --no-deps --force-recreate jelcz-a >/dev/null || \
    err "could not recreate jelcz-a without the temporary announce credentials"
}

cleanup() {
  local exit_code="$?"
  [[ "${CLEANUP_RUNNING}" -eq 0 ]] || return "${exit_code}"
  CLEANUP_RUNNING=1
  set +e

  if [[ -n "${ANNOUNCED_RKEY}" ]]; then
    log "Cleanup: retracting ${ANNOUNCED_RKEY}…"
    demo_mutation_curl -fsS -X POST \
      -H 'content-type: application/json' \
      -d "{\"rkey\":\"${ANNOUNCED_RKEY}\"}" \
      "${JELCZ_A_BASE}/demo/streamplace/api/retract-origin" >/dev/null || \
      err "cleanup retract failed; remove rkey ${ANNOUNCED_RKEY} manually"
  fi

  if [[ -n "${ACCESS_JWT}" && -n "${APP_PASSWORD_NAME}" ]]; then
    log "Cleanup: revoking temporary app password…"
    curl -fsS -X POST "${PDS_URL}/xrpc/com.atproto.server.revokeAppPassword" \
      -H 'content-type: application/json' \
      -H "Authorization: Bearer ${ACCESS_JWT}" \
      -d "{\"name\":\"${APP_PASSWORD_NAME}\"}" >/dev/null || \
      err "cleanup app-password revocation failed; revoke ${APP_PASSWORD_NAME} manually"
  fi

  if [[ -n "${ACCESS_JWT}" ]]; then
    curl -fsS -X POST "${PDS_URL}/xrpc/com.atproto.server.deleteSession" \
      -H "Authorization: Bearer ${ACCESS_JWT}" >/dev/null || true
  fi
  restore_jelcz_a_origin_configuration
  return "${exit_code}"
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
    --pds-url)
      need_option_value "$1" "${2:-}"
      PDS_URL_OVERRIDE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      err "unknown option: $1"
      usage >&2
      exit 2
      ;;
  esac
done

load_env_file
ORIGINAL_ORIGIN_ANNOUNCE="${JELCZ_ORIGIN_ANNOUNCE:-0}"
ORIGINAL_ORIGIN_IDENTIFIER="${JELCZ_ORIGIN_ANNOUNCE_IDENTIFIER:-}"
ORIGINAL_ORIGIN_APP_PASSWORD="${JELCZ_ORIGIN_ANNOUNCE_APP_PASSWORD:-}"
ORIGINAL_ORIGIN_PDS_URL="${JELCZ_ORIGIN_ANNOUNCE_PDS_URL:-}"
ORIGINAL_ORIGIN_SERVER_DID="${JELCZ_ORIGIN_ANNOUNCE_SERVER_DID:-}"
ORIGINAL_ORIGIN_HTTPS_BASE="${JELCZ_ORIGIN_ANNOUNCE_HTTPS_BASE:-}"
COMPOSE_PROJECT_NAME="${PROJECT_NAME_OVERRIDE:-${COMPOSE_PROJECT_NAME:-streamplace-peership-demo}}"
export COMPOSE_PROJECT_NAME
RUNTIME_ENV_FILE="$(dirname "${ENV_FILE}")/.env.${COMPOSE_PROJECT_NAME}.runtime"
load_runtime_env_if_present

# This source-level preflight catches a regressed Compose boundary before
# creating an account or depending on Docker availability.
for required_mapping in \
  JELCZ_ORIGIN_ANNOUNCE \
  JELCZ_ORIGIN_ANNOUNCE_IDENTIFIER \
  JELCZ_ORIGIN_ANNOUNCE_APP_PASSWORD \
  JELCZ_ORIGIN_ANNOUNCE_PDS_URL \
  JELCZ_ORIGIN_ANNOUNCE_SERVER_DID
do
  compose_injects "${required_mapping}" || blocked_by_compose
done

need_cmd curl docker openssl python3
COMPOSE=(docker compose --env-file "${ENV_FILE}")
if [[ -f "${RUNTIME_ENV_FILE}" ]]; then
  COMPOSE+=(--env-file "${RUNTIME_ENV_FILE}")
fi
COMPOSE+=(--project-name "${COMPOSE_PROJECT_NAME}" -f "${COMPOSE_FILE}")

readonly JELCZ_A_BASE="http://${LAB_PUBLIC_HOST:-127.0.0.1}:${JELCZ_A_HOST_PORT:-2596}"
readonly PDS_URL="${PDS_URL_OVERRIDE:-${PDS_URL:-http://${LAB_PUBLIC_HOST:-127.0.0.1}:2583}}"
readonly PDS_CONTAINER_URL="${JELCZ_ORIGIN_ANNOUNCE_PDS_URL:-http://local-pds:2583}"
readonly RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
readonly HANDLE="streamplace-origin-${RUN_ID}.test"
readonly EMAIL="streamplace-origin-${RUN_ID}@garazyk-e2e.local"
readonly ACCOUNT_PASSWORD="$(openssl rand -hex 24)"
readonly MANIFEST_CID="bafkreigh2akiscaildcqabsybikkogfadovvy74igkn62d72smuariloqa"

trap cleanup EXIT

log "Preflight: checking the running Docker lab…"
"${COMPOSE[@]}" ps -q jelcz-a | grep -q . || {
  err "jelcz-a is not running in Compose project ${COMPOSE_PROJECT_NAME}"
  exit 1
}
curl -fsS -o /dev/null "${JELCZ_A_BASE}/_health" || {
  err "jelcz-a is not healthy at ${JELCZ_A_BASE}"
  exit 1
}
curl -fsS -o /dev/null "${PDS_URL}/xrpc/com.atproto.server.describeServer" || {
  err "local PDS is not reachable at ${PDS_URL}"
  exit 1
}

log "Creating disposable local PDS account ${HANDLE}…"
ACCOUNT_JSON="$(curl -fsS -X POST "${PDS_URL}/xrpc/com.atproto.server.createAccount" \
  -H 'content-type: application/json' \
  -d "{\"handle\":\"${HANDLE}\",\"email\":\"${EMAIL}\",\"password\":\"${ACCOUNT_PASSWORD}\"}")"
DID="$(json_field "${ACCOUNT_JSON}" did)"
ACCESS_JWT="$(json_field "${ACCOUNT_JSON}" accessJwt)"
[[ -n "${DID}" && -n "${ACCESS_JWT}" ]] || {
  err "createAccount did not return a DID and accessJwt"
  exit 1
}

APP_PASSWORD_NAME="streamplace-origin-${RUN_ID}"
APP_PASSWORD_JSON="$(curl -fsS -X POST "${PDS_URL}/xrpc/com.atproto.server.createAppPassword" \
  -H 'content-type: application/json' \
  -H "Authorization: Bearer ${ACCESS_JWT}" \
  -d "{\"name\":\"${APP_PASSWORD_NAME}\"}")"
APP_PASSWORD="$(json_field "${APP_PASSWORD_JSON}" password)"
[[ -n "${APP_PASSWORD}" ]] || {
  err "createAppPassword returned no password"
  exit 1
}

# The Compose mappings preflighted above make these values visible only to the
# Docker jelcz-a process. They are never printed and are removed in cleanup.
export JELCZ_ORIGIN_ANNOUNCE=1
export JELCZ_ORIGIN_ANNOUNCE_IDENTIFIER="${HANDLE}"
export JELCZ_ORIGIN_ANNOUNCE_APP_PASSWORD="${APP_PASSWORD}"
export JELCZ_ORIGIN_ANNOUNCE_PDS_URL="${PDS_CONTAINER_URL}"
export JELCZ_ORIGIN_ANNOUNCE_SERVER_DID="${DID}"
export JELCZ_ORIGIN_ANNOUNCE_HTTPS_BASE=""

log "Recreating Docker jelcz-a with the disposable origin-announcer identity…"
"${COMPOSE[@]}" up -d --no-deps --force-recreate jelcz-a >/dev/null
COMPOSE_RECREATED=1
for _ in $(seq 1 40); do
  curl -fsS -o /dev/null "${JELCZ_A_BASE}/_health" && break
  sleep 1
done
curl -fsS -o /dev/null "${JELCZ_A_BASE}/_health" || {
  err "jelcz-a did not become healthy after credential injection"
  exit 1
}

ANNOUNCED_RKEY="origin-smoke-${RUN_ID}"
SUBJECT_URI="at://${DID}/tools.garazyk.video/origin-smoke-${RUN_ID}"
log "Publishing tools.garazyk.video.origin through Docker jelcz-a…"
ANNOUNCE_JSON="$(demo_mutation_curl -fsS -X POST \
  -H 'content-type: application/json' \
  -d "{\"subjectUri\":\"${SUBJECT_URI}\",\"subjectCid\":\"${MANIFEST_CID}\",\"manifestCid\":\"${MANIFEST_CID}\",\"rkey\":\"${ANNOUNCED_RKEY}\"}" \
  "${JELCZ_A_BASE}/demo/streamplace/api/announce-origin")"
PUBLISHED_URI="$(json_field "${ANNOUNCE_JSON}" uri)"
[[ -n "${PUBLISHED_URI}" ]] || {
  err "Docker jelcz-a announce failed: ${ANNOUNCE_JSON}"
  exit 1
}

ENCODED_DID="$(url_encode "${DID}")"
RECORD_JSON="$(curl -fsS "${PDS_URL}/xrpc/com.atproto.repo.getRecord?repo=${ENCODED_DID}&collection=tools.garazyk.video.origin&rkey=${ANNOUNCED_RKEY}")"
[[ "$(json_field "${RECORD_JSON}" uri)" == "${PUBLISHED_URI}" ]] || {
  err "PDS getRecord did not return the Docker-published origin: ${RECORD_JSON}"
  exit 1
}
log "  PDS read-back confirmed ${PUBLISHED_URI}"

log "Retracting through Docker jelcz-a…"
demo_mutation_curl -fsS -X POST \
  -H 'content-type: application/json' \
  -d "{\"rkey\":\"${ANNOUNCED_RKEY}\"}" \
  "${JELCZ_A_BASE}/demo/streamplace/api/retract-origin" | \
  python3 -c 'import json,sys; assert json.load(sys.stdin).get("retracted") is True'
ANNOUNCED_RKEY=""

MISSING_STATUS="$(curl -sS -o /dev/null -w '%{http_code}' \
  "${PDS_URL}/xrpc/com.atproto.repo.getRecord?repo=${ENCODED_DID}&collection=tools.garazyk.video.origin&rkey=origin-smoke-${RUN_ID}")"
[[ "${MISSING_STATUS}" == "400" || "${MISSING_STATUS}" == "404" ]] || {
  err "expected absent record after Docker retract, got HTTP ${MISSING_STATUS}"
  exit 1
}

log "OK — Docker jelcz-a published, PDS read back, and retracted the origin record"
