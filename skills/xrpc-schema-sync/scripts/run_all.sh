#!/usr/bin/env bash
set -euo pipefail

root="."
output_dir="reports"
ignore_file=""
scope_file=""
fail_on_duplicates=0

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
    --fail-on-duplicates)
      fail_on_duplicates=1
      shift
      ;;
    *)
      root="$1"
      shift
      ;;
  esac
done

mkdir -p "$output_dir"

scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_coverage_script="$root/scripts/generate_xrpc_coverage_report.js"
repo_next_steps_script="$root/scripts/generate_xrpc_next_steps.js"

if [[ -f "$repo_coverage_script" && -f "$repo_next_steps_script" ]]; then
  coverage_cmd=(node "$repo_coverage_script" --source-only)
  if [[ "$fail_on_duplicates" -eq 1 ]]; then
    coverage_cmd+=(--fail-on-duplicates)
  fi
  if [[ -n "$scope_file" ]]; then
    coverage_cmd+=(--scope-file "$scope_file")
  fi

  (cd "$root" && "${coverage_cmd[@]}")
  (cd "$root" && node "$repo_next_steps_script")

  cp "$root/reports/xrpc_coverage.json" "$output_dir/xrpc_coverage.json"
  cp "$root/reports/xrpc_coverage.md" "$output_dir/xrpc_coverage.md"
  cp "$root/reports/xrpc_next_steps_plan.md" "$output_dir/xrpc_next_steps_plan.md"
  cp "$root/reports/xrpc_issue_candidates.md" "$output_dir/xrpc_issue_candidates.md"

  echo "Wrote $output_dir/xrpc_coverage.json, $output_dir/xrpc_coverage.md, $output_dir/xrpc_next_steps_plan.md, $output_dir/xrpc_issue_candidates.md"
  exit 0
fi

methods_tsv="$output_dir/methods.tsv"
lexicons_tsv="$output_dir/lexicons.tsv"

"$scripts_dir/list_xrpc_methods.py" "$root" --output "$methods_tsv"
"$scripts_dir/list_xrpc_methods.py" "$root" --json > "$output_dir/methods.json"

"$scripts_dir/parse_lexicons.py" "$root" --output "$lexicons_tsv"
"$scripts_dir/parse_lexicons.py" "$root" --json > "$output_dir/lexicons.json"

"$scripts_dir/diff_methods.py" \
  --methods "$methods_tsv" \
  --lexicons "$lexicons_tsv" \
  ${ignore_file:+--ignore-file "$ignore_file"} \
  --json > "$output_dir/diff.json"

echo "Wrote $output_dir/methods.json, $output_dir/lexicons.json, $output_dir/diff.json"
