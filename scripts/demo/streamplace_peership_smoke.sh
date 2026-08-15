#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0
#
# Smoke: independent bridge-network HTTP and iroh CA transfers across jelcz-a/b/c.

set -euo pipefail

readonly PUBLIC_HOST="${LAB_PUBLIC_HOST:-127.0.0.1}"
readonly A="http://${PUBLIC_HOST}:${JELCZ_A_HOST_PORT:-2596}"
readonly B="http://${PUBLIC_HOST}:${JELCZ_B_HOST_PORT:-2597}"
readonly C="http://${PUBLIC_HOST}:${JELCZ_C_HOST_PORT:-2598}"
readonly SP="http://${PUBLIC_HOST}:${STREAMPLACE_HTTP_HOST_PORT:-38080}"
# Provider URLs as seen from inside the jelcz containers (compose service DNS).
# Host-published ${A}/${B}/${C} are for curl from the host; 127.0.0.1 inside a
# container is that container itself, so pull-peer must use jelcz-a/b/c.
readonly A_PEER="${JELCZ_A_PEER_URL:-http://jelcz-a:${JELCZ_A_LISTEN_PORT:-2596}}"
readonly B_PEER="${JELCZ_B_PEER_URL:-http://jelcz-b:${JELCZ_B_LISTEN_PORT:-2597}}"
readonly C_PEER="${JELCZ_C_PEER_URL:-http://jelcz-c:${JELCZ_C_LISTEN_PORT:-2598}}"
readonly DEMO_API_TOKEN="${JELCZ_DEMO_API_TOKEN:-}"

log() { printf '%s\n' "$*"; }
err() { printf 'error: %s\n' "$*" >&2; }

# The Compose wrapper normally provides this capability.  Keep the smoke
# compatible with a standalone, intentionally unauthenticated demo.
demo_mutation_curl() {
  if [[ -n "${DEMO_API_TOKEN}" ]]; then
    curl -H "Authorization: Bearer ${DEMO_API_TOKEN}" "$@"
  else
    curl "$@"
  fi
}

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

pull_transport_ok() {
  local from_base="$1" peer_base="$2" cid="$3" expected_source="$4" label="$5"
  local body status source verified
  body="$(demo_mutation_curl -fsS -X POST \
    -H 'content-type: application/json' \
    -d "{\"cid\":\"${cid}\",\"provider\":\"${peer_base}\",\"did\":\"did:web:jelcz.local\"}" \
    "${from_base}/demo/streamplace/api/pull-peer")"
  status="$(json_field "$body" status)"
  source="$(json_field "$body" peerSource)"
  verified="$(json_field "$body" blake3Verified)"
  log "  ${label}: status=${status} peerSource=${source} blake3Verified=${verified}"
  if [[ "${status}" != "peered-verified" || "${source}" != "${expected_source}" || "${verified}" != "True" ]]; then
    err "transport assertion failed on ${label}: ${body}"
    exit 1
  fi
}

assert_mutation_capability() {
  [[ -n "${DEMO_API_TOKEN}" ]] || return 0
  local body_file code body
  body_file="$(mktemp)"
  code="$(curl -sS -o "${body_file}" -w '%{http_code}' -X POST \
    --data-binary 'capability-negative-seed' \
    -H 'content-type: application/octet-stream' \
    "${A}/demo/streamplace/api/seed?fanout=0")"
  body="$(<"${body_file}")"
  [[ "${code}" == "401" ]] || { rm -f "${body_file}"; err "missing capability returned HTTP ${code}: ${body}"; exit 1; }
  code="$(curl -sS -o "${body_file}" -w '%{http_code}' -X POST \
    -H 'Authorization: Bearer wrong-demo-capability' \
    -H 'content-type: application/octet-stream' \
    --data-binary 'capability-negative-seed' \
    "${A}/demo/streamplace/api/seed?fanout=0")"
  body="$(<"${body_file}")"
  rm -f "${body_file}"
  [[ "${code}" == "403" ]] || { err "wrong capability returned HTTP ${code}: ${body}"; exit 1; }
  log "  mutation capability rejects missing (401) and wrong (403) tokens"
}

