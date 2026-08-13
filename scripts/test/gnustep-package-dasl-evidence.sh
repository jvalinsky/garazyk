#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0
#
# Bounded GNUstep evidence for the CMake package consumers and DASL suites.
# Requires Docker. Builds (or reuses) the Dockerfile.gnustep image, installs the
# Garazyk package inside the container, runs package-consumer-smoke, then runs
# focused DASL AllTests filters.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IMAGE="${GARAZYK_GNUSTEP_IMAGE:-garazyk-gnustep-toolchain:local}"
DOCKERFILE="${ROOT}/docker/Dockerfile.gnustep"
TARGET="${GARAZYK_GNUSTEP_DOCKER_TARGET:-toolchain}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required for GNUstep evidence" >&2
  exit 1
fi

if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  echo "Building GNUstep toolchain image ${IMAGE} (target=${TARGET}; this can take a long time)..."
  docker build -f "${DOCKERFILE}" --target "${TARGET}" -t "${IMAGE}" "${ROOT}"
fi

echo "=== GNUstep package-consumer smoke ==="
docker run --rm \
  -v "${ROOT}:/src:ro" \
  -w /tmp/garazyk-work \
  "${IMAGE}" \
  bash -lc '
    set -euo pipefail
    cp -a /src/. .
    # Writable trees for out-of-source package install
    rm -rf build-package-install build-package-prefix build-package-prefix-moved \
           build-package-consumer build-package-consumer-full build-package-consumer-neg
    export GNUSTEP_PREFIX=/usr/GNUstep/Local
    ./scripts/test/package-consumer-smoke.sh
  '

echo "=== GNUstep focused DASL suites ==="
docker run --rm \
  -v "${ROOT}:/src:ro" \
  -w /tmp/garazyk-dasl \
  "${IMAGE}" \
  bash -lc '
    set -euo pipefail
    cp -a /src/. .
    cmake -S . -B build-dasl -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTS=ON \
      -DGNUSTEP_PREFIX=/usr/GNUstep/Local \
      -DCMAKE_OBJC_FLAGS="-I/usr/GNUstep/Local/Library/Headers"
    cmake --build build-dasl --target AllTests --parallel 4
    ./build-dasl/tests/AllTests --filter DASLConformanceTests --gated=run
    ./build-dasl/tests/AllTests --filter ATProtoDagCBOREdgeCaseTests --gated=run
    ./build-dasl/tests/AllTests --filter ATProtoS2PACOSETests --gated=run
    ./build-dasl/tests/AllTests --filter ATProtoS2PALeafCertificateTests --gated=run
    ./build-dasl/tests/AllTests --filter ATProtoS2PAJUMBFTests --gated=run
    ./build-dasl/tests/AllTests --filter ATProtoWebTileTests --gated=run
  '

echo "gnustep-package-dasl-evidence: OK"
