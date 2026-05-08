#!/usr/bin/env bash
set -euo pipefail

root_dir="${1:-.}"
out_dir="${2:-/tmp/objc-network-timeout-retry-audit}"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: rg is required but not installed" >&2
  exit 1
fi

scan_path="$root_dir"
if [[ -d "$root_dir/Garazyk/Sources/Network" ]]; then
  scan_path="$root_dir/Garazyk/Sources/Network"
fi

mkdir -p "$out_dir"

io_hits="$out_dir/io_hits.txt"
timeout_hits="$out_dir/timeout_hits.txt"
retry_hits="$out_dir/retry_hits.txt"
cancel_hits="$out_dir/cancel_hits.txt"
error_hits="$out_dir/error_hits.txt"

rg -n --glob '*.{m,mm,h}' \
  -e '\bconnect\b' \
  -e '\bsend\b' \
  -e '\brecv\b' \
  -e '\bread\b' \
  -e '\bwrite\b' \
  -e 'NSURLConnection' \
  "$scan_path" >"$io_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e '\btimeout\b' \
  -e 'SO_RCVTIMEO' \
  -e 'SO_SNDTIMEO' \
  -e 'dispatch_time' \
  -e 'NSTimeInterval' \
  "$scan_path" >"$timeout_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e '\bretry\b' \
  -e '\bbackoff\b' \
  -e '\battempt\b' \
  -e '\breconnect\b' \
  -e '\bjitter\b' \
  "$scan_path" >"$retry_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e '\bcancel\b' \
  -e '\bshutdown\b' \
  -e '\bclose\b' \
  "$scan_path" >"$cancel_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'EAGAIN' \
  -e 'EWOULDBLOCK' \
  -e 'ETIMEDOUT' \
  -e 'ECONNRESET' \
  -e 'ENOTCONN' \
  "$scan_path" >"$error_hits" || true

cut -d: -f1 "$io_hits" | sort -u >"$out_dir/io_files.txt"
cut -d: -f1 "$timeout_hits" | sort -u >"$out_dir/timeout_files.txt"
cut -d: -f1 "$retry_hits" | sort -u >"$out_dir/retry_files.txt"
cut -d: -f1 "$cancel_hits" | sort -u >"$out_dir/cancel_files.txt"

comm -23 "$out_dir/io_files.txt" "$out_dir/timeout_files.txt" >"$out_dir/io_without_timeout_signal.txt"
comm -23 "$out_dir/io_files.txt" "$out_dir/cancel_files.txt" >"$out_dir/io_without_cancel_signal.txt"
comm -23 "$out_dir/retry_files.txt" "$out_dir/timeout_files.txt" >"$out_dir/retry_without_timeout_signal.txt"

summary="$out_dir/summary.md"
{
  echo "# Objective-C Network Timeout/Retry Scan"
  echo
  echo "- Root: $root_dir"
  echo "- Scan path: $scan_path"
  echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo
  echo "## Counts"
  echo "- IO/connect signals: $(wc -l < "$io_hits" | tr -d ' ')"
  echo "- Timeout signals: $(wc -l < "$timeout_hits" | tr -d ' ')"
  echo "- Retry/backoff signals: $(wc -l < "$retry_hits" | tr -d ' ')"
  echo "- Cancel/close signals: $(wc -l < "$cancel_hits" | tr -d ' ')"
  echo "- Transient error signals: $(wc -l < "$error_hits" | tr -d ' ')"
  echo
  echo "## Prioritize first (IO files without timeout signal)"
  if [[ -s "$out_dir/io_without_timeout_signal.txt" ]]; then
    sed 's/^/- /' "$out_dir/io_without_timeout_signal.txt"
  else
    echo "- none"
  fi
  echo
  echo "## Secondary priority (retry files without timeout signal)"
  if [[ -s "$out_dir/retry_without_timeout_signal.txt" ]]; then
    sed 's/^/- /' "$out_dir/retry_without_timeout_signal.txt"
  else
    echo "- none"
  fi
  echo
  echo "## Notes"
  echo "- Heuristics identify candidates only; verify control flow and idempotency."
} >"$summary"

echo "wrote $summary"