assert_unconfigured_provider_rejected() {
  local base="$1" cid="$2" body_file code body error
  body_file="$(mktemp)"
  code="$(demo_mutation_curl -sS -o "${body_file}" -w '%{http_code}' -X POST \
    -H 'content-type: application/json' \
    -d "{\"cid\":\"${cid}\",\"provider\":\"http://127.0.0.1:1\",\"did\":\"did:web:jelcz.local\"}" \
    "${base}/demo/streamplace/api/pull-peer")"
  body="$(<"${body_file}")"
  rm -f "${body_file}"
  error="$(json_field "${body}" error)"
  if [[ "${code}" != "403" || "${error}" != "ProviderNotAllowed" ]]; then
    err "unconfigured provider was not rejected: HTTP ${code} ${body}"
    exit 1
  fi
  log "  unconfigured provider rejected before egress (HTTP 403)"
}

assert_destination_miss() {
  local base="$1" cid="$2" label="$3" miss_file
  miss_file="$(mktemp)"
  local code
  code="$(curl -sS -o "${miss_file}" -w '%{http_code}' \
    "${base}/xrpc/place.stream.playback.getVideoBlob?did=did:web:jelcz.local&cid=${cid}")"
  rm -f "${miss_file}"
  if [[ "${code}" != "404" ]]; then
    err "destination was not empty before ${label}: getVideoBlob HTTP ${code} for ${cid}"
    exit 1
  fi
  log "  ${label}: destination miss confirmed (HTTP 404)"
}

assert_local_bytes() {
  local base="$1" cid="$2" expected="$3" output="$4" label="$5"
  local code
  code="$(curl -sS -o "${output}" -w '%{http_code}' \
    "${base}/xrpc/place.stream.playback.getVideoBlob?did=did:web:jelcz.local&cid=${cid}")"
  [[ "${code}" == "200" ]] || {
    err "${label} getVideoBlob HTTP ${code}"
    exit 1
  }
  cmp -s "${expected}" "${output}" || {
    err "${label} local bytes differ from seeded bytes"
    exit 1
  }
  log "  ${label}: local byte equality confirmed"
}

log "Checking health…"
need_healthy "${A}/_health"
need_healthy "${B}/_health"
need_healthy "${C}/_health"
assert_mutation_capability

if curl -fsS -o /dev/null "${SP}/api/healthz" 2>/dev/null \
  || curl -fsS -o /dev/null "${SP}/" 2>/dev/null; then
  log "Streamplace HTTP reachable at ${SP}"
else
  log "warn: Streamplace not reachable at ${SP} (mesh smoke will still run)"
fi

HTTP_PAYLOAD="$(mktemp)"
IROH_PAYLOAD="$(mktemp)"
HTTP_OUTPUT="$(mktemp)"
IROH_OUTPUT="$(mktemp)"
trap 'rm -f "${HTTP_PAYLOAD}" "${IROH_PAYLOAD}" "${HTTP_OUTPUT}" "${IROH_OUTPUT}"' EXIT
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
printf 'streamplace-peership-smoke-http-%s' "${RUN_ID}" >"${HTTP_PAYLOAD}"
printf 'streamplace-peership-smoke-iroh-%s' "${RUN_ID}" >"${IROH_PAYLOAD}"

log "Seeding HTTP assertion object on jelcz-a (demo fanout disabled)…"
HTTP_SEED_JSON="$(demo_mutation_curl -fsS -X POST --data-binary @"${HTTP_PAYLOAD}" \
  -H 'content-type: application/octet-stream' \
  "${A}/demo/streamplace/api/seed?fanout=0")"
