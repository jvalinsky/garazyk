#!/usr/bin/env bash
set -euo pipefail

root="."
output_dir="reports"
ignore_file=""
scope_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      output_dir="$2"
      shift 2
      ;;
    --ignore-file)
      ignore_file="$2"
      shift 2
      ;;
    --scope-file)
      scope_file="$2"
      shift 2
      ;;
    *)
      root="$1"
      shift
      ;;
  esac
done

mkdir -p "$output_dir"

scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_stub_script="$root/scripts/stub_find.sh"
repo_coverage_script="$root/scripts/generate_xrpc_coverage_report.js"
repo_next_steps_script="$root/scripts/generate_xrpc_next_steps.js"

"$scripts_dir/find_stubs.sh" "$root" --json ${ignore_file:+--ignore-file "$ignore_file"} > "$output_dir/stubs.json"
"$scripts_dir/map_endpoints.py" "$root" --json > "$output_dir/methods.json"

if [[ -f "$repo_stub_script" && -f "$repo_coverage_script" && -f "$repo_next_steps_script" ]]; then
  (cd "$root" && "$repo_stub_script" ATProtoPDS/Sources >/dev/null 2>&1 || true)

  coverage_cmd=(node "$repo_coverage_script" --source-only)
  if [[ -n "$scope_file" ]]; then
    coverage_cmd+=(--scope-file "$scope_file")
  fi
  (cd "$root" && "${coverage_cmd[@]}")
  (cd "$root" && node "$repo_next_steps_script")

  if [[ -f "$root/reports/stub_scan_raw/stubs.json" ]]; then
    cp "$root/reports/stub_scan_raw/stubs.json" "$output_dir/repo_stub_scan.json"
  fi
  if [[ -f "$root/reports/xrpc_coverage.json" ]]; then
    cp "$root/reports/xrpc_coverage.json" "$output_dir/xrpc_coverage.json"
  fi
  if [[ -f "$root/reports/xrpc_coverage.md" ]]; then
    cp "$root/reports/xrpc_coverage.md" "$output_dir/xrpc_coverage.md"
  fi
  if [[ -f "$root/reports/xrpc_next_steps_plan.md" ]]; then
    cp "$root/reports/xrpc_next_steps_plan.md" "$output_dir/xrpc_next_steps_plan.md"
  fi
  if [[ -f "$root/reports/xrpc_issue_candidates.md" ]]; then
    cp "$root/reports/xrpc_issue_candidates.md" "$output_dir/xrpc_issue_candidates.md"
  fi
fi

echo "Wrote $output_dir/stubs.json and $output_dir/methods.json"
