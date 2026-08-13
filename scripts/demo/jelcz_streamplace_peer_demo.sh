#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0
#
# Launch jelcz with the Streamplace peership demo UI.
# Browser: http://127.0.0.1:2586/demo/streamplace
#
# Discovery talks to Streamplace; media playback goes through jelcz
# (CA store for small BDASL objects, Range-proxy for large MUXL archives).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

JELCZ_BIN="${JELCZ_BIN:-$ROOT/build/bin/jelcz}"
if [[ ! -x "$JELCZ_BIN" ]]; then
  echo "Building jelcz…"
  cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug
  cmake --build build --target jelcz --parallel 4
fi

DATA_DIR="${JELCZ_DEMO_DATA_DIR:-$ROOT/build/jelcz-streamplace-demo-data}"
mkdir -p "$DATA_DIR"

export JELCZ_PORT="${JELCZ_PORT:-2586}"
export JELCZ_DATA_DIR="$DATA_DIR"
export JELCZ_STREAMPLACE_MIRROR_BASE="${JELCZ_STREAMPLACE_MIRROR_BASE:-https://stream.place}"
export JELCZ_STREAMPLACE_ATTRIBUTION_DID="${JELCZ_STREAMPLACE_ATTRIBUTION_DID:-did:web:stream.place}"
export JELCZ_CA_MIRROR_FETCH=1
export JELCZ_STREAMPLACE_SERVE_COMPAT=1
export JELCZ_STREAMPLACE_DEMO=1
export JELCZ_DEMO_UI_PATH="$ROOT/Garazyk/Resources/jelcz-demo/streamplace-peer.html"

echo "jelcz Streamplace peership demo"
echo "  binary:  $JELCZ_BIN"
echo "  data:    $DATA_DIR"
echo "  upstream:$JELCZ_STREAMPLACE_MIRROR_BASE"
echo "  UI:      http://127.0.0.1:${JELCZ_PORT}/demo/streamplace"
echo

exec "$JELCZ_BIN" serve --data-dir "$DATA_DIR" --port "$JELCZ_PORT"
