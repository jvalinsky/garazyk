#!/bin/bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
test_binary="${repo_root}/build/tests/AllTests"

if [[ ! -x "${test_binary}" ]]; then
echo "Test binary not found at: ${test_binary}"
echo "Build it first with: xcodebuild -scheme AllTests build"
exit 1
fi

echo "Running all tests..."
"${test_binary}" "$@"
echo "Tests complete."
