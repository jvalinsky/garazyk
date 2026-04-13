#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="${1:-./build/bin}"

require_binary() {
  local path="$1"
  if [[ ! -x "$path" ]]; then
    echo "[FAIL] Missing executable: $path" >&2
    exit 1
  fi
}

run_capture() {
  local out_file="$1"
  shift
  set +e
  "$@" >"$out_file" 2>&1
  local rc=$?
  set -e
  echo "$rc"
}

require_contains() {
  local file="$1"
  local text="$2"
  if ! grep -Fq "$text" "$file"; then
    echo "[FAIL] Expected output to contain: $text" >&2
    echo "---- output ----" >&2
    sed -n '1,80p' "$file" >&2
    echo "---------------" >&2
    exit 1
  fi
}

require_usage_line() {
  local file="$1"
  local binary_name="$2"
  if ! grep -Eq "Usage: (.+/)?${binary_name} <command>" "$file"; then
    echo "[FAIL] Expected usage line for ${binary_name}" >&2
    echo "---- output ----" >&2
    sed -n '1,80p' "$file" >&2
    echo "---------------" >&2
    exit 1
  fi
}

check_base_help() {
  local binary_name="$1"
  local help_file="$2"
  for cmd in serve status version help; do
    require_contains "$help_file" "$cmd"
  done
  require_usage_line "$help_file" "$binary_name"
}

check_command_contract() {
  local binary_name="$1"
  local binary_path="$2"

  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  local missing_out="$tmp/missing.txt"
  local flags_out="$tmp/flags.txt"
  local help_out="$tmp/help.txt"

  local rc_missing rc_flags rc_help
  rc_missing="$(run_capture "$missing_out" "$binary_path")"
  rc_flags="$(run_capture "$flags_out" "$binary_path" --help)"
  rc_help="$(run_capture "$help_out" "$binary_path" help)"

  if [[ "$rc_missing" -eq 0 ]]; then
    echo "[FAIL] $binary_name bare invocation must fail" >&2
    exit 1
  fi
  if [[ "$rc_flags" -eq 0 ]]; then
    echo "[FAIL] $binary_name flags-before-command must fail" >&2
    exit 1
  fi
  if [[ "$rc_help" -ne 0 ]]; then
    echo "[FAIL] $binary_name help command must succeed" >&2
    exit 1
  fi

  require_usage_line "$missing_out" "$binary_name"
  require_contains "$flags_out" "Flags must follow the command name"
  check_base_help "$binary_name" "$help_out"

  echo "[PASS] $binary_name command contract"
}

check_status_alias() {
  local binary_name="$1"
  local binary_path="$2"
  local alias_name="$3"

  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  local out_file="$tmp/alias.txt"
  local rc
  rc="$(run_capture "$out_file" "$binary_path" "$alias_name")"

  if [[ "$rc" -eq 2 ]]; then
    echo "[FAIL] $binary_name $alias_name parsed as usage error" >&2
    sed -n '1,80p' "$out_file" >&2
    exit 1
  fi
  if grep -Fq "Unknown command" "$out_file"; then
    echo "[FAIL] $binary_name rejected alias '$alias_name'" >&2
    sed -n '1,80p' "$out_file" >&2
    exit 1
  fi

  echo "[PASS] $binary_name alias '$alias_name' accepted"
}

KASZLAK="$BIN_DIR/kaszlak"
CAMPAGNOLA="$BIN_DIR/campagnola"
ZUK="$BIN_DIR/zuk"
SYRENA="$BIN_DIR/syrena"

require_binary "$KASZLAK"
require_binary "$CAMPAGNOLA"
require_binary "$ZUK"
require_binary "$SYRENA"

check_command_contract "kaszlak" "$KASZLAK"
check_command_contract "campagnola" "$CAMPAGNOLA"
check_command_contract "zuk" "$ZUK"
check_command_contract "syrena" "$SYRENA"

check_status_alias "kaszlak" "$KASZLAK" "health"
check_status_alias "campagnola" "$CAMPAGNOLA" "health"

echo "[PASS] CLI command contract checks complete"
