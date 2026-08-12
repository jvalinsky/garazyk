#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="${ROOT}/build-package-install"
PREFIX="${ROOT}/build-package-prefix"
MOVED="${ROOT}/build-package-prefix-moved"
CONSUMER_BUILD="${ROOT}/build-package-consumer"
CONSUMER_CMAKE_ARGS=()

if [[ "$(uname -s)" == Darwin ]] && command -v brew >/dev/null 2>&1; then
  if OPENSSL_PREFIX="$(brew --prefix openssl@3 2>/dev/null || brew --prefix openssl 2>/dev/null)"; then
    CONSUMER_CMAKE_ARGS+=("-DOPENSSL_ROOT_DIR=${OPENSSL_PREFIX}")
  fi
fi

rm -rf "${BUILD}" "${PREFIX}" "${MOVED}" "${CONSUMER_BUILD}"

cmake -S "${ROOT}" -B "${BUILD}" -DCMAKE_BUILD_TYPE=Debug -DGARAZYK_INSTALL=ON
cmake --build "${BUILD}" --target \
  ATProtoCore ATProtoStorage ATProtoTransport ATProtoServices ATProtoXRPC \
  ATProtoSync ATProtoPLC ATProtoRuntime ATProtoMediaCore ATProtoVideoService \
  ATProtoAdminUI secp256k1 --parallel 4
cmake --install "${BUILD}" --prefix "${PREFIX}"

mv "${PREFIX}" "${MOVED}"

cmake -S "${ROOT}/tests/package-consumers/core-only" -B "${CONSUMER_BUILD}" \
  -DCMAKE_PREFIX_PATH="${MOVED}" "${CONSUMER_CMAKE_ARGS[@]}"
cmake --build "${CONSUMER_BUILD}" --parallel 4
"${CONSUMER_BUILD}/core_consumer"

FULL_BUILD="${ROOT}/build-package-consumer-full"
rm -rf "${FULL_BUILD}"
cmake -S "${ROOT}/tests/package-consumers/full-graph" -B "${FULL_BUILD}" \
  -DCMAKE_PREFIX_PATH="${MOVED}" "${CONSUMER_CMAKE_ARGS[@]}"
cmake --build "${FULL_BUILD}" --parallel 4
"${FULL_BUILD}/full_graph_consumer"

NEG_BUILD="${ROOT}/build-package-consumer-neg"
rm -rf "${NEG_BUILD}"
if cmake -S "${ROOT}/tests/package-consumers/private-header-denied" -B "${NEG_BUILD}" \
  -DCMAKE_PREFIX_PATH="${MOVED}" "${CONSUMER_CMAKE_ARGS[@]}" >/dev/null 2>&1; then
  if cmake --build "${NEG_BUILD}" --parallel 4 >/dev/null 2>&1; then
    echo "expected private-header consumer to fail compile" >&2
    exit 1
  fi
fi

echo "package-consumer-smoke: OK"
