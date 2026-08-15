#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0
#
# Validate the Streamplace peership Compose interpolation contract without
# creating containers or contacting an image registry.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly COMPOSE_FILE="${ROOT}/docker/streamplace-peership/docker-compose.yml"
readonly ENV_EXAMPLE="${ROOT}/docker/streamplace-peership/.env.example"
readonly TEST_STREAMPLACE_IMAGE="example.invalid/streamplace:1.2.3"
readonly TEST_SIDECAR_CAPABILITY="compose-check-sidecar-capability"
# shellcheck source=streamplace_peership_runtime_env.sh
source "${SCRIPT_DIR}/streamplace_peership_runtime_env.sh"

DEFAULT_CONFIG="$(mktemp)"
OVERRIDE_CONFIG="$(mktemp)"
PUBLISH_CONFIG="$(mktemp)"
RUNTIME_TEST_DIR="$(mktemp -d)"
RUNTIME_TEST_FILE="${RUNTIME_TEST_DIR}/runtime.env"
RUNTIME_TEST_TARGET="${RUNTIME_TEST_DIR}/target.env"
trap 'rm -f "${DEFAULT_CONFIG}" "${OVERRIDE_CONFIG}" "${PUBLISH_CONFIG}" "${RUNTIME_TEST_FILE}" "${RUNTIME_TEST_TARGET}"; rmdir "${RUNTIME_TEST_DIR}" 2>/dev/null || true' EXIT

err() { printf 'error: %s\n' "$*" >&2; }

need_cmd() {
  local command_name
  for command_name in "$@"; do
    command -v "${command_name}" >/dev/null 2>&1 || {
      err "missing required command: ${command_name}"
      exit 1
    }
  done
}

assert_contains() {
  local file="$1"
  local expected="$2"
  if ! grep -F -- "${expected}" "${file}" >/dev/null; then
    err "Compose config is missing: ${expected}"
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"
  if grep -F -- "${unexpected}" "${file}" >/dev/null; then
    err "Compose config unexpectedly contains: ${unexpected}"
    exit 1
  fi
}

assert_count() {
  local file="$1"
  local expected="$2"
  local count="$3"
  local actual
  actual="$(grep -Fc -- "${expected}" "${file}")"
  if [[ "${actual}" != "${count}" ]]; then
    err "expected ${count} occurrences of '${expected}', found ${actual}"
    exit 1
  fi
}

need_cmd docker
chmod 700 "${RUNTIME_TEST_DIR}"

TEST_DEMO_TOKEN="$(printf 'a%.0s' {1..64})"
TEST_RUNTIME_SIDECAR="$(printf 'b%.0s' {1..64})"
peership_write_runtime_capabilities "${RUNTIME_TEST_FILE}" \
  "${TEST_DEMO_TOKEN}" "${TEST_RUNTIME_SIDECAR}"
[[ "$(peership_stat_mode "${RUNTIME_TEST_FILE}")" == "600" ]] || {
  err "generated runtime capability file is not mode 600"
  exit 1
}
(
  unset JELCZ_DEMO_API_TOKEN JELCZ_IROH_SIDECAR_CAPABILITY
  peership_load_runtime_capabilities "${RUNTIME_TEST_FILE}"
  [[ "${JELCZ_DEMO_API_TOKEN}" == "${TEST_DEMO_TOKEN}" ]]
  [[ "${JELCZ_IROH_SIDECAR_CAPABILITY}" == "${TEST_RUNTIME_SIDECAR}" ]]
)
mv "${RUNTIME_TEST_FILE}" "${RUNTIME_TEST_TARGET}"
ln -s "${RUNTIME_TEST_TARGET}" "${RUNTIME_TEST_FILE}"
if peership_load_runtime_capabilities "${RUNTIME_TEST_FILE}" >/dev/null 2>&1; then
  err "runtime capability loader accepted a symlink"
  exit 1
fi
rm -f "${RUNTIME_TEST_FILE}"
mv "${RUNTIME_TEST_TARGET}" "${RUNTIME_TEST_FILE}"

