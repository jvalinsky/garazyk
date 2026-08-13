#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0
#
# Publish a synthetic RTMP test pattern to the lab Streamplace node.
# Prefer: ./scripts/demo/streamplace_peership_up.sh --publish
# This script is for host-side ffmpeg when the compose profile is not used.

set -euo pipefail

RTMP_URL="${STREAMPLACE_RTMP_URL:-rtmp://127.0.0.1:1935/live/garazyk-demo}"

if ! command -v ffmpeg >/dev/null 2>&1; then
  printf 'error: ffmpeg not found on PATH\n' >&2
  exit 1
fi

printf 'Publishing to %s (Ctrl-C to stop)\n' "${RTMP_URL}"
exec ffmpeg -re \
  -f lavfi -i "testsrc=size=1280x720:rate=30" \
  -f lavfi -i "sine=frequency=880:sample_rate=44100" \
  -c:v libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p \
  -c:a aac -b:a 128k -shortest \
  -f flv "${RTMP_URL}"
