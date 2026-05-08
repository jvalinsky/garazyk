#!/usr/bin/env bash
set -euo pipefail

root_dir="${1:-.}"
out_dir="${2:-/tmp/objc-sqlite-invariant-audit}"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: rg is required but not installed" >&2
  exit 1
fi

scan_path="$root_dir"
if [[ -d "$root_dir/Garazyk/Sources/Database" ]]; then
  scan_path="$root_dir/Garazyk/Sources/Database"
fi

mkdir -p "$out_dir"

transaction_hits="$out_dir/transaction_hits.txt"
prepare_hits="$out_dir/prepare_hits.txt"
step_hits="$out_dir/step_hits.txt"
reset_hits="$out_dir/reset_hits.txt"
finalize_hits="$out_dir/finalize_hits.txt"
pragma_hits="$out_dir/pragma_hits.txt"
lock_hits="$out_dir/lock_hits.txt"

rg -n --glob '*.{m,mm,h}' \
  -e '\bBEGIN\b' \
  -e '\bCOMMIT\b' \
  -e '\bROLLBACK\b' \
  -e 'inTransaction' \
  "$scan_path" >"$transaction_hits" || true

rg -n --glob '*.{m,mm,h}' -e 'sqlite3_prepare(_v2)?\b' "$scan_path" >"$prepare_hits" || true
rg -n --glob '*.{m,mm,h}' -e 'sqlite3_step\b' "$scan_path" >"$step_hits" || true
rg -n --glob '*.{m,mm,h}' -e 'sqlite3_reset\b' "$scan_path" >"$reset_hits" || true
rg -n --glob '*.{m,mm,h}' -e 'sqlite3_finalize\b' "$scan_path" >"$finalize_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'PRAGMA' \
  -e 'journal_mode' \
  -e 'foreign_keys' \
  -e 'busy_timeout' \
  "$scan_path" >"$pragma_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e '@synchronized\s*\(' \
  -e '\[[^]]+\s+lock\]' \
  -e 'os_unfair_lock_lock\b' \
  -e 'pthread_mutex_lock\b' \
  "$scan_path" >"$lock_hits" || true

cut -d: -f1 "$prepare_hits" | sort -u >"$out_dir/prepare_files.txt"
cut -d: -f1 "$finalize_hits" | sort -u >"$out_dir/finalize_files.txt"
cut -d: -f1 "$step_hits" | sort -u >"$out_dir/step_files.txt"
cut -d: -f1 "$reset_hits" | sort -u >"$out_dir/reset_files.txt"
cut -d: -f1 "$transaction_hits" | sort -u >"$out_dir/transaction_files.txt"
cut -d: -f1 "$lock_hits" | sort -u >"$out_dir/lock_files.txt"

comm -23 "$out_dir/prepare_files.txt" "$out_dir/finalize_files.txt" >"$out_dir/prepare_without_finalize.txt"
comm -23 "$out_dir/step_files.txt" "$out_dir/reset_files.txt" >"$out_dir/step_without_reset.txt"
comm -12 "$out_dir/transaction_files.txt" "$out_dir/lock_files.txt" >"$out_dir/transaction_and_lock_files.txt"

summary="$out_dir/summary.md"
{
  echo "# Objective-C SQLite Invariant Scan"
  echo
  echo "- Root: $root_dir"
  echo "- Scan path: $scan_path"
  echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo
  echo "## Counts"
  echo "- Transaction sites: $(wc -l < "$transaction_hits" | tr -d ' ')"
  echo "- Prepare sites: $(wc -l < "$prepare_hits" | tr -d ' ')"
  echo "- Step sites: $(wc -l < "$step_hits" | tr -d ' ')"
  echo "- Reset sites: $(wc -l < "$reset_hits" | tr -d ' ')"
  echo "- Finalize sites: $(wc -l < "$finalize_hits" | tr -d ' ')"
  echo "- PRAGMA sites: $(wc -l < "$pragma_hits" | tr -d ' ')"
  echo
  echo "## Prioritize first (prepare without finalize signal)"
  if [[ -s "$out_dir/prepare_without_finalize.txt" ]]; then
    sed 's/^/- /' "$out_dir/prepare_without_finalize.txt"
  else
    echo "- none"
  fi
  echo
  echo "## Secondary priority (step without reset signal)"
  if [[ -s "$out_dir/step_without_reset.txt" ]]; then
    sed 's/^/- /' "$out_dir/step_without_reset.txt"
  else
    echo "- none"
  fi
  echo
  echo "## Transaction files that also lock"
  if [[ -s "$out_dir/transaction_and_lock_files.txt" ]]; then
    sed 's/^/- /' "$out_dir/transaction_and_lock_files.txt"
  else
    echo "- none"
  fi
  echo
  echo "## Notes"
  echo "- Signals are file-level heuristics only."
  echo "- Confirm control flow before filing findings."
} >"$summary"

echo "wrote $summary"