# An empty Streamplace image must stop accidental use of `latest` before
# anything is started. The normal configurations below use inert but valid
# image references so config validation never pulls them.
if env STREAMPLACE_IMAGE= JELCZ_DEMO_API_TOKEN=compose-check-token JELCZ_IROH_SIDECAR_CAPABILITY="${TEST_SIDECAR_CAPABILITY}" docker compose --env-file "${ENV_EXAMPLE}" --project-name peership-image-required -f "${COMPOSE_FILE}" config >/dev/null 2>&1; then
  err "Compose accepted unset required image references"
  exit 1
fi

if env STREAMPLACE_IMAGE="${TEST_STREAMPLACE_IMAGE}" JELCZ_DEMO_API_TOKEN=compose-check-token JELCZ_IROH_SIDECAR_CAPABILITY= docker compose --env-file "${ENV_EXAMPLE}" --project-name peership-capability-required -f "${COMPOSE_FILE}" config >/dev/null 2>&1; then
  err "Compose accepted an empty sidecar capability"
  exit 1
fi
if env STREAMPLACE_IMAGE="${TEST_STREAMPLACE_IMAGE}" JELCZ_DEMO_API_TOKEN= JELCZ_IROH_SIDECAR_CAPABILITY="${TEST_SIDECAR_CAPABILITY}" docker compose --env-file "${ENV_EXAMPLE}" --project-name peership-demo-token-required -f "${COMPOSE_FILE}" config >/dev/null 2>&1; then
  err "Compose accepted an empty demo capability"
  exit 1
fi

env JELCZ_DEMO_API_TOKEN=compose-check-token JELCZ_IROH_SIDECAR_CAPABILITY="${TEST_SIDECAR_CAPABILITY}" \
  docker compose --env-file "${ENV_EXAMPLE}" --project-name peership-default-check -f "${COMPOSE_FILE}" config >"${DEFAULT_CONFIG}"

assert_contains "${DEFAULT_CONFIG}" 'name: peership-default-check'
assert_contains "${DEFAULT_CONFIG}" 'host_ip: 127.0.0.1'
assert_contains "${DEFAULT_CONFIG}" 'published: "38080"'
assert_contains "${DEFAULT_CONFIG}" 'published: "1935"'
assert_contains "${DEFAULT_CONFIG}" 'published: "2596"'
assert_contains "${DEFAULT_CONFIG}" 'published: "2597"'
assert_contains "${DEFAULT_CONFIG}" 'published: "2598"'
assert_not_contains "${DEFAULT_CONFIG}" 'published: "17352"'
assert_contains "${DEFAULT_CONFIG}" 'JELCZ_STREAMPLACE_MIRROR_BASE: http://streamplace:38080'
assert_contains "${DEFAULT_CONFIG}" 'JELCZ_PUBLIC_BASE_URL: http://127.0.0.1:2596'
assert_contains "${DEFAULT_CONFIG}" 'SP_WIDE_OPEN: "true"'
assert_count "${DEFAULT_CONFIG}" 'JELCZ_DEMO_API_TOKEN: compose-check-token' 3
assert_count "${DEFAULT_CONFIG}" "JELCZ_IROH_SIDECAR_CAPABILITY: ${TEST_SIDECAR_CAPABILITY}" 6
assert_contains "${DEFAULT_CONFIG}" 'name: peership-default-check_peership'
assert_count "${DEFAULT_CONFIG}" 'name: local-network_local_net' 1
assert_not_contains "${DEFAULT_CONFIG}" ':latest'
assert_contains "${DEFAULT_CONFIG}" 'image: oci.stream.place/streamplace@sha256:d2b79900b03eb6a964961bc9df0423492ea8b83602f7d3c2f4b7c7a66dbf8776'

