#!/usr/bin/env bash
set -euo pipefail

root_dir="${1:-.}"
out_dir="${2:-/tmp/objc-test-gap-mapper}"

source_root="$root_dir/ATProtoPDS/Sources"
test_root="$root_dir/ATProtoPDS/Tests"
if [[ ! -d "$source_root" ]]; then
  source_root="$root_dir/Sources"
fi
if [[ ! -d "$test_root" ]]; then
  test_root="$root_dir/Tests"
fi

mkdir -p "$out_dir"

source_files="$out_dir/source_files.txt"
test_files="$out_dir/test_files.txt"
test_basenames="$out_dir/test_basenames.txt"
covered_sources="$out_dir/covered_sources.txt"
uncovered_sources="$out_dir/uncovered_sources.txt"
module_sources="$out_dir/module_sources.txt"
module_uncovered="$out_dir/module_uncovered.txt"

find "$source_root" -type f \( -name '*.m' -o -name '*.mm' \) | sort >"$source_files" || true
find "$test_root" -type f -name '*.m' | sort >"$test_files" || true

while read -r test_file; do
  [[ -z "$test_file" ]] && continue
  base_name="$(basename "$test_file")"
  echo "${base_name%.*}"
done <"$test_files" | sort -u >"$test_basenames"

: >"$covered_sources"
: >"$uncovered_sources"
: >"$module_sources"
: >"$module_uncovered"

while read -r source_file; do
  [[ -z "$source_file" ]] && continue

  source_base="$(basename "$source_file")"
  source_base="${source_base%.*}"
  case "$source_base" in
    main|test_main)
      continue
      ;;
  esac

  rel_path="${source_file#$source_root/}"
  module_name="${rel_path%%/*}"
  echo "$module_name" >>"$module_sources"

  expected_test_1="${source_base}Tests"
  expected_test_2="${source_base}Test"

  if grep -Fxq "$expected_test_1" "$test_basenames" \
    || grep -Fxq "$expected_test_2" "$test_basenames" \
    || grep -Fq "$source_base" "$test_basenames"; then
    echo "$source_file" >>"$covered_sources"
  else
    echo "$source_file" >>"$uncovered_sources"
    echo "$module_name" >>"$module_uncovered"
  fi
done <"$source_files"

summary="$out_dir/summary.md"
{
  echo "# Objective-C Test Gap Map"
  echo
  echo "- Root: $root_dir"
  echo "- Source root: $source_root"
  echo "- Test root: $test_root"
  echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo
  echo "## Counts"
  echo "- Source implementation files: $(wc -l < "$source_files" | tr -d ' ')"
  echo "- Test implementation files: $(wc -l < "$test_files" | tr -d ' ')"
  echo "- Covered source candidates: $(wc -l < "$covered_sources" | tr -d ' ')"
  echo "- Uncovered source candidates: $(wc -l < "$uncovered_sources" | tr -d ' ')"
  echo
  echo "## Top uncovered modules"
  if [[ -s "$module_uncovered" ]]; then
    sort "$module_uncovered" | uniq -c | sort -nr | head -n 15 | awk '{print "- " $2 ": " $1 " uncovered files"}'
  else
    echo "- none"
  fi
  echo
  echo "## First uncovered files"
  if [[ -s "$uncovered_sources" ]]; then
    head -n 40 "$uncovered_sources" | sed 's/^/- /'
  else
    echo "- none"
  fi
  echo
  echo "## Notes"
  echo "- Mapping is heuristic; manually confirm coverage depth."
  echo "- Indirect coverage may exist even without basename match."
} >"$summary"

echo "wrote $summary"
