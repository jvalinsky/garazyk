#!/usr/bin/env bash
# JSON wrapper over scripts/run-tests.sh for AI consumption.
# Exits 0 even when tests fail; the caller reads `.status` from the JSON.
# Exits non-zero only if the underlying runner could not be invoked.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || (cd "$script_dir/../.." && pwd))"
runner="$repo_root/scripts/run-tests.sh"

if [[ ! -x "$runner" ]]; then
  jq -n --arg err "runner not found or not executable: $runner" \
    '{status:"error", error:$err}'
  exit 2
fi

log="$(mktemp -t run_tests.XXXXXX)"
trap 'rm -f "$log"' EXIT

start=$(date +%s)
rc=0
"$runner" >"$log" 2>&1 || rc=$?
end=$(date +%s)
duration=$((end - start))

# Heuristic parsing of AllTests output — adapt if the suite output changes.
passed=$(grep -cE '^\[ *PASSED? *\]|^ok ' "$log" || true)
failed=$(grep -cE '^\[ *FAILED *\]|^not ok ' "$log" || true)
failing_raw=$(grep -E '^\[ *FAILED *\]|^not ok ' "$log" || true)
failing=$(printf '%s' "$failing_raw" | jq -Rs 'split("\n")|map(select(length>0))')

status="passed"
if (( rc != 0 )) || (( failed > 0 )); then
  status="failed"
fi

jq -n \
  --arg status "$status" \
  --argjson passed "${passed:-0}" \
  --argjson failed "${failed:-0}" \
  --argjson duration "$duration" \
  --argjson rc "$rc" \
  --argjson failing "$failing" \
  --rawfile log "$log" \
  '{status:$status, passed:$passed, failed:$failed, duration_s:$duration, exit_code:$rc, failing_tests:$failing, log_tail:($log|split("\n")|.[-40:]|join("\n"))}'