HTTP_CID="$(json_field "${HTTP_SEED_JSON}" cid)"
[[ -n "${HTTP_CID}" ]] || {
  err "HTTP seed returned no cid: ${HTTP_SEED_JSON}"
  exit 1
}
[[ "$(json_field "${HTTP_SEED_JSON}" meshFanoutSuppressed)" == "True" ]] || {
  err "HTTP seed did not suppress mesh fanout: ${HTTP_SEED_JSON}"
  exit 1
}
log "  HTTP CID=${HTTP_CID}"

log "Providers on B:"
curl -fsS "${B}/demo/streamplace/api/providers" | python3 -m json.tool

log "HTTP assertion: B must miss first, then pull from A's HTTP endpoint…"
assert_destination_miss "${B}" "${HTTP_CID}" "B←A (HTTP)"
assert_unconfigured_provider_rejected "${B}" "${HTTP_CID}"
assert_destination_miss "${B}" "${HTTP_CID}" "B←unconfigured provider"
pull_transport_ok "${B}" "${A_PEER}" "${HTTP_CID}" "http-peer" "B←A (HTTP)"
assert_local_bytes "${B}" "${HTTP_CID}" "${HTTP_PAYLOAD}" "${HTTP_OUTPUT}" "B←A (HTTP)"

log "Seeding separate iroh assertion object on jelcz-a (demo fanout disabled)…"
IROH_SEED_JSON="$(demo_mutation_curl -fsS -X POST --data-binary @"${IROH_PAYLOAD}" \
  -H 'content-type: application/octet-stream' \
  "${A}/demo/streamplace/api/seed?fanout=0")"
IROH_CID="$(json_field "${IROH_SEED_JSON}" cid)"
IROH_PROVIDER="$(json_field "${IROH_SEED_JSON}" irohProvider)"
IROH_OFFERED="$(json_field "${IROH_SEED_JSON}" irohOffered)"
[[ -n "${IROH_CID}" && "${IROH_OFFERED}" == "True" && "${IROH_PROVIDER}" == iroh://* ]] || {
  err "iroh seed was not offered by the sidecar: ${IROH_SEED_JSON}"
  exit 1
}
[[ "$(json_field "${IROH_SEED_JSON}" meshFanoutSuppressed)" == "True" ]] || {
  err "iroh seed did not suppress mesh fanout: ${IROH_SEED_JSON}"
  exit 1
}
log "  iroh CID=${IROH_CID} provider=${IROH_PROVIDER}"

log "iroh assertion: C must miss first, then fetch through its sidecar…"
assert_destination_miss "${C}" "${IROH_CID}" "C←A (iroh)"
pull_transport_ok "${C}" "${IROH_PROVIDER}" "${IROH_CID}" "iroh-peer" "C←A (iroh)"
assert_local_bytes "${C}" "${IROH_CID}" "${IROH_PAYLOAD}" "${IROH_OUTPUT}" "C←A (iroh)"

log "Mesh topology on B:"
curl -fsS "${B}/demo/streamplace/api/mesh" | python3 -m json.tool | head -n 40

log "Optional: jelcz-a catalog against Streamplace mirror…"
if cat_json="$(curl -fsS --max-time 45 "${A}/demo/streamplace/api/catalog" 2>/dev/null)"; then
  python3 -c '
import json,sys
d=json.loads(sys.argv[1])
live=len(d.get("live") or [])
vod=len(d.get("vod") or [])
print("  catalog: %d live, %d VOD" % (live, vod))
stats=d.get("stats") or {}
print("  httpsProviders: %s" % (stats.get("httpsProviders"),))
' "${cat_json}"
else
  log "  catalog probe skipped/failed (Streamplace may still be warming test stream)"
fi

log ""
log "OK — independent HTTP and iroh peership assertions passed"
log "  A UI: ${A}/demo/streamplace"
log "  B UI: ${B}/demo/streamplace"
log "  C UI: ${C}/demo/streamplace"
log "  Streamplace: ${SP}/"
