#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0
#
# Opt-in live smoke: fetch one Streamplace getVideoBlob and check MUXL ftyp.
# Not part of default CI. Requires network.
#
# Usage:
#   JELCZ_STREAMPLACE_SMOKE=1 ./scripts/test/streamplace_vod_mirror_smoke.sh
# Optional:
#   STREAMPLACE_BASE=https://stream.place
#   STREAMPLACE_DID=did:web:stream.place
#   STREAMPLACE_CID=<bafkr4i...>

set -euo pipefail

if [[ "${JELCZ_STREAMPLACE_SMOKE:-}" != "1" ]]; then
  echo "Skip: set JELCZ_STREAMPLACE_SMOKE=1 to run live Streamplace VOD smoke"
  exit 0
fi

BASE="${STREAMPLACE_BASE:-https://stream.place}"
DID="${STREAMPLACE_DID:-did:web:stream.place}"
# Public fixture CID from 2026-08-12 probe notes — override if stale.
CID="${STREAMPLACE_CID:-}"

if [[ -z "${CID}" ]]; then
  echo "STREAMPLACE_CID is required for live smoke (BDASL bafkr4i… of a known MUXL object)"
  exit 2
fi

URL="${BASE%/}/xrpc/place.stream.playback.getVideoBlob?did=${DID}&cid=${CID}"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

HTTP_CODE="$(curl -sS -L --max-time 60 -o "$TMP" -w '%{http_code}' \
  -H 'Range: bytes=0-31' \
  "$URL" || true)"

if [[ "$HTTP_CODE" != "200" && "$HTTP_CODE" != "206" ]]; then
  echo "FAIL: HTTP $HTTP_CODE from $URL"
  exit 1
fi

# ftyp at offset 4
FTYP="$(dd if="$TMP" bs=1 skip=4 count=4 2>/dev/null || true)"
if [[ "$FTYP" != "ftyp" ]]; then
  echo "FAIL: expected ftyp box, got: $(xxd -l 16 "$TMP" 2>/dev/null || true)"
  exit 1
fi

echo "OK: Streamplace getVideoBlob Range response contains ftyp ($HTTP_CODE, $(wc -c <"$TMP") bytes)"
