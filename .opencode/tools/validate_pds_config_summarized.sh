#!/usr/bin/env bash
# JSON wrapper over scripts/validate_pds_config.sh.
# Emits {status, config_path, issues:[{severity,key,message}]}.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || (cd "$script_dir/../.." && pwd))"
runner="$repo_root/scripts/validate_pds_config.sh"

config_path="${1:-docker/pds/config.json}"

if [[ ! -x "$runner" ]]; then
  jq -n --arg err "runner not found or not executable: $runner" \
    '{status:"error", error:$err}'
  exit 2
fi

log="$(mktemp -t validate_pds.XXXXXX)"
trap 'rm -f "$log"' EXIT

rc=0
"$runner" "$config_path" >"$log" 2>&1 || rc=$?

# Lines look like: "FAIL: key expected 'x', got 'y'" or "PASS: key is 'z'".
issues=$(
  awk '
    /^FAIL: /   { sub(/^FAIL: /, "");   printf "{\"severity\":\"fail\",\"message\":\"%s\"}\n", $0 }
    /^Error: /  { sub(/^Error: /, "");  printf "{\"severity\":\"error\",\"message\":\"%s\"}\n", $0 }
  ' "$log" | jq -s '[.[] | . + {key: (.message|split(" ")|.[0])}]'
)

status="pass"
if (( rc != 0 )); then status="fail"; fi

jq -n \
  --arg status "$status" \
  --arg config_path "$config_path" \
  --argjson rc "$rc" \
  --argjson issues "${issues:-[]}" \
  --rawfile log "$log" \
  '{status:$status, config_path:$config_path, exit_code:$rc, issues:$issues, log:$log}'
