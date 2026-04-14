#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
cd "$ROOT"

failures=0

check_no_matches() {
  local description="$1"
  local pattern="$2"
  shift 2

  echo "==> ${description}"
  if rg -n "$pattern" "$@" >/tmp/pds_boundary_check_hits.txt; then
    cat /tmp/pds_boundary_check_hits.txt
    echo "FAIL: ${description}"
    failures=$((failures + 1))
  else
    echo "PASS: ${description}"
  fi
}

contains_word() {
  local needle="$1"
  shift
  for value in "$@"; do
    if [[ "$value" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

extract_public_module_links() {
  local module="$1"
  local line
  line="$(rg -No "target_link_libraries\\(${module} PUBLIC ([^)]+)\\)" CMakeLists.txt | head -n1 || true)"
  if [[ -z "$line" ]]; then
    echo ""
    return
  fi

  line="${line#target_link_libraries(${module} PUBLIC }"
  line="${line%)}"
  # shellcheck disable=SC2086
  echo $line
}

extract_private_executable_links() {
  local executable="$1"
  awk -v exe="$executable" '
    $0 ~ ("^[[:space:]]*target_link_libraries\\(" exe "[[:space:]]+PRIVATE") { in_block=1; next }
    in_block && $0 ~ /^[[:space:]]*\)/ { exit }
    in_block {
      line=$0
      sub(/#.*/, "", line)
      print line
    }
  ' CMakeLists.txt | tr '\n' ' '
}

echo "Running module boundary checks from: $ROOT"

check_no_matches \
  "No relative include paths in runtime/framework code" \
  '#import "\\.\\./' \
  Garazyk/Sources Garazyk/Frameworks

check_no_matches \
  "No ambiguous legacy service import paths for app services" \
  '#import "Services/(PDSAccountService|PDSRecordService|PDSBlobService|PDSRepositoryService|PDSRelayService)\\.h"' \
  Garazyk/Sources

check_no_matches \
  "Sync module does not import App/*" \
  '#import "App/' \
  Garazyk/Sources/Sync

check_no_matches \
  "PLC module does not import App/*" \
  '#import "App/' \
  Garazyk/Sources/PLC

echo "==> Module public dependency DAG checks"
declare -A allowed
allowed["ATProtoCore"]=""
allowed["ATProtoStorage"]="ATProtoCore"
allowed["ATProtoServices"]="ATProtoStorage ATProtoCore"
allowed["ATProtoTransport"]="ATProtoCore"
allowed["ATProtoSync"]="ATProtoStorage ATProtoTransport ATProtoCore"
allowed["ATProtoXRPC"]="ATProtoServices ATProtoStorage ATProtoTransport ATProtoSync ATProtoCore"
allowed["ATProtoPLC"]="ATProtoTransport ATProtoCore"
allowed["ATProtoRuntime"]="ATProtoServices ATProtoTransport ATProtoXRPC ATProtoSync ATProtoCore"

modules=(
  ATProtoCore
  ATProtoStorage
  ATProtoServices
  ATProtoTransport
  ATProtoSync
  ATProtoXRPC
  ATProtoPLC
  ATProtoRuntime
)

declare -A module_rank=(
  [ATProtoCore]=1
  [ATProtoStorage]=2
  [ATProtoTransport]=2
  [ATProtoServices]=3
  [ATProtoSync]=3
  [ATProtoPLC]=3
  [ATProtoXRPC]=4
  [ATProtoRuntime]=5
)

for module in "${modules[@]}"; do
  observed="$(extract_public_module_links "$module")"
  read -r -a observed_arr <<<"$observed"
  read -r -a allowed_arr <<<"${allowed[$module]}"
  for dep in "${observed_arr[@]}"; do
    if [[ "$dep" != ATProto* ]]; then
      continue
    fi
    if ! contains_word "$dep" "${allowed_arr[@]}"; then
      echo "FAIL: ${module} links disallowed module dependency: ${dep}"
      failures=$((failures + 1))
    fi

    module_rank_value="${module_rank[$module]:-0}"
    dep_rank_value="${module_rank[$dep]:-0}"
    if [[ "$dep_rank_value" -ge "$module_rank_value" ]]; then
      echo "FAIL: ${module} links reverse/lateral dependency ${dep} (rank ${module_rank_value} -> ${dep_rank_value})"
      failures=$((failures + 1))
    fi

    dep_observed="$(extract_public_module_links "$dep")"
    read -r -a dep_observed_arr <<<"$dep_observed"
    if contains_word "$module" "${dep_observed_arr[@]}"; then
      echo "FAIL: direct reverse dependency cycle detected between ${module} and ${dep}"
      failures=$((failures + 1))
    fi
  done
done

echo "==> Executable link surface checks"
declare -A expected_exec_links
expected_exec_links["kaszlak"]="ATProtoRuntime ATProtoServices ATProtoTransport ATProtoXRPC ATProtoSync ATProtoStorage ATProtoCore"
expected_exec_links["campagnola"]="ATProtoPLC ATProtoTransport ATProtoCore"
expected_exec_links["zuk"]="ATProtoSync ATProtoTransport ATProtoCore"

for exe in kaszlak campagnola zuk; do
  observed="$(extract_private_executable_links "$exe")"
  read -r -a observed_arr <<<"$observed"
  read -r -a expected_arr <<<"${expected_exec_links[$exe]}"

  declare -A observed_mods=()
  for dep in "${observed_arr[@]}"; do
    if [[ "$dep" == ATProto* ]]; then
      observed_mods["$dep"]=1
    fi
  done

  for dep in "${expected_arr[@]}"; do
    if [[ -z "${observed_mods[$dep]:-}" ]]; then
      echo "FAIL: ${exe} missing expected module dependency ${dep}"
      failures=$((failures + 1))
    fi
  done

  for dep in "${!observed_mods[@]}"; do
    if ! contains_word "$dep" "${expected_arr[@]}"; then
      echo "FAIL: ${exe} has unexpected module dependency ${dep}"
      failures=$((failures + 1))
    fi
  done
done

if [[ "$failures" -ne 0 ]]; then
  echo "Boundary checks failed (${failures} issue(s))."
  exit 1
fi

echo "Boundary checks passed."
