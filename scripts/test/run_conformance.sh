#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/../.." && pwd))"
export PATH=$PATH:$REPO_ROOT/build/bin

echo "[Conformance] Verifying XRPC Coverage..."
node "${REPO_ROOT}/scripts/docs/generate_xrpc_coverage_report.cjs" --source-only --fail-on-duplicates

echo "[Conformance] Configuring..."
cmake -S "${REPO_ROOT}" -B "${REPO_ROOT}/build" -DBUILD_TESTS=ON

echo "[Conformance] Building Tests..."
cmake --build "${REPO_ROOT}/build" --target AllTests

echo "[Conformance] Running Tests..."
cd "${REPO_ROOT}/build" && ctest --output-on-failure

echo "[Conformance] SUCCESS"
