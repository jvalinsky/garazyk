#!/usr/bin/env bash
set -euo pipefail

root_dir="${1:-.}"
out_dir="${2:-/tmp/objc-oauth-dpop-conformance-audit}"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: rg is required but not installed" >&2
  exit 1
fi

scan_path="$root_dir"
if [[ -d "$root_dir/Garazyk/Sources" ]]; then
  scan_path="$root_dir/Garazyk/Sources"
fi

mkdir -p "$out_dir"

dpop_hits="$out_dir/dpop_hits.txt"
token_hits="$out_dir/token_hits.txt"
nonce_hits="$out_dir/nonce_hits.txt"
clock_hits="$out_dir/clock_hits.txt"
key_hits="$out_dir/key_hits.txt"

rg -n --glob '*.{m,mm,h}' \
  -e '\bDPoP\b' \
  -e '\bdpop\b' \
  -e '\bproof\b' \
  -e '\bjti\b' \
  -e '\bhtu\b' \
  -e '\bhtm\b' \
  "$scan_path/Auth" "$scan_path/Network" 2>/dev/null >"$dpop_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'access token' \
  -e 'refresh token' \
  -e '\brefresh\b' \
  -e '\bexpires\b' \
  -e '\brevoke\b' \
  -e '\brotat(e|ion)\b' \
  "$scan_path/Auth" "$scan_path/Network" 2>/dev/null >"$token_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e '\bnonce\b' \
  -e '\breplay\b' \
  -e 'one[- ]time' \
  "$scan_path/Auth" "$scan_path/Network" 2>/dev/null >"$nonce_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e '\biat\b' \
  -e '\bexp\b' \
  -e 'timeIntervalSince1970' \
  -e '\bclock\b' \
  -e '\bskew\b' \
  "$scan_path/Auth" "$scan_path/Network" 2>/dev/null >"$clock_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'SecKey' \
  -e '\bJWT\b' \
  -e '\bverify\b' \
  -e '\bsign\b' \
  -e '\bkid\b' \
  "$scan_path/Auth" "$scan_path/Security" 2>/dev/null >"$key_hits" || true

cut -d: -f1 "$dpop_hits" | sort -u >"$out_dir/dpop_files.txt"
cut -d: -f1 "$token_hits" | sort -u >"$out_dir/token_files.txt"
cut -d: -f1 "$nonce_hits" | sort -u >"$out_dir/nonce_files.txt"

comm -12 "$out_dir/dpop_files.txt" "$out_dir/token_files.txt" >"$out_dir/dpop_and_token_files.txt"
comm -23 "$out_dir/dpop_files.txt" "$out_dir/nonce_files.txt" >"$out_dir/dpop_without_nonce_signal.txt"

summary="$out_dir/summary.md"
{
  echo "# Objective-C OAuth DPoP Conformance Scan"
  echo
  echo "- Root: $root_dir"
  echo "- Scan path: $scan_path"
  echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo
  echo "## Counts"
  echo "- DPoP/proof signals: $(wc -l < "$dpop_hits" | tr -d ' ')"
  echo "- Token lifecycle signals: $(wc -l < "$token_hits" | tr -d ' ')"
  echo "- Nonce/replay signals: $(wc -l < "$nonce_hits" | tr -d ' ')"
  echo "- Clock/skew signals: $(wc -l < "$clock_hits" | tr -d ' ')"
  echo "- Key/sign/verify signals: $(wc -l < "$key_hits" | tr -d ' ')"
  echo
  echo "## Prioritize first (DPoP + token lifecycle files)"
  if [[ -s "$out_dir/dpop_and_token_files.txt" ]]; then
    sed 's/^/- /' "$out_dir/dpop_and_token_files.txt"
  else
    echo "- none"
  fi
  echo
  echo "## Secondary priority (DPoP files without nonce signal)"
  if [[ -s "$out_dir/dpop_without_nonce_signal.txt" ]]; then
    sed 's/^/- /' "$out_dir/dpop_without_nonce_signal.txt"
  else
    echo "- none"
  fi
  echo
  echo "## Notes"
  echo "- Validate against runtime behavior and conformance tests."
} >"$summary"

echo "wrote $summary"
