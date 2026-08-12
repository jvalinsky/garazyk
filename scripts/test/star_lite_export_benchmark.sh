#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0
#
# STAR-lite v0 vs CAR export benchmark wrapper.
#
# Usage:
#   ./scripts/test/star_lite_export_benchmark.sh
#   STAR_LITE_BENCH_TARGET_BYTES=100000000 ./scripts/test/star_lite_export_benchmark.sh
#   STAR_LITE_BENCH_QUICK=1 ./scripts/test/star_lite_export_benchmark.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${ROOT}"

if [[ ! -x "${BUILD_DIR:-${ROOT}/build/bin}/kaszlak" ]]; then
  echo "Missing build/bin/kaszlak — configure and build first." >&2
  exit 1
fi

exec deno run -A "${ROOT}/scripts/test/star_lite_export_benchmark.ts" "$@"
