#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

echo "Building with AddressSanitizer..."
mkdir -p "${repo_root}/build-asan"
cd "${repo_root}/build-asan"

cmake .. -DCMAKE_BUILD_TYPE=Debug -DENABLE_ASAN=ON
make AllTests -j$(sysctl -n hw.ncpu 2>/dev/null || echo 4)

echo "Running tests with ASan..."
# ASAN_OPTIONS can be used to tune behavior
export ASAN_OPTIONS="detect_leaks=1:color=always"
./tests/AllTests
