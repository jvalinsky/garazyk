#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0

# Safe reader/writer for the generated Streamplace peership capability file.
# This file is sourced by the demo scripts; it does not execute on its own.

peership_runtime_err() {
  printf 'error: %s\n' "$*" >&2
}

peership_stat_mode() {
  local path="$1"
  if stat -f '%Lp' "${path}" >/dev/null 2>&1; then
    stat -f '%Lp' "${path}"
  else
    stat -c '%a' "${path}"
  fi
}

peership_validate_runtime_parent() {
  local parent="$1"
  local mode
  if [[ ! -d "${parent}" || ! -O "${parent}" ]]; then
    peership_runtime_err "runtime capability directory must be owned by the current user: ${parent}"
    return 1
  fi
  mode="$(peership_stat_mode "${parent}")" || return 1
  if (( (8#${mode} & 8#022) != 0 )); then
    peership_runtime_err "runtime capability directory must not be group/world writable: ${parent}"
    return 1
  fi
}

peership_load_runtime_capabilities() {
  local path="$1"
  local parent mode line value
  local runtime_demo_token=""
  local runtime_sidecar_capability=""

  parent="$(dirname "${path}")"
  peership_validate_runtime_parent "${parent}" || return 1
  if [[ -L "${path}" || ! -f "${path}" || ! -O "${path}" ]]; then
    peership_runtime_err "runtime capability file must be an owned regular file, not a symlink: ${path}"
    return 1
  fi
  mode="$(peership_stat_mode "${path}")" || return 1
  if [[ "${mode}" != "600" ]]; then
    peership_runtime_err "runtime capability file must have mode 600: ${path}"
    return 1
  fi

  while IFS= read -r line || [[ -n "${line}" ]]; do
    case "${line}" in
      JELCZ_DEMO_API_TOKEN=*)
        [[ -z "${runtime_demo_token}" ]] || {
          peership_runtime_err "duplicate JELCZ_DEMO_API_TOKEN in ${path}"
          return 1
        }
        value="${line#JELCZ_DEMO_API_TOKEN=}"
        [[ "${value}" =~ ^[0-9a-f]{64}$ ]] || {
          peership_runtime_err "invalid JELCZ_DEMO_API_TOKEN in ${path}"
          return 1
        }
        runtime_demo_token="${value}"
        ;;
      JELCZ_IROH_SIDECAR_CAPABILITY=*)
        [[ -z "${runtime_sidecar_capability}" ]] || {
          peership_runtime_err "duplicate JELCZ_IROH_SIDECAR_CAPABILITY in ${path}"
          return 1
        }
        value="${line#JELCZ_IROH_SIDECAR_CAPABILITY=}"
        [[ "${value}" =~ ^[0-9a-f]{64}$ ]] || {
          peership_runtime_err "invalid JELCZ_IROH_SIDECAR_CAPABILITY in ${path}"
          return 1
        }
        runtime_sidecar_capability="${value}"
        ;;
      *)
        peership_runtime_err "unexpected runtime capability record in ${path}"
        return 1
        ;;
    esac
  done <"${path}"

  if [[ -z "${runtime_demo_token}" || -z "${runtime_sidecar_capability}" ]]; then
    peership_runtime_err "runtime capability file is incomplete: ${path}"
    return 1
  fi
  if [[ -z "${JELCZ_DEMO_API_TOKEN:-}" ]]; then
    JELCZ_DEMO_API_TOKEN="${runtime_demo_token}"
  fi
  if [[ -z "${JELCZ_IROH_SIDECAR_CAPABILITY:-}" ]]; then
    JELCZ_IROH_SIDECAR_CAPABILITY="${runtime_sidecar_capability}"
  fi
  export JELCZ_DEMO_API_TOKEN JELCZ_IROH_SIDECAR_CAPABILITY
}

peership_write_runtime_capabilities() {
  local path="$1"
  local demo_token="$2"
  local sidecar_capability="$3"
  local parent temporary

  [[ "${demo_token}" =~ ^[0-9a-f]{64}$ ]] || {
    peership_runtime_err "refusing to persist an invalid demo capability"
    return 1
  }
  [[ "${sidecar_capability}" =~ ^[0-9a-f]{64}$ ]] || {
    peership_runtime_err "refusing to persist an invalid sidecar capability"
    return 1
  }
  parent="$(dirname "${path}")"
  peership_validate_runtime_parent "${parent}" || return 1
  temporary="$(mktemp "${path}.tmp.XXXXXX")" || return 1
  if ! (
    umask 077
    {
      printf 'JELCZ_DEMO_API_TOKEN=%s\n' "${demo_token}"
      printf 'JELCZ_IROH_SIDECAR_CAPABILITY=%s\n' "${sidecar_capability}"
    } >"${temporary}"
    chmod 600 "${temporary}"
  ); then
    rm -f "${temporary}"
    return 1
  fi
  mv -f "${temporary}" "${path}"
}
