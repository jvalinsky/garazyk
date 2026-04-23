#!/usr/bin/env bash
set -euo pipefail

root_dir="${1:-.}"
out_dir="${2:-/tmp/objc-locking-queue-audit}"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: rg is required but not installed" >&2
  exit 1
fi

mkdir -p "$out_dir"

lock_hits="$out_dir/lock_hits.txt"
unlock_hits="$out_dir/unlock_hits.txt"
queue_hits="$out_dir/queue_hits.txt"
queue_assert_hits="$out_dir/queue_assert_hits.txt"
sync_hits="$out_dir/sync_hits.txt"
sync_main_hits="$out_dir/sync_main_hits.txt"

rg -n --glob '*.{m,mm,h}' \
  -e '\[[^]]+\s+lock\]' \
  -e 'os_unfair_lock_lock\b' \
  -e 'pthread_mutex_lock\b' \
  -e '@synchronized\s*\(' \
  "$root_dir" >"$lock_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e '\[[^]]+\s+unlock\]' \
  -e 'os_unfair_lock_unlock\b' \
  -e 'pthread_mutex_unlock\b' \
  "$root_dir" >"$unlock_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'dispatch_queue_create\s*\(' \
  -e 'dispatch_get_main_queue\s*\(' \
  -e 'dispatch_get_global_queue\s*\(' \
  -e 'dispatch_async\s*\(' \
  -e 'dispatch_sync\s*\(' \
  "$root_dir" >"$queue_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'dispatch_assert_queue' \
  -e 'dispatch_assert_queue_not' \
  -e 'dispatch_precondition' \
  "$root_dir" >"$queue_assert_hits" || true

rg -n --glob '*.{m,mm,h}' -e 'dispatch_sync\s*\(' "$root_dir" >"$sync_hits" || true
rg -n --glob '*.{m,mm,h}' -e 'dispatch_sync\s*\(\s*dispatch_get_main_queue\s*\(' "$root_dir" >"$sync_main_hits" || true

cut -d: -f1 "$lock_hits" | sort | uniq -c | awk '{print $2 " " $1}' >"$out_dir/lock_count_by_file.txt"
cut -d: -f1 "$unlock_hits" | sort | uniq -c | awk '{print $2 " " $1}' >"$out_dir/unlock_count_by_file.txt"

awk '
NR==FNR {unlock[$1] = $2; next}
{
  file = $1
  lock_count = $2
  unlock_count = (file in unlock) ? unlock[file] : 0
  if (lock_count > unlock_count) {
    print file " lock=" lock_count " unlock=" unlock_count
  }
}
' "$out_dir/unlock_count_by_file.txt" "$out_dir/lock_count_by_file.txt" >"$out_dir/lock_unlock_imbalance.txt"

cut -d: -f1 "$lock_hits" | sort -u >"$out_dir/lock_files.txt"
cut -d: -f1 "$sync_hits" | sort -u >"$out_dir/sync_files.txt"
cut -d: -f1 "$queue_hits" | sort -u >"$out_dir/queue_files.txt"
cut -d: -f1 "$queue_assert_hits" | sort -u >"$out_dir/queue_assert_files.txt"

comm -12 "$out_dir/lock_files.txt" "$out_dir/sync_files.txt" >"$out_dir/lock_and_sync_files.txt"
comm -23 "$out_dir/queue_files.txt" "$out_dir/queue_assert_files.txt" >"$out_dir/queue_without_assert_files.txt"

summary="$out_dir/summary.md"
{
  echo "# Objective-C Locking and Queue Contract Scan"
  echo
  echo "- Root: $root_dir"
  echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo
  echo "## Counts"
  echo "- Lock sites: $(wc -l < "$lock_hits" | tr -d ' ')"
  echo "- Unlock sites: $(wc -l < "$unlock_hits" | tr -d ' ')"
  echo "- Queue API sites: $(wc -l < "$queue_hits" | tr -d ' ')"
  echo "- Queue assertion sites: $(wc -l < "$queue_assert_hits" | tr -d ' ')"
  echo "- sync sites: $(wc -l < "$sync_hits" | tr -d ' ')"
  echo "- sync-to-main sites: $(wc -l < "$sync_main_hits" | tr -d ' ')"
  echo
  echo "## Prioritize first (lock/unlock imbalance)"
  if [[ -s "$out_dir/lock_unlock_imbalance.txt" ]]; then
    sed 's/^/- /' "$out_dir/lock_unlock_imbalance.txt"
  else
    echo "- none"
  fi
  echo
  echo "## Secondary priority (lock + sync in same file)"
  if [[ -s "$out_dir/lock_and_sync_files.txt" ]]; then
    sed 's/^/- /' "$out_dir/lock_and_sync_files.txt"
  else
    echo "- none"
  fi
  echo
  echo "## Queue files without assertions"
  if [[ -s "$out_dir/queue_without_assert_files.txt" ]]; then
    sed 's/^/- /' "$out_dir/queue_without_assert_files.txt"
  else
    echo "- none"
  fi
  echo
  echo "## Notes"
  echo "- Imbalance can be false-positive when unlock appears in other control-flow paths."
  echo "- Confirm contracts manually before filing findings."
} >"$summary"

echo "wrote $summary"
