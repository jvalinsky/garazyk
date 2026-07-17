#!/bin/bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || (cd "${script_dir}/../.." && pwd))"
test_binary="${repo_root}/build/tests/AllTests"

if [[ ! -x "${test_binary}" ]]; then
echo "Test binary not found at: ${test_binary}"
echo "Build it first with: cmake --build build --target AllTests -j4"
exit 1
fi

echo "Running all tests..."
"${script_dir}/check_ui_design_system.sh"
# Gated classes stay off pending workstream 01 S5: a measured 2026-07-16
# baseline shows 76 failures across 11 gated classes, failing in isolation
# too. Pass --gated=run explicitly to include them.
"${test_binary}" "$@"
echo "Tests complete."
