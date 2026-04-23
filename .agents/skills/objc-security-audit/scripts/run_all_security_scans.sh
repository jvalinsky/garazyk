#!/usr/bin/env bash
# Dispatcher for the objc-security-audit skill.
# Runs all four scan_*.sh scripts and writes a combined summary.md.
#
# Usage: run_all_security_scans.sh [root_dir] [out_dir]
#   root_dir  path to repository root (default: .)
#   out_dir   directory for per-scan outputs (default: /tmp/objc-security-audit)

set -euo pipefail

root_dir="${1:-.}"
out_dir="${2:-/tmp/objc-security-audit}"
scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$out_dir"

scans=(scan_sql_injection scan_crypto scan_secrets scan_log_redaction)

for name in "${scans[@]}"; do
  sub_out="$out_dir/$name"
  mkdir -p "$sub_out"
  echo "[security-audit] running $name -> $sub_out"
  "$scripts_dir/$name.sh" "$root_dir" "$sub_out"
done

summary="$out_dir/summary.md"
{
  echo "# Objective-C Security Audit — Combined Summary"
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
