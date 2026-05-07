#!/usr/bin/env bash
# JSON wrapper over scripts/stub_find.sh.
# Emits {status, path, count, files:[{path,line,marker,text}]}.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || (cd "$script_dir/../.." && pwd))"
runner="$repo_root/scripts/stub_find.sh"

path="${1:-.}"

if [[ ! -x "$runner" ]]; then
  jq -n --arg err "runner not found or not executable: $runner" \
    '{status:"error", error:$err}'
  exit 2
fi

log="$(mktemp -t stub_find.XXXXXX)"
trap 'rm -f "$log"' EXIT

rc=0
"$runner" "$path" >"$log" 2>&1 || rc=$?

# ripgrep output: "<path>:<line>:<text>"
matches=$(grep -E ':[0-9]+:' "$log" || true)
findings=$(printf '%s' "$matches" | jq -Rn '
  [inputs
    | select(length > 0)
    | capture("^(?<path>[^:]+):(?<line>[0-9]+):(?<text>.*)$")
    | .line |= tonumber
    | .marker = (
        if (.text|test("FIXME")) then "FIXME"
        elif (.text|test("TODO")) then "TODO"
        elif (.text|test("not implemented")) then "not_implemented"
        elif (.text|test("stub")) then "stub"
        else "other" end
      )
  ]
')

status="clean"
if [[ -n "${findings:-}" && "$findings" != "[]" ]]; then status="findings"; fi
if (( rc == 2 )); then status="error"; fi

jq -n \
  --arg status "$status" \
  --arg path "$path" \
  --argjson rc "$rc" \
  --argjson findings "${findings:-[]}" \
  '{status:$status, path:$path, exit_code:$rc, count:($findings|length), files:$findings}'
