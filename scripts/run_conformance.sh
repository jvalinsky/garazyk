#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH=$PATH:$REPO_ROOT/build/bin

echo "[Conformance] Verifying XRPC Coverage..."
node "${REPO_ROOT}/scripts/generate_xrpc_coverage_report.js" --source-only --fail-on-duplicates

echo "[Conformance] Configuring..."
cmake -S "${REPO_ROOT}" -B "${REPO_ROOT}/build" -DBUILD_TESTS=ON

echo "[Conformance] Building Tests..."
cmake --build "${REPO_ROOT}/build" --target AllTests

echo "[Conformance] Running Tests..."
cd "${REPO_ROOT}/build" && ctest --output-on-failure

echo "[Conformance] SUCCESS"
