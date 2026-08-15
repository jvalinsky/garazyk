#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0
#
# Sidecar IPC smoke (offer + fetch). Does not start jelcz.
# Full jelcz lab wiring also needs:
#   JELCZ_P2P=1 JELCZ_CA_MIRROR_FETCH=1 JELCZ_IROH_SIDECAR_URL=http://127.0.0.1:PORT
#   JELCZ_IROH_PROVIDER_ENDPOINT_ID=… (+ optional ticket)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SIDECAR_DIR="${ROOT}/tools/jelcz-iroh-blobs-sidecar"
PORT="${JELCZ_IROH_SIDECAR_PORT:-17352}"
BASE_URL="http://127.0.0.1:${PORT}"
FIXTURE_CID="bafkr4iadewxtddpf7wzglzmsoxbm4gqkmq6n3hieephctfxj5ht2n4b43e"
PAYLOAD="hello-ca-store"
OUT="$(mktemp)"
PID=""
SIDECAR_CAPABILITY="${JELCZ_IROH_SIDECAR_CAPABILITY:-}"

if [[ -z "${SIDECAR_CAPABILITY}" ]]; then
  command -v openssl >/dev/null 2>&1 || {
    echo "error: openssl is required to generate JELCZ_IROH_SIDECAR_CAPABILITY" >&2
    exit 1
  }
  SIDECAR_CAPABILITY="$(openssl rand -hex 32)"
fi
export JELCZ_IROH_SIDECAR_CAPABILITY="${SIDECAR_CAPABILITY}"

cleanup() {
  if [[ -n "${PID}" ]] && kill -0 "${PID}" 2>/dev/null; then
    kill "${PID}" 2>/dev/null || true
    wait "${PID}" 2>/dev/null || true
  fi
  rm -f "${OUT}"
}
trap cleanup EXIT

echo "==> building sidecar"
cargo build --manifest-path "${SIDECAR_DIR}/Cargo.toml" --quiet

echo "==> starting sidecar on ${BASE_URL}"
cargo run --manifest-path "${SIDECAR_DIR}/Cargo.toml" --quiet -- \
  --listen "127.0.0.1:${PORT}" &
PID=$!
for _ in $(seq 1 50); do
  if curl -fsS "${BASE_URL}/v1/health" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
curl -fsS "${BASE_URL}/v1/health" | grep -q '"status":"ok"'

echo "==> offer fixture payload"
OFFER_JSON="$(curl -fsS -X POST "${BASE_URL}/v1/offer" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${SIDECAR_CAPABILITY}" \
  -d "{\"payload_utf8\":\"${PAYLOAD}\"}")"
ENDPOINT_ID="$(printf '%s' "${OFFER_JSON}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["endpointId"])')"
TICKET="$(printf '%s' "${OFFER_JSON}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["endpointTicket"])')"

echo "==> fetch via IPC"
curl -fsS -X POST "${BASE_URL}/v1/fetch" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${SIDECAR_CAPABILITY}" \
  -d "{\"cid\":\"${FIXTURE_CID}\",\"provider\":{\"endpointId\":\"${ENDPOINT_ID}\",\"endpointTicket\":\"${TICKET}\"}}" \
  -o "${OUT}"
if [[ "$(cat "${OUT}")" != "${PAYLOAD}" ]]; then
  echo "FAIL: fetched payload mismatch" >&2
  exit 1
fi

echo "PASS: iroh sidecar IPC offer/fetch smoke (${BASE_URL})"
