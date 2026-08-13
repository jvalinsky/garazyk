#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0
#
# Live smoke: createAccount on local PDS → jelcz ORIGIN_ANNOUNCE →
# announce-origin / retract-origin (WS16 Phase 3 gate).

set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly PDS="${PDS_URL:-http://127.0.0.1:2583}"
readonly PORT="${JELCZ_ANNOUNCE_PORT:-2599}"
readonly BASE="http://127.0.0.1:${PORT}"
readonly HANDLE_SLUG="jelcz-announce-$(date +%s)"
readonly HANDLE="${HANDLE_SLUG}.test"
readonly EMAIL="${HANDLE_SLUG}@garazyk-e2e.local"
readonly PASSWORD="${JELCZ_ANNOUNCE_PASSWORD:-announce-smoke-pass-1}"
readonly DATA_DIR="${ROOT}/build/jelcz-announce-smoke"
readonly JELCZ_BIN="${JELCZ_BIN:-${ROOT}/build/bin/jelcz}"

log() { printf '%s\n' "$*"; }
err() { printf 'error: %s\n' "$*" >&2; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "missing $1"
    exit 1
  }
}

json_field() {
  python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get(sys.argv[1],"") or "")' "$2" <<<"$1"
}

need_cmd curl
need_cmd python3

[[ -x "${JELCZ_BIN}" ]] || {
  err "jelcz binary missing: ${JELCZ_BIN} (build target jelcz)"
  exit 1
}

curl -fsS -o /dev/null "${PDS}/xrpc/com.atproto.server.describeServer" || {
  err "PDS not reachable at ${PDS}"
  exit 1
}

log "Creating PDS account ${HANDLE}…"
ACCT="$(curl -fsS -X POST "${PDS}/xrpc/com.atproto.server.createAccount" \
  -H 'content-type: application/json' \
  -d "{\"handle\":\"${HANDLE}\",\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\"}")"
DID="$(json_field "${ACCT}" did)"
[[ -n "${DID}" ]] || {
  err "createAccount failed: ${ACCT}"
  exit 1
}
log "  did=${DID}"

rm -rf "${DATA_DIR}"
mkdir -p "${DATA_DIR}"

pkill -f "jelcz serve --port ${PORT}" 2>/dev/null || true
sleep 0.3

export JELCZ_STREAMPLACE_DEMO=1
export JELCZ_STREAMPLACE_SERVE_COMPAT=1
export JELCZ_STREAMPLACE_MIRROR_BASE=https://stream.place
export JELCZ_STREAMPLACE_ATTRIBUTION_DID=did:web:stream.place
export JELCZ_CA_MIRROR_FETCH=1
export JELCZ_ORIGIN_ANNOUNCE=1
export JELCZ_ORIGIN_ANNOUNCE_PDS_URL="${PDS}"
export JELCZ_ORIGIN_ANNOUNCE_IDENTIFIER="${HANDLE}"
export JELCZ_ORIGIN_ANNOUNCE_APP_PASSWORD="${PASSWORD}"
export JELCZ_ORIGIN_ANNOUNCE_SERVER_DID="${DID}"
export JELCZ_ORIGIN_ANNOUNCE_HTTPS_BASE="${BASE}"
export JELCZ_DEMO_UI_PATH="${ROOT}/Garazyk/Resources/jelcz-demo/streamplace-peer.html"

log "Starting jelcz on :${PORT} with origin announce…"
"${JELCZ_BIN}" serve --port "${PORT}" --data-dir "${DATA_DIR}" \
  >"${DATA_DIR}/jelcz.log" 2>&1 &
JELCZ_PID=$!
trap 'kill "${JELCZ_PID}" 2>/dev/null || true' EXIT

for _ in $(seq 1 40); do
  if curl -fsS -o /dev/null "${BASE}/_health" 2>/dev/null; then
    break
  fi
  sleep 0.25
done
curl -fsS -o /dev/null "${BASE}/_health" || {
  err "jelcz did not become healthy; log:"
  tail -n 40 "${DATA_DIR}/jelcz.log" >&2 || true
  exit 1
}

SUBJECT_URI="at://${DID}/tools.garazyk.video/smoke1"
MANIFEST_CID="bafkreigh2akiscaildcqabsybikkogfadovvy74igkn62d72smuariloqa"

log "POST announce-origin…"
ANN="$(curl -sS -X POST "${BASE}/demo/streamplace/api/announce-origin" \
  -H 'content-type: application/json' \
  -d "{\"subjectUri\":\"${SUBJECT_URI}\",\"subjectCid\":\"${MANIFEST_CID}\",\"manifestCid\":\"${MANIFEST_CID}\",\"rkey\":\"smoke1\"}")"
URI="$(json_field "${ANN}" uri)"
RKEY="$(json_field "${ANN}" rkey)"
[[ -n "${URI}" && -n "${RKEY}" ]] || {
  err "announce failed: ${ANN}"
  tail -n 40 "${DATA_DIR}/jelcz.log" >&2 || true
  exit 1
}
log "  uri=${URI} rkey=${RKEY}"

log "GET record from PDS…"
ENC_DID="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "${DID}")"
REC="$(curl -fsS "${PDS}/xrpc/com.atproto.repo.getRecord?repo=${ENC_DID}&collection=tools.garazyk.video.origin&rkey=${RKEY}")"
GOT_URI="$(json_field "${REC}" uri)"
[[ "${GOT_URI}" == "${URI}" ]] || {
  err "getRecord mismatch: ${REC}"
  exit 1
}
log "  getRecord ok"

log "POST retract-origin…"
RET="$(curl -fsS -X POST "${BASE}/demo/streamplace/api/retract-origin" \
  -H 'content-type: application/json' \
  -d "{\"rkey\":\"${RKEY}\"}")"
python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("retracted") is True, d' <<<"${RET}"
log "  retracted"

CODE="$(curl -s -o /dev/null -w '%{http_code}' \
  "${PDS}/xrpc/com.atproto.repo.getRecord?repo=${ENC_DID}&collection=tools.garazyk.video.origin&rkey=${RKEY}")"
[[ "${CODE}" == "400" || "${CODE}" == "404" ]] || {
  err "expected missing record after retract, HTTP ${CODE}"
  exit 1
}

log ""
log "OK — live PDS origin announce/retract smoke passed"
log "  handle=${HANDLE} did=${DID}"
log "  announced ${URI} then retracted"
