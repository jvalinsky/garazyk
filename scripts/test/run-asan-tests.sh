#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || (cd "${script_dir}/../.." && pwd))"

echo "Building with AddressSanitizer..."
mkdir -p "${repo_root}/build-asan"
cd "${repo_root}/build-asan"

cmake .. -DCMAKE_BUILD_TYPE=Debug -DENABLE_ASAN=ON
# Bounded parallelism: ASan objects are large and unbounded builds have
# exhausted memory on 16 GB dev machines.
make AllTests -j4

echo "Running tests with ASan..."
# LeakSanitizer is not supported by Apple's ASan runtime; enabling it on
# macOS aborts the binary at startup before any test runs.
if [[ "$(uname -s)" == "Darwin" ]]; then
  export ASAN_OPTIONS="color=always"
else
  export ASAN_OPTIONS="detect_leaks=1:color=always"
fi
# Gated classes stay off pending workstream 01 S5 (76-failure baseline,
# 2026-07-16). Pass --gated=run explicitly to include them.
./tests/AllTests "$@"
