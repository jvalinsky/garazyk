#!/usr/bin/env bash
# Dispatcher for the objc-architecture-audit skill.
# Runs all scan_*.sh scripts and writes a combined summary.md.
#
# Usage: run_architecture_audit.sh [root_dir] [out_dir]

set -euo pipefail

root_dir="${1:-.}"
out_dir="${2:-/tmp/objc-architecture-audit}"
scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$out_dir"

scans=(
  scan_gnustep_regressions
  scan_service_boundaries
  scan_xrpc_contracts
  scan_parser_hardening
  scan_firehose_backpressure
  scan_network_timeout_retry
  scan_oauth_dpop_conformance
  scan_dos
  scan_sqlite_invariants
  map_test_gaps
)

for name in "${scans[@]}"; do
  sub_out="$out_dir/$name"
  mkdir -p "$sub_out"
  echo "[architecture-audit] running $name -> $sub_out"
  "$scripts_dir/$name.sh" "$root_dir" "$sub_out"
done

summary="$out_dir/summary.md"
{
  echo "# Objective-C Architecture & Reliability Audit — Combined Summary"
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
