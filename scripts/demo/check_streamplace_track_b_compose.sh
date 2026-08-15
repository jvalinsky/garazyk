#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0
#
# Static contract check for the opt-in Streamplace Track B profile.  It does
# not create containers, pull images, or make an iroh transfer.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly BASE_COMPOSE="${ROOT}/docker/streamplace-peership/docker-compose.yml"
readonly TRACK_B_COMPOSE="${ROOT}/docker/streamplace-peership/docker-compose.track-b.yml"
readonly BASE_ENV="${ROOT}/docker/streamplace-peership/.env.example"
readonly TRACK_B_ENV="${ROOT}/docker/streamplace-peership/track-b.env.example"
readonly EXPECTED_REVISION="5ba597dbedda8f2fdb84b815ee633301212f5f51"

output="$(mktemp)"
trap 'rm -f "${output}"' EXIT

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'error: missing required command: %s\n' "$1" >&2
    exit 1
  }
}

assert_contains() {
  grep -F -- "$2" "$1" >/dev/null || {
    printf 'error: Compose config is missing: %s\n' "$2" >&2
    exit 1
  }
}

assert_not_contains() {
  if grep -F -- "$2" "$1" >/dev/null; then
    printf 'error: Compose config unexpectedly contains: %s\n' "$2" >&2
    exit 1
  fi
}

assert_not_matches() {
  if grep -E -- "$2" "$1" >/dev/null; then
    printf 'error: Compose config unexpectedly matches: %s\n' "$2" >&2
    exit 1
  fi
}

service_image() {
  awk -v service="$2" '
    $0 == "  " service ":" { in_service = 1; next }
    in_service && /^  [^[:space:]][^:]*:$/ { exit }
    in_service && /^    image: / {
      sub(/^    image: /, "")
      gsub(/^"|"$/, "")
      print
      exit
    }
  ' "$1"
}

is_digest_pinned_image() {
  [[ "$1" =~ ^[^[:space:]@]+@sha256:[[:xdigit:]]{64}$ ]]
}

assert_digest_pinned_image() {
  local service="$1"
  local config="$2"
  local image
  image="$(service_image "${config}" "${service}")"
  if ! is_digest_pinned_image "${image}"; then
    printf 'error: %s image is not pinned to a SHA-256 digest: %s\n' \
      "${service}" "${image:-<missing>}" >&2
    exit 1
  fi
}

assert_rejects_unpinned_image() {
  local label="$1"
  local image="$2"
  if is_digest_pinned_image "${image}"; then
    printf 'error: negative digest check unexpectedly accepted %s: %s\n' \
      "${label}" "${image}" >&2
    exit 1
  fi
}

need_cmd docker

# All three Track B images and the actual publisher DID are mandatory.
if env STREAMPLACE_TRACK_B_IMAGE= STREAMPLACE_TRACK_B_PUBLISHER_IMAGE= \
  JELCZ_STREAMPLACE_TRACK_B_BRIDGE_IMAGE= STREAMPLACE_TRACK_B_STREAMER_DID= \
  STREAMPLACE_TRACK_B_BRIDGE_TOKEN= \
  JELCZ_DEMO_API_TOKEN=compose-check-token \
  JELCZ_IROH_SIDECAR_CAPABILITY=compose-check-sidecar-capability \
  docker compose --env-file "${BASE_ENV}" --env-file "${TRACK_B_ENV}" \
    -f "${BASE_COMPOSE}" -f "${TRACK_B_COMPOSE}" --profile track-b config >/dev/null 2>&1; then
  printf 'error: Track B Compose accepted missing required image/DID inputs\n' >&2
  exit 1
fi