# The inactive profile must not require FFmpeg, while the profile itself still
# resolves only to a fixed non-floating fallback when inspected directly.
env JELCZ_DEMO_API_TOKEN=compose-check-token JELCZ_IROH_SIDECAR_CAPABILITY="${TEST_SIDECAR_CAPABILITY}" \
  docker compose --env-file "${ENV_EXAMPLE}" --project-name peership-publish-check --profile publish -f "${COMPOSE_FILE}" config >"${PUBLISH_CONFIG}"
assert_contains "${PUBLISH_CONFIG}" 'image: jrottenberg/ffmpeg:7.1-alpine'
assert_not_contains "${PUBLISH_CONFIG}" ':latest'

env \
  STREAMPLACE_IMAGE="${TEST_STREAMPLACE_IMAGE}" \
  GARAZYK_ATPROTO_NET=peership-custom-network \
  LAB_BIND_ADDRESS=127.0.0.2 \
  LAB_PUBLIC_HOST=lab.example.test \
  STREAMPLACE_HTTP_HOST_PORT=38180 \
  STREAMPLACE_HTTP_LISTEN_PORT=38181 \
  STREAMPLACE_RTMP_HOST_PORT=19351 \
  STREAMPLACE_RTMP_LISTEN_PORT=19352 \
  JELCZ_A_HOST_PORT=35196 \
  JELCZ_A_LISTEN_PORT=35197 \
  JELCZ_B_HOST_PORT=35198 \
  JELCZ_B_LISTEN_PORT=35199 \
  JELCZ_C_HOST_PORT=35200 \
  JELCZ_C_LISTEN_PORT=35201 \
  IROH_SIDECAR_PORT=17353 \
  JELCZ_DEMO_API_TOKEN=compose-check-token \
  JELCZ_IROH_SIDECAR_CAPABILITY="${TEST_SIDECAR_CAPABILITY}" \
  JELCZ_ORIGIN_ANNOUNCE=1 \
  JELCZ_ORIGIN_ANNOUNCE_IDENTIFIER=origin-check.test \
  JELCZ_ORIGIN_ANNOUNCE_APP_PASSWORD=origin-check-secret \
  JELCZ_ORIGIN_ANNOUNCE_SERVER_DID=did:example:origin-check \
  docker compose --env-file "${ENV_EXAMPLE}" --project-name peership-overrides-check -f "${COMPOSE_FILE}" config >"${OVERRIDE_CONFIG}"

assert_contains "${OVERRIDE_CONFIG}" 'name: peership-overrides-check'
assert_contains "${OVERRIDE_CONFIG}" 'host_ip: 127.0.0.2'
assert_contains "${OVERRIDE_CONFIG}" 'published: "38180"'
assert_contains "${OVERRIDE_CONFIG}" 'target: 38181'
assert_contains "${OVERRIDE_CONFIG}" 'published: "35196"'
assert_contains "${OVERRIDE_CONFIG}" 'target: 35197'
assert_contains "${OVERRIDE_CONFIG}" 'SP_PUBLIC_HOST: lab.example.test:38180'
assert_contains "${OVERRIDE_CONFIG}" 'JELCZ_STREAMPLACE_MIRROR_BASE: http://streamplace:38181'
assert_contains "${OVERRIDE_CONFIG}" 'JELCZ_PUBLIC_BASE_URL: http://lab.example.test:35196'
assert_contains "${OVERRIDE_CONFIG}" 'JELCZ_IROH_SIDECAR_URL: http://iroh-a:17353'
assert_contains "${OVERRIDE_CONFIG}" 'name: peership-custom-network'
assert_contains "${OVERRIDE_CONFIG}" 'name: peership-overrides-check_peership'
assert_not_contains "${OVERRIDE_CONFIG}" 'published: "17353"'
assert_count "${OVERRIDE_CONFIG}" 'JELCZ_ORIGIN_ANNOUNCE_APP_PASSWORD: origin-check-secret' 1
assert_count "${OVERRIDE_CONFIG}" 'JELCZ_ORIGIN_ANNOUNCE_IDENTIFIER: origin-check.test' 1

printf 'OK — Streamplace peership Compose defaults, overrides, required images, and sidecar isolation validated.\n'
