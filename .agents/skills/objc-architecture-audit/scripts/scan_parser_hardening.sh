#!/usr/bin/env bash
set -euo pipefail

root_dir="${1:-.}"
out_dir="${2:-/tmp/objc-parser-hardening-audit}"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: rg is required but not installed" >&2
  exit 1
fi

mkdir -p "$out_dir"

scan_paths=()
if [[ -d "$root_dir/Garazyk/Sources/Repository" ]]; then
  scan_paths+=("$root_dir/Garazyk/Sources/Repository")
fi
if [[ -d "$root_dir/Garazyk/Sources/Core" ]]; then
  scan_paths+=("$root_dir/Garazyk/Sources/Core")
fi
if [[ ${#scan_paths[@]} -eq 0 ]]; then
  scan_paths+=("$root_dir")
fi

parse_hits="$out_dir/parse_hits.txt"
risky_hits="$out_dir/risky_hits.txt"
bounds_hits="$out_dir/bounds_hits.txt"
integer_hits="$out_dir/integer_hits.txt"

rg -n --glob '*.{m,mm,h}' \
  -e '\bparse\b' \
  -e '\bdecode\b' \
  -e '\bdeserialize\b' \
  -e 'fromData' \
  -e 'read[A-Z]' \
  "${scan_paths[@]}" >"$parse_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e '\bmemcpy\b' \
  -e '\bmemmove\b' \
  -e 'getBytes' \
  -e 'subdataWithRange' \
  -e '\bbytes\b' \
  -e '\bNSRange\b' \
  "${scan_paths[@]}" >"$risky_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e '\blength\b' \
  -e '\boffset\b' \
  -e '\bremaining\b' \
  -e 'NSMaxRange' \
  -e '\brange\.location\b' \
  -e '\brange\.length\b' \
  "${scan_paths[@]}" >"$bounds_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'uint(8|16|32|64)_t' \
  -e 'NSUInteger' \
  -e 'NSInteger' \
  -e 'size_t' \
  -e 'htonl|ntohl|htobe|be64toh' \
  "${scan_paths[@]}" >"$integer_hits" || true

cut -d: -f1 "$parse_hits" | sort -u >"$out_dir/parse_files.txt"
cut -d: -f1 "$risky_hits" | sort -u >"$out_dir/risky_files.txt"
cut -d: -f1 "$bounds_hits" | sort -u >"$out_dir/bounds_files.txt"

comm -12 "$out_dir/parse_files.txt" "$out_dir/risky_files.txt" >"$out_dir/parse_and_risky_files.txt"
comm -23 "$out_dir/parse_and_risky_files.txt" "$out_dir/bounds_files.txt" >"$out_dir/parse_risky_without_bounds_signal.txt"

summary="$out_dir/summary.md"
{
  echo "# Objective-C Parser Hardening Scan"
  echo
  echo "- Root: $root_dir"
  echo "- Scan paths: ${scan_paths[*]}"
  echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo
  echo "## Counts"
  echo "- Parse/decoder signals: $(wc -l < "$parse_hits" | tr -d ' ')"
  echo "- Risky memory/range signals: $(wc -l < "$risky_hits" | tr -d ' ')"
  echo "- Bounds/length signals: $(wc -l < "$bounds_hits" | tr -d ' ')"
  echo "- Integer/conversion signals: $(wc -l < "$integer_hits" | tr -d ' ')"
  echo
  echo "## Prioritize first (parse + risky without bounds signal)"
  if [[ -s "$out_dir/parse_risky_without_bounds_signal.txt" ]]; then
    sed 's/^/- /' "$out_dir/parse_risky_without_bounds_signal.txt"
  else
    echo "- none"
  fi
  echo
  echo "## Notes"
  echo "- File-level signal only; confirm exact operation-level guards."
} >"$summary"

echo "wrote $summary"