env \
  STREAMPLACE_TRACK_B_IMAGE=example.invalid/streamplace@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  STREAMPLACE_TRACK_B_PUBLISHER_IMAGE=example.invalid/ffmpeg@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
  JELCZ_STREAMPLACE_TRACK_B_BRIDGE_IMAGE=example.invalid/track-b-bridge@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc \
  STREAMPLACE_TRACK_B_STREAMER_DID=did:plc:trackbstreamer \
  STREAMPLACE_TRACK_B_BRIDGE_TOKEN=compose-track-b-capability \
  JELCZ_DEMO_API_TOKEN=compose-check-token \
  JELCZ_IROH_SIDECAR_CAPABILITY=compose-check-sidecar-capability \
  docker compose --env-file "${BASE_ENV}" --env-file "${TRACK_B_ENV}" \
    --project-name peership-track-b-check -f "${BASE_COMPOSE}" \
    -f "${TRACK_B_COMPOSE}" --profile track-b config >"${output}"

assert_contains "${output}" "com.garazyk.streamplace.source-revision: ${EXPECTED_REVISION}"
assert_contains "${output}" "SP_NO_FIREHOSE: \"false\""
assert_contains "${output}" "--alpn"
assert_contains "${output}" "/iroh/streamplace/1"
assert_contains "${output}" "STREAMPLACE_TRACK_B_REPORT_CONTRACT: streamplace-track-b/v1"
assert_contains "${output}" "JELCZ_P2P_ALLOWED_STREAMERS: did:plc:trackbstreamer"
assert_contains "${output}" "JELCZ_STREAMPLACE_IROH_BRIDGE_TOKEN: compose-track-b-capability"
assert_contains "${output}" "JELCZ_STREAMPLACE_IROH_BRIDGE_URL: http://streamplace-track-b-bridge:17353"
assert_contains "${output}" "JELCZ_STREAMPLACE_IROH_BRIDGE_TRUST_LAN: \"1\""
assert_contains "${output}" "JELCZ_P2P: \"0\""
assert_contains "${output}" "JELCZ_IROH_SIDECAR_URL: \"\""
assert_contains "${output}" "JELCZ_IROH_PEER_SIDECARS: \"\""
assert_contains "${output}" "--bind-all"
assert_contains "${output}" "no-new-privileges:true"
assert_contains "${output}" "read_only: true"
assert_contains "${output}" "mode=1777"
assert_contains "${output}" "streamplace-track-b-publisher"
assert_contains "${output}" "streamplace-track-b-bridge"
assert_contains "${output}" "streamplace-track-b-fault-wrong-streamer"
assert_contains "${output}" "streamplace-track-b-fault-wrong-alpn"
assert_contains "${output}" "streamplace-track-b-fault-wrong-from"
assert_contains "${output}" "streamplace-track-b-fault-corrupt"
assert_contains "${output}" "streamplace-track-b-fault-oversize"
assert_contains "${output}" "streamplace-track-b-fault-drop-subscribe"
assert_contains "${output}" "wrong-streamer"
assert_contains "${output}" "wrong-alpn"
assert_contains "${output}" "wrong-from"
assert_contains "${output}" "corrupt-muxl"
assert_contains "${output}" "oversize-segment"
assert_contains "${output}" "drop-subscribe"
assert_contains "${output}" "Dockerfile.streamplace-iroh-bridge"
assert_not_contains "${output}" "published: \"17402\""
assert_not_contains "${output}" "target: 17402"

# Docker Compose itself accepts tag references. The Track B checker is the
# fail-closed contract boundary: all three acceptance images must resolve to a
# full SHA-256 digest, including the publisher and the independent bridge.
assert_digest_pinned_image "streamplace" "${output}"
assert_digest_pinned_image "streamplace-track-b-publisher" "${output}"
assert_digest_pinned_image "streamplace-track-b-bridge" "${output}"
assert_rejects_unpinned_image "publisher tag" "example.invalid/ffmpeg:7.1"
assert_rejects_unpinned_image "bridge tag" "example.invalid/track-b-bridge:1.0"

# The rendered Track B profile must not include any Track A sidecar service.
assert_not_matches "${output}" '^  iroh-a:'
assert_not_matches "${output}" '^  iroh-b:'
assert_not_matches "${output}" '^  iroh-c:'

printf 'OK — Track B profile requires pinned inputs, private bridge/fault peers, firehose, consent, and Streamplace ALPN contract.\n'
