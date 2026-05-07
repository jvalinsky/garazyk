#!/usr/bin/env bash
# JSON wrapper over scripts/quality_gate.sh.
# Emits {status, duration_s, checks:[{name, status}], failed_checks:[...]}.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || (cd "$script_dir/../.." && pwd))"
runner="$repo_root/scripts/quality_gate.sh"

if [[ ! -x "$runner" ]]; then
  jq -n --arg err "runner not found or not executable: $runner" \
    '{status:"error", error:$err}'
  exit 2
fi

log="$(mktemp -t quality_gate.XXXXXX)"
trap 'rm -f "$log"' EXIT

start=$(date +%s)
rc=0
"$runner" >"$log" 2>&1 || rc=$?
end=$(date +%s)
duration=$((end - start))

# quality_gate.sh logs "[INFO] Running <name>" and "[ERROR] <name> ..." / "[INFO] All quality checks passed".
checks=$(
  awk '
    /\[INFO\] Running / { sub(/.*\[INFO\] Running /, ""); printf "{\"name\":\"%s\",\"status\":\"ran\"}\n", $0 }
    /\[INFO\] .* passed/ { sub(/.*\[INFO\] /, ""); printf "{\"name\":\"%s\",\"status\":\"passed\"}\n", $0 }
    /\[ERROR\] / { sub(/.*\[ERROR\] /, ""); printf "{\"name\":\"%s\",\"status\":\"failed\"}\n", $0 }
  ' "$log" | jq -s '.'
)

failed_raw=$(grep -oE 'Failed checks: [A-Za-z0-9_, -]+' "$log" | sed 's/^Failed checks: //' | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)
failed_checks=$(printf '%s' "$failed_raw" | jq -Rs 'split("\n")|map(select(length>0))')

status="passed"
if (( rc != 0 )); then status="failed"; fi

jq -n \
  --arg status "$status" \
  --argjson rc "$rc" \
  --argjson duration "$duration" \
  --argjson checks "${checks:-[]}" \
  --argjson failed_checks "${failed_checks:-[]}" \
  --rawfile log "$log" \
  '{status:$status, exit_code:$rc, duration_s:$duration, checks:$checks, failed_checks:$failed_checks, log_tail:($log|split("\n")|.[-40:]|join("\n"))}'
