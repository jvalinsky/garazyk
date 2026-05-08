#!/usr/bin/env bash
set -euo pipefail

root_dir="${1:-.}"
out_dir="${2:-/tmp/objc-firehose-ordering-backpressure-audit}"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: rg is required but not installed" >&2
  exit 1
fi

scan_path="$root_dir"
if [[ -d "$root_dir/Garazyk/Sources/Sync" ]]; then
  scan_path="$root_dir/Garazyk/Sources/Sync"
fi

mkdir -p "$out_dir"

ordering_hits="$out_dir/ordering_hits.txt"
backpressure_hits="$out_dir/backpressure_hits.txt"
emit_hits="$out_dir/emit_hits.txt"
retry_hits="$out_dir/retry_hits.txt"
lock_hits="$out_dir/lock_hits.txt"

rg -n --glob '*.{m,mm,h}' \
  -e '\bseq(uence)?\b' \
  -e '\bcursor\b' \
  -e '\brev\b' \
  -e 'since' \
  -e 'subscribeRepos' \
  "$scan_path" >"$ordering_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'backpressure' \
  -e '\bbuffer\b' \
  -e '\bqueue\b' \
  -e '\bpending\b' \
  -e '\boverflow\b' \
  -e '\bdrop(ped)?\b' \
  "$scan_path" >"$backpressure_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e '\bsend\b' \
  -e '\bwrite\b' \
  -e '\bbroadcast\b' \
  -e '\bemit\b' \
  -e 'WebSocket' \
  "$scan_path" >"$emit_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e '\bretry\b' \
  -e '\breconnect\b' \
  -e '\breplay\b' \
  -e '\bresume\b' \
  "$scan_path" >"$retry_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e '@synchronized\s*\(' \
  -e '\[[^]]+\s+lock\]' \
  -e 'dispatch_sync\s*\(' \
  "$scan_path" >"$lock_hits" || true

cut -d: -f1 "$ordering_hits" | sort -u >"$out_dir/ordering_files.txt"
cut -d: -f1 "$backpressure_hits" | sort -u >"$out_dir/backpressure_files.txt"
cut -d: -f1 "$emit_hits" | sort -u >"$out_dir/emit_files.txt"

comm -12 "$out_dir/ordering_files.txt" "$out_dir/backpressure_files.txt" >"$out_dir/ordering_and_backpressure_files.txt"
comm -23 "$out_dir/emit_files.txt" "$out_dir/backpressure_files.txt" >"$out_dir/emitter_without_backpressure_signal.txt"

summary="$out_dir/summary.md"
{
  echo "# Objective-C Firehose Ordering/Backpressure Scan"
  echo
  echo "- Root: $root_dir"
  echo "- Scan path: $scan_path"
  echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo
  echo "## Counts"
  echo "- Ordering/cursor signals: $(wc -l < "$ordering_hits" | tr -d ' ')"
  echo "- Backpressure/buffer signals: $(wc -l < "$backpressure_hits" | tr -d ' ')"
  echo "- Emit/write signals: $(wc -l < "$emit_hits" | tr -d ' ')"
  echo "- Retry/replay signals: $(wc -l < "$retry_hits" | tr -d ' ')"
  echo "- Lock/sync signals: $(wc -l < "$lock_hits" | tr -d ' ')"
  echo
  echo "## Prioritize first (ordering + backpressure same file)"
  if [[ -s "$out_dir/ordering_and_backpressure_files.txt" ]]; then
    sed 's/^/- /' "$out_dir/ordering_and_backpressure_files.txt"
  else
    echo "- none"
  fi
  echo
  echo "## Secondary priority (emitters without backpressure signal)"
  if [[ -s "$out_dir/emitter_without_backpressure_signal.txt" ]]; then
    sed 's/^/- /' "$out_dir/emitter_without_backpressure_signal.txt"
  else
    echo "- none"
  fi
  echo
  echo "## Notes"
  echo "- File-level heuristics only; verify per-connection behavior manually."
} >"$summary"

echo "wrote $summary"
