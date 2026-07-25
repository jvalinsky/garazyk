#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
cd "$ROOT"

failures=0

search_matches() {
  local pattern="$1"
  shift
  if command -v rg >/dev/null 2>&1; then
    rg -n "$pattern" "$@"
  else
    grep -R -n -E -- "$pattern" "$@"
  fi
}

check_no_matches() {
  local description="$1"
  local pattern="$2"
  shift 2

  echo "==> ${description}"
  local output
  local result
  output="$(mktemp)"
  if search_matches "$pattern" "$@" >"$output"; then
    cat "$output"
    rm -f "$output"
    echo "FAIL: ${description}"
    failures=$((failures + 1))
  else
    result=$?
    rm -f "$output"
    if [[ "$result" -eq 1 ]]; then
      echo "PASS: ${description}"
    else
      echo "FAIL: ${description} (search command failed)"
      failures=$((failures + 1))
    fi
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
  line="$(awk -v module="$module" '
    $0 ~ ("target_link_libraries\\(" module " PUBLIC ") { print; exit }
  ' CMakeLists.txt)"
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
  "PLC module does not import App runtime types" \
  '#import "App/(PDS|ATProtoApplication|ATProtoServiceContainer)' \
  Garazyk/Sources/PLC

echo "==> Module public dependency DAG checks"

allowed_links_for_module() {
  case "$1" in
    ATProtoCore) echo "" ;;
    ATProtoStorage|ATProtoTransport) echo "ATProtoCore" ;;
    ATProtoServices) echo "ATProtoStorage ATProtoCore" ;;
    ATProtoSync) echo "ATProtoStorage ATProtoTransport ATProtoCore" ;;
    ATProtoXRPC) echo "ATProtoServices ATProtoStorage ATProtoTransport ATProtoSync ATProtoCore" ;;
    ATProtoPLC) echo "ATProtoTransport ATProtoCore" ;;
    ATProtoVideoService) echo "ATProtoMediaCore ATProtoStorage ATProtoCore ATProtoTransport" ;;
    ATProtoRuntime) echo "ATProtoPLC ATProtoServices ATProtoTransport ATProtoXRPC ATProtoSync ATProtoCore ATProtoVideoService" ;;
    *) echo "" ;;
  esac
}

module_rank_for() {
  case "$1" in
    ATProtoCore) echo 1 ;;
    ATProtoStorage|ATProtoTransport) echo 2 ;;
    ATProtoServices|ATProtoSync|ATProtoPLC|ATProtoMediaCore) echo 3 ;;
    ATProtoXRPC|ATProtoVideoService) echo 4 ;;
    ATProtoRuntime) echo 5 ;;
    *) echo 0 ;;
  esac
}

modules=(
  ATProtoCore
  ATProtoStorage
  ATProtoServices
  ATProtoTransport
  ATProtoSync
  ATProtoXRPC
  ATProtoPLC
  ATProtoVideoService
  ATProtoRuntime
)

for module in "${modules[@]}"; do
  observed="$(extract_public_module_links "$module")"
  observed_arr=()
  read -r -a observed_arr <<<"$observed"
  allowed_arr=()
  read -r -a allowed_arr <<<"$(allowed_links_for_module "$module")"
  for dep in "${observed_arr[@]:-}"; do
    if [[ "$dep" != ATProto* ]]; then
      continue
    fi
    if ! contains_word "$dep" "${allowed_arr[@]:-}"; then
      echo "FAIL: ${module} links disallowed module dependency: ${dep}"
      failures=$((failures + 1))
    fi

    module_rank_value="$(module_rank_for "$module")"
    dep_rank_value="$(module_rank_for "$dep")"
    if [[ "$dep_rank_value" -ge "$module_rank_value" ]]; then
      echo "FAIL: ${module} links reverse/lateral dependency ${dep} (rank ${module_rank_value} -> ${dep_rank_value})"
      failures=$((failures + 1))
    fi

    dep_observed="$(extract_public_module_links "$dep")"
    dep_observed_arr=()
    read -r -a dep_observed_arr <<<"$dep_observed"
    if contains_word "$module" "${dep_observed_arr[@]:-}"; then
      echo "FAIL: direct reverse dependency cycle detected between ${module} and ${dep}"
      failures=$((failures + 1))
    fi
  done
done

echo "==> Executable link surface checks"

expected_links_for_executable() {
  case "$1" in
    kaszlak) echo "ATProtoAppViewServer ATProtoRuntime ATProtoVideoService ATProtoServices ATProtoTransport ATProtoXRPC ATProtoSync ATProtoStorage ATProtoPLC ATProtoCore" ;;
    campagnola) echo "ATProtoAppViewServer ATProtoPLC ATProtoTransport ATProtoCore ATProtoRuntime ATProtoServices" ;;
    zuk) echo "ATProtoAppViewServer ATProtoSync ATProtoTransport ATProtoCore ATProtoRuntime ATProtoServices ATProtoStorage" ;;
    *) echo "" ;;
  esac
}

for exe in kaszlak campagnola zuk; do
  observed="$(extract_private_executable_links "$exe")"
  observed_arr=()
  read -r -a observed_arr <<<"$observed"
  expected_arr=()
  read -r -a expected_arr <<<"$(expected_links_for_executable "$exe")"

  observed_mods=()
  for dep in "${observed_arr[@]:-}"; do
    if [[ "$dep" == ATProto* ]]; then
      observed_mods+=("$dep")
    fi
  done

  for dep in "${expected_arr[@]}"; do
    if ! contains_word "$dep" "${observed_mods[@]:-}"; then
      echo "FAIL: ${exe} missing expected module dependency ${dep}"
      failures=$((failures + 1))
    fi
  done

  for dep in "${observed_mods[@]:-}"; do
    if ! contains_word "$dep" "${expected_arr[@]:-}"; then
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
