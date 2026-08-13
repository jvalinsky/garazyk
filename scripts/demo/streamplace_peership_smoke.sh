#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0
#
# Smoke: CA mesh across jelcz-a/b/c; optionally probe Streamplace HTTP + catalog.

set -euo pipefail

readonly A="http://127.0.0.1:${JELCZ_A_PORT:-2596}"
readonly B="http://127.0.0.1:${JELCZ_B_PORT:-2597}"
readonly C="http://127.0.0.1:${JELCZ_C_PORT:-2598}"
readonly SP="http://127.0.0.1:${STREAMPLACE_HTTP_PORT:-38080}"

log() { printf '%s\n' "$*"; }
err() { printf 'error: %s\n' "$*" >&2; }

json_field() {
  local json="$1" field="$2"
  python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get(sys.argv[1],""))' "$field" <<<"$json"
}

need_healthy() {
  local url="$1"
  curl -fsS -o /dev/null "$url" || {
    err "not healthy: $url"
    exit 1
  }
}

pull_ok() {
  local from_base="$1" peer_base="$2" cid="$3" label="$4"
  local body status source
  body="$(curl -fsS -X POST \
    -H 'content-type: application/json' \
    -d "{\"cid\":\"${cid}\",\"provider\":\"${peer_base}\",\"did\":\"did:web:jelcz.local\"}" \
    "${from_base}/demo/streamplace/api/pull-peer")"
  status="$(json_field "$body" status)"
  source="$(json_field "$body" peerSource)"
  log "  ${label}: status=${status} peerSource=${source}"
  if [[ "${status}" != "peered-verified" && "${status}" != "already-local" ]]; then
    err "pull failed on ${label}: ${body}"
    exit 1
  fi
}

log "Checking health…"
need_healthy "${A}/_health"
need_healthy "${B}/_health"
need_healthy "${C}/_health"

if curl -fsS -o /dev/null "${SP}/api/healthz" 2>/dev/null \
  || curl -fsS -o /dev/null "${SP}/" 2>/dev/null; then
  log "Streamplace HTTP reachable at ${SP}"
else
  log "warn: Streamplace not reachable at ${SP} (mesh smoke will still run)"
fi

PAYLOAD="$(mktemp)"
trap 'rm -f "${PAYLOAD}" /tmp/jelcz-peer-smoke.bin' EXIT
printf 'streamplace-peership-smoke-%s' "$(date -u +%Y%m%dT%H%M%SZ)" >"${PAYLOAD}"

log "Seeding CA object on jelcz-a…"
SEED_JSON="$(curl -fsS -X POST --data-binary @"${PAYLOAD}" \
  -H 'content-type: application/octet-stream' \
  "${A}/demo/streamplace/api/seed")"
CID="$(json_field "${SEED_JSON}" cid)"
[[ -n "${CID}" ]] || {
  err "seed returned no cid: ${SEED_JSON}"
  exit 1
}
log "  cid=${CID}"

log "Providers on B:"
curl -fsS "${B}/demo/streamplace/api/providers" | python3 -m json.tool

log "B and C pull from A (container DNS uses jelcz-a:2596; host smoke uses published URL)…"
# From host, peers are published ports — provider must be host-reachable.
pull_ok "${B}" "${A}" "${CID}" "B←A"
pull_ok "${C}" "${A}" "${CID}" "C←A"

log "Verify B serves bytes from local CA…"
code="$(curl -s -o /tmp/jelcz-peer-smoke.bin -w '%{http_code}' \
  "${B}/xrpc/place.stream.playback.getVideoBlob?did=did:web:jelcz.local&cid=${CID}")"
[[ "${code}" == "200" ]] || {
  err "B getVideoBlob HTTP ${code}"
  exit 1
}
cmp -s "${PAYLOAD}" /tmp/jelcz-peer-smoke.bin

log "Optional: jelcz-a catalog against Streamplace mirror…"
if cat_json="$(curl -fsS --max-time 45 "${A}/demo/streamplace/api/catalog" 2>/dev/null)"; then
  python3 -c '
import json,sys
d=json.loads(sys.argv[1])
live=len(d.get("live") or [])
vod=len(d.get("vod") or [])
print(f"  catalog: {live} live, {vod} VOD")
stats=d.get("stats") or {}
print(f"  httpsProviders: {stats.get("httpsProviders")}")
' "${cat_json}"
else
  log "  catalog probe skipped/failed (Streamplace may still be warming test stream)"
fi

log ""
log "OK — multi-jelcz HTTPS peership smoke passed"
log "  A UI: ${A}/demo/streamplace"
log "  B UI: ${B}/demo/streamplace"
log "  C UI: ${C}/demo/streamplace"
log "  Streamplace: ${SP}/"
