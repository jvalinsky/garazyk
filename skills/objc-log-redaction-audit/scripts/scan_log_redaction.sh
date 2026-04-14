#!/usr/bin/env bash
set -euo pipefail

root_dir="${1:-.}"
out_dir="${2:-/tmp/objc-log-redaction-audit}"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: rg is required but not installed" >&2
  exit 1
fi

scan_path="$root_dir"
if [[ -d "$root_dir/Garazyk/Sources" ]]; then
  scan_path="$root_dir/Garazyk/Sources"
fi

mkdir -p "$out_dir"

log_hits="$out_dir/log_hits.txt"
sensitive_hits="$out_dir/sensitive_hits.txt"
header_hits="$out_dir/header_hits.txt"

rg -n --glob '*.{m,mm,h}' \
  -e '\bNSLog\b' \
  -e '\bos_log\b' \
  -e '\bprintf\b' \
  -e '\bfprintf\b' \
  -e 'PDSLog' \
  -e 'logger' \
  "$scan_path" >"$log_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'accessToken' \
  -e 'refreshToken' \
  -e 'authorization' \
  -e 'bearer' \
  -e 'password' \
  -e 'secret' \
  -e '\bJWT\b' \
  -e '\bDPoP\b' \
  -e '\bcookie\b' \
  "$scan_path" >"$sensitive_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'Authorization:' \
  -e 'Set-Cookie' \
  -e 'Bearer ' \
  -e 'Cookie:' \
  "$scan_path" >"$header_hits" || true

cut -d: -f1 "$log_hits" | sort -u >"$out_dir/log_files.txt"
cut -d: -f1 "$sensitive_hits" | sort -u >"$out_dir/sensitive_files.txt"
cut -d: -f1 "$header_hits" | sort -u >"$out_dir/header_files.txt"

comm -12 "$out_dir/log_files.txt" "$out_dir/sensitive_files.txt" >"$out_dir/log_and_sensitive_files.txt"
comm -12 "$out_dir/log_files.txt" "$out_dir/header_files.txt" >"$out_dir/log_and_header_files.txt"

summary="$out_dir/summary.md"
{
  echo "# Objective-C Log Redaction Scan"
  echo
  echo "- Root: $root_dir"
  echo "- Scan path: $scan_path"
  echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo
  echo "## Counts"
  echo "- Logging signals: $(wc -l < "$log_hits" | tr -d ' ')"
  echo "- Sensitive identifier signals: $(wc -l < "$sensitive_hits" | tr -d ' ')"
  echo "- Header/token literal signals: $(wc -l < "$header_hits" | tr -d ' ')"
  echo
  echo "## Prioritize first (logging + sensitive identifiers)"
  if [[ -s "$out_dir/log_and_sensitive_files.txt" ]]; then
    sed 's/^/- /' "$out_dir/log_and_sensitive_files.txt"
  else
    echo "- none"
  fi
  echo
  echo "## Secondary priority (logging + auth header literals)"
  if [[ -s "$out_dir/log_and_header_files.txt" ]]; then
    sed 's/^/- /' "$out_dir/log_and_header_files.txt"
  else
    echo "- none"
  fi
  echo
  echo "## Notes"
  echo "- False positives are expected; inspect exact logged payloads."
} >"$summary"

echo "wrote $summary"
