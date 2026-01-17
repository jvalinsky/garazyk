#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."
BUILD_DIR="${PROJECT_DIR}/build"
BUILD_TYPE="${BUILD_TYPE:-Debug}"

echo "Configuring build (${BUILD_TYPE})..."
cmake -S "${PROJECT_DIR}" -B "${BUILD_DIR}" -DCMAKE_BUILD_TYPE="${BUILD_TYPE}"

echo "Building demo binaries..."
cmake --build "${BUILD_DIR}" --target atproto-plc september

echo "Starting demo..."
"${SCRIPT_DIR}/run_demo.sh"
