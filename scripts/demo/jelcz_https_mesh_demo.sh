#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0
#
# WS16 Phase 2 — two local jelcz nodes, HTTPS mesh without iroh.
# Node A seeds a BLAKE3 object; node B pulls it via getVideoBlob into its CA.
#
# Usage: ./scripts/demo/jelcz_https_mesh_demo.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

JELCZ_BIN="${JELCZ_BIN:-$ROOT/build/bin/jelcz}"
if [[ ! -x "$JELCZ_BIN" ]]; then
  echo "Building jelcz…"
  cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug
  cmake --build build --target jelcz --parallel 4
fi

PORT_A="${JELCZ_MESH_PORT_A:-2586}"
PORT_B="${JELCZ_MESH_PORT_B:-2587}"
DATA_A="${JELCZ_MESH_DATA_A:-$ROOT/build/jelcz-mesh-a}"
DATA_B="${JELCZ_MESH_DATA_B:-$ROOT/build/jelcz-mesh-b}"
mkdir -p "$DATA_A" "$DATA_B"

pkill -f "$JELCZ_BIN serve --port $PORT_A" 2>/dev/null || true
pkill -f "$JELCZ_BIN serve --port $PORT_B" 2>/dev/null || true
sleep 1

common_env() {
  export JELCZ_STREAMPLACE_MIRROR_BASE="${JELCZ_STREAMPLACE_MIRROR_BASE:-https://stream.place}"
  export JELCZ_STREAMPLACE_ATTRIBUTION_DID="${JELCZ_STREAMPLACE_ATTRIBUTION_DID:-did:web:stream.place}"
  export JELCZ_CA_MIRROR_FETCH=1
  export JELCZ_STREAMPLACE_SERVE_COMPAT=1
  export JELCZ_STREAMPLACE_DEMO=1
  export JELCZ_DEMO_UI_PATH="$ROOT/Garazyk/Resources/jelcz-demo/streamplace-peer.html"
  # Deny auto-ingest of firehose origins unless explicitly allowed (* for lab).
  export JELCZ_P2P_ALLOWED_STREAMERS="${JELCZ_P2P_ALLOWED_STREAMERS:-}"
  export JELCZ_P2P_ALLOWED_BROADCASTERS="${JELCZ_P2P_ALLOWED_BROADCASTERS:-}"
}

start_node() {
  local port="$1" data="$2"
  shift 2
  (
    common_env
    export JELCZ_PORT="$port"
    export JELCZ_DATA_DIR="$data"
    # Extra KEY=value pairs for this node.
    while [[ $# -gt 0 ]]; do
      export "$1"
      shift
    done
    exec "$JELCZ_BIN" serve --port "$port" --data-dir "$data"
  ) &
}

echo "Starting jelcz A on :$PORT_A (seed)…"
start_node "$PORT_A" "$DATA_A"

echo "Starting jelcz B on :$PORT_B (pull from A)…"
start_node "$PORT_B" "$DATA_B" \
  "JELCZ_PEER_HTTPS_PROVIDERS=http://127.0.0.1:${PORT_A}"

wait_http() {
  local url="$1" name="$2"
  for _ in $(seq 1 40); do
    if curl -sf -o /dev/null "$url"; then
      echo "  $name ready"
      return 0
    fi
    sleep 0.25
  done
  echo "timeout waiting for $name at $url" >&2
  exit 1
}

wait_http "http://127.0.0.1:${PORT_A}/demo/streamplace/api/stats" "A"
wait_http "http://127.0.0.1:${PORT_B}/demo/streamplace/api/stats" "B"

PAYLOAD="$(mktemp)"
printf 'jelcz-https-mesh-demo-%s' "$(date +%s)" >"$PAYLOAD"

echo "Seeding object on A…"
SEED_JSON="$(curl -sf -X POST --data-binary @"$PAYLOAD" \
  -H 'content-type: application/octet-stream' \
  "http://127.0.0.1:${PORT_A}/demo/streamplace/api/seed")"
CID="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["cid"])' <<<"$SEED_JSON")"
echo "  cid=$CID"

echo "Providers on B:"
curl -sf "http://127.0.0.1:${PORT_B}/demo/streamplace/api/providers" | python3 -m json.tool

echo "B pulling cid from A over HTTPS…"
PULL_JSON="$(curl -sf -X POST \
  -H 'content-type: application/json' \
  -d "{\"cid\":\"$CID\",\"provider\":\"http://127.0.0.1:${PORT_A}\",\"did\":\"did:web:jelcz.local\"}" \
  "http://127.0.0.1:${PORT_B}/demo/streamplace/api/pull-peer")"
echo "$PULL_JSON" | python3 -m json.tool

STATUS="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' <<<"$PULL_JSON")"
SOURCE="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("peerSource",""))' <<<"$PULL_JSON")"
if [[ "$STATUS" != "peered-verified" && "$STATUS" != "already-local" ]]; then
  echo "mesh pull failed: status=$STATUS" >&2
  exit 1
fi
if [[ "$SOURCE" != "https-peer" && "$SOURCE" != "ca-store" ]]; then
  echo "unexpected peerSource=$SOURCE" >&2
  exit 1
fi

echo "Local serve from B CA…"
HTTP_CODE="$(curl -s -o /tmp/jelcz-mesh-blob.bin -w '%{http_code}' \
  "http://127.0.0.1:${PORT_B}/xrpc/place.stream.playback.getVideoBlob?did=did:web:jelcz.local&cid=${CID}")"
if [[ "$HTTP_CODE" != "200" ]]; then
  echo "B getVideoBlob returned $HTTP_CODE" >&2
  exit 1
fi
cmp -s "$PAYLOAD" /tmp/jelcz-mesh-blob.bin

rm -f "$PAYLOAD" /tmp/jelcz-mesh-blob.bin
echo
echo "OK — HTTPS mesh: A seeded → B peered-verified → B served from local CA"
echo "  A UI: http://127.0.0.1:${PORT_A}/demo/streamplace"
echo "  B UI: http://127.0.0.1:${PORT_B}/demo/streamplace"
echo "  (nodes left running; pkill jelcz to stop)"
