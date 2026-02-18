#!/usr/bin/env bash
set -euo pipefail

root_dir="${1:-.}"
out_dir="${2:-/tmp/objc-reentrancy-audit}"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: rg is required but not installed" >&2
  exit 1
fi

mkdir -p "$out_dir"

lock_hits="$out_dir/lock_hits.txt"
callback_hits="$out_dir/callback_hits.txt"
kvo_notification_hits="$out_dir/kvo_notification_hits.txt"
sync_queue_hits="$out_dir/sync_queue_hits.txt"

rg -n --glob '*.{m,mm,h}' \
  -e '@synchronized\s*\(' \
  -e '\[[^]]+\s+lock\]' \
  -e 'os_unfair_lock_lock\b' \
  -e 'pthread_mutex_lock\b' \
  -e 'dispatch_semaphore_wait\b' \
  "$root_dir" >"$lock_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e '\[[^]]*delegate[^]]*\]' \
  -e '\bcompletion\s*\(' \
  -e '\bhandler\s*\(' \
  -e '\bcallback\s*\(' \
  -e 'postNotification(Name|:)' \
  "$root_dir" >"$callback_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'addObserver:' \
  -e 'observeValueForKeyPath:' \
  -e 'willChangeValueForKey:' \
  -e 'didChangeValueForKey:' \
  -e 'postNotification(Name|:)' \
  "$root_dir" >"$kvo_notification_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'dispatch_sync\s*\(' \
  -e 'dispatch_get_main_queue\s*\(' \
  -e 'performSelectorOnMainThread:' \
  "$root_dir" >"$sync_queue_hits" || true

cut -d: -f1 "$lock_hits" | sort -u >"$out_dir/lock_files.txt"
cut -d: -f1 "$callback_hits" | sort -u >"$out_dir/callback_files.txt"
cut -d: -f1 "$sync_queue_hits" | sort -u >"$out_dir/sync_queue_files.txt"

comm -12 "$out_dir/lock_files.txt" "$out_dir/callback_files.txt" >"$out_dir/lock_and_callback_files.txt"
comm -12 "$out_dir/lock_files.txt" "$out_dir/sync_queue_files.txt" >"$out_dir/lock_and_sync_files.txt"

summary="$out_dir/summary.md"
{
  echo "# Objective-C Re-entrancy Scan"
  echo
  echo "- Root: $root_dir"
  echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo
  echo "## Counts"
  echo "- Lock primitives: $(wc -l < "$lock_hits" | tr -d ' ')"
  echo "- Callback sites: $(wc -l < "$callback_hits" | tr -d ' ')"
  echo "- KVO or notification sites: $(wc -l < "$kvo_notification_hits" | tr -d ' ')"
  echo "- Sync queue sites: $(wc -l < "$sync_queue_hits" | tr -d ' ')"
  echo
  echo "## Prioritize first"
  if [[ -s "$out_dir/lock_and_callback_files.txt" ]]; then
    sed 's/^/- /' "$out_dir/lock_and_callback_files.txt"
  else
    echo "- none"
  fi
  echo
  echo "## Secondary priority (lock + sync dispatch)"
  if [[ -s "$out_dir/lock_and_sync_files.txt" ]]; then
    sed 's/^/- /' "$out_dir/lock_and_sync_files.txt"
  else
    echo "- none"
  fi
  echo
  echo "## Notes"
  echo "- Treat results as candidates."
  echo "- Confirm control flow before filing findings."
} >"$summary"

echo "wrote $summary"
