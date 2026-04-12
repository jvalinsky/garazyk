#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."
BUILD_DIR="${PROJECT_DIR}/build"
BUILD_TYPE="${BUILD_TYPE:-Debug}"

echo "Cleaning previous build cache..."
rm -rf "${BUILD_DIR}"

echo "Configuring build (${BUILD_TYPE})..."
# Explicitly use system clang to bypass 'swiftly' circular proxy issues
export CC=/usr/bin/clang
export CXX=/usr/bin/clang++
export OBJC=/usr/bin/clang
cmake -S "${PROJECT_DIR}" -B "${BUILD_DIR}" \
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
    -DCMAKE_C_COMPILER=/usr/bin/clang \
    -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
    -DCMAKE_OBJC_COMPILER=/usr/bin/clang

echo "Building demo binaries..."
cmake --build "${BUILD_DIR}" --target campagnola kaszlak



echo "Starting demo..."
"${SCRIPT_DIR}/run_demo.sh"
