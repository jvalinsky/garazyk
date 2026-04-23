#!/usr/bin/env bash
# Dispatcher for the objc-concurrency-audit skill.
# Runs all scan_*.sh scripts and writes a combined summary.md.
#
# Usage: run_concurrency_audit.sh [root_dir] [out_dir]

set -euo pipefail

root_dir="${1:-.}"
out_dir="${2:-/tmp/objc-concurrency-audit}"
scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$out_dir"

scans=(scan_concurrency_patterns scan_locking_queue_contracts scan_reentrancy_patterns)

for name in "${scans[@]}"; do
  sub_out="$out_dir/$name"
  mkdir -p "$sub_out"
  echo "[concurrency-audit] running $name -> $sub_out"
  "$scripts_dir/$name.sh" "$root_dir" "$sub_out"
done

summary="$out_dir/summary.md"
{
  echo "# Objective-C Concurrency Audit — Combined Summary"
  echo
  echo "- Root: $root_dir"
  echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo
  for name in "${scans[@]}"; do
    sub_summary="$out_dir/$name/summary.md"
    echo "## $name"
    if [[ -s "$sub_summary" ]]; then
      sed 's/^# /### /' "$sub_summary"
    else
      echo "_no summary produced_"
    fi
    echo
  done
} >"$summary"

echo "wrote $summary"
