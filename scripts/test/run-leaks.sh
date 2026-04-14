#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || (cd "${script_dir}/../.." && pwd))"
test_binary="${repo_root}/build/tests/AllTests"

if [[ ! -x "${test_binary}" ]]; then
    echo "Test binary not found at: ${test_binary}"
    echo "Building project first..."
    mkdir -p "${repo_root}/build"
    cd "${repo_root}/build"
    cmake .. -DCMAKE_BUILD_TYPE=Debug
    make AllTests -j$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
fi

echo "Running tests with MallocStackLogging enabled..."
export MallocStackLogging=1
export PDS_LOG_LEVEL=error # Reduce noise

# Run tests in background
"${test_binary}" &
test_pid=$!

echo "Started AllTests with PID: ${test_pid}"
echo "Running leaks every 5 seconds (Press Ctrl+C to stop)..."

# Monitor leaks while process is running
while kill -0 $test_pid 2>/dev/null; do
    leaks $test_pid || true
    sleep 5
done

echo "Tests finished. Final leak check..."
leaks $test_pid || true

unset MallocStackLogging
