#!/usr/bin/env bash
set -euo pipefail

root_dir="${1:-.}"
out_dir="${2:-/tmp/objc-concurrency-audit}"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: rg is required but not installed" >&2
  exit 1
fi

mkdir -p "$out_dir"

threading_hits="$out_dir/threading_hits.txt"
sync_hits="$out_dir/sync_hits.txt"
mutable_state_hits="$out_dir/mutable_state_hits.txt"
nonatomic_property_hits="$out_dir/nonatomic_property_hits.txt"
main_sync_hits="$out_dir/main_sync_hits.txt"

rg -n --glob '*.{m,mm,h}' \
  -e 'dispatch_async\s*\(' \
  -e 'dispatch_sync\s*\(' \
  -e 'NSThread' \
  -e 'NSOperationQueue' \
  -e 'performSelectorInBackground:' \
  "$root_dir" >"$threading_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e '@synchronized\s*\(' \
  -e '\[[^]]+\s+lock\]' \
  -e 'os_unfair_lock_lock\b' \
  -e 'pthread_mutex_lock\b' \
  -e 'dispatch_semaphore_wait\b' \
  "$root_dir" >"$sync_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'NSMutable(Array|Dictionary|Set|Data)\b' \
  -e 'NSMapTable\b' \
  -e 'NSHashTable\b' \
  -e '^\s*static\s+.*=' \
  -e '^\s*extern\s+' \
  "$root_dir" >"$mutable_state_hits" || true

rg -n --glob '*.{h,m,mm}' \
  -e '@property\s*\([^)]*nonatomic' \
  "$root_dir" >"$nonatomic_property_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'dispatch_sync\s*\(\s*dispatch_get_main_queue\s*\(' \
  "$root_dir" >"$main_sync_hits" || true

cut -d: -f1 "$threading_hits" | sort -u >"$out_dir/threading_files.txt"
cut -d: -f1 "$sync_hits" | sort -u >"$out_dir/sync_files.txt"
cut -d: -f1 "$mutable_state_hits" | sort -u >"$out_dir/mutable_files.txt"

comm -12 "$out_dir/threading_files.txt" "$out_dir/mutable_files.txt" >"$out_dir/threading_and_mutable_files.txt"
comm -23 "$out_dir/threading_and_mutable_files.txt" "$out_dir/sync_files.txt" >"$out_dir/unsynchronized_candidates.txt"

summary="$out_dir/summary.md"
{
  echo "# Objective-C Concurrency Scan"
  echo
  echo "- Root: $root_dir"
  echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo
  echo "## Counts"
  echo "- Threading sites: $(wc -l < "$threading_hits" | tr -d ' ')"
  echo "- Synchronization sites: $(wc -l < "$sync_hits" | tr -d ' ')"
  echo "- Shared mutable state sites: $(wc -l < "$mutable_state_hits" | tr -d ' ')"
  echo "- Non-atomic property declarations: $(wc -l < "$nonatomic_property_hits" | tr -d ' ')"
  echo "- sync-to-main calls: $(wc -l < "$main_sync_hits" | tr -d ' ')"
  echo
  echo "## Prioritize first (threading + mutable + no sync signal in file)"
  if [[ -s "$out_dir/unsynchronized_candidates.txt" ]]; then
    sed 's/^/- /' "$out_dir/unsynchronized_candidates.txt"
  else
    echo "- none"
  fi
  echo
  echo "## Notes"
  echo "- Static results are heuristic only."
  echo "- Validate queue ownership and lock strategy before final findings."
} >"$summary"

echo "wrote $summary"
