#!/usr/bin/env bash
set -euo pipefail

root_dir="${1:-.}"
out_dir="${2:-/tmp/objc-cryptographic-security-audit}"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: rg is required but not installed" >&2
  exit 1
fi

scan_path="$root_dir"
if [[ -d "$root_dir/Garazyk/Sources" ]]; then
  scan_path="$root_dir/Garazyk/Sources"
fi

mkdir -p "$out_dir"

weak_hash_hits="$out_dir/weak_hash_hits.txt"
weak_encrypt_hits="$out_dir/weak_encrypt_hits.txt"
hardcoded_key_hits="$out_dir/hardcoded_key_hits.txt"
hardcoded_iv_hits="$out_dir/hardcoded_iv_hits.txt"
timing_hits="$out_dir/timing_hits.txt"
weak_random_hits="$out_dir/weak_random_hits.txt"
ecb_mode_hits="$out_dir/ecb_mode_hits.txt"

rg -n --glob '*.{m,mm,h}' \
  -e 'CC_MD5\(' \
  -e 'CC_SHA1\(' \
  -e 'MD5\(' \
  -e 'SHA1\(' \
  -e 'SHA1Init\(' \
  -e 'SHA1Update\(' \
  -e 'SHA1Final\(' \
  "$scan_path" >"$weak_hash_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'DES_|kCCAlgorithmDES' \
  -e '3DES|kCCAlgorithm3DES' \
  -e 'RC4|kCCAlgorithmRC4' \
  -e 'kCCAlgorithmBlowfish' \
  "$scan_path" >"$weak_encrypt_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'encryptionKey\s*=\s*@"' \
  -e 'key\s*=\s*@"[A-Za-z0-9+/]{16,}"' \
  -e 'secretKey\s*=\s*@"' \
  -e 'kCCKeySize' \
  "$scan_path" >"$hardcoded_key_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'kCCInitializationVector' \
  -e 'iv\s*=\s*@"' \
  -e 'initializationVector\s*=\s*@"' \
  -e 'kCCBlockSizeAES128' \
  "$scan_path" >"$hardcoded_iv_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'strcmp\s*\([^,]+,\s*[^)]+\)' \
  -e 'memcmp\s*\([^,]+,\s*[^,]+,\s*[^)]+\)' \
  -e 'NSIsEqual\[' \
  -e 'isEqualToString.*token' \
  -e 'isEqualToString.*secret' \
  -e 'isEqualToString.*password' \
  -e 'isEqualToString.*key' \
  "$scan_path" >"$timing_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e '\brand\s*\(' \
  -e '\brandom\s*\(' \
  -e 'srand\s*\(' \
  -e 'arc4random\s*\(\s*\)' \
  "$scan_path" >"$weak_random_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'kCCOptionECBMode' \
  -e 'kCCModeECB' \
  "$scan_path" >"$ecb_mode_hits" || true

securerandom_hits="$out_dir/securerandom_hits.txt"
rg -n --glob '*.{m,mm,h}' \
  -e 'SecRandomCopyBytes' \
  -e 'arc4random_buf' \
  -e 'CCRandomGenerateBytes' \
  "$scan_path" >"$securerandom_hits" || true

cat "$weak_hash_hits" "$weak_encrypt_hits" "$hardcoded_key_hits" "$timing_hits" "$ecb_mode_hits" \
  | cut -d: -f1 | sort -u >"$out_dir/files_with_crypto_issues.txt" || true

summary="$out_dir/summary.md"
{
  echo "# Objective-C Cryptographic Security Scan"
  echo
  echo "- Root: $root_dir"
  echo "- Scan path: $scan_path"
  echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo
  echo "## Counts"
  echo "- Weak hash usage (MD5/SHA1): $(wc -l < "$weak_hash_hits" | tr -d ' ')"
  echo "- Weak encryption (DES/3DES/RC4): $(wc -l < "$weak_encrypt_hits" | tr -d ' ')"
  echo "- Hardcoded key references: $(wc -l < "$hardcoded_key_hits" | tr -d ' ')"
  echo "- Hardcoded IV references: $(wc -l < "$hardcoded_iv_hits" | tr -d ' ')"
  echo "- Timing-vulnerable comparisons: $(wc -l < "$timing_hits" | tr -d ' ')"
  echo "- Weak random usage: $(wc -l < "$weak_random_hits" | tr -d ' ')"
  echo "- ECB mode usage: $(wc -l < "$ecb_mode_hits" | tr -d ' ')"
  echo "- Secure random usage: $(wc -l < "$securerandom_hits" | tr -d ' ')"
  echo
  echo "## Files with potential crypto issues"
  if [[ -s "$out_dir/files_with_crypto_issues.txt" ]]; then
    sed 's/^/- /' "$out_dir/files_with_crypto_issues.txt"
  else
    echo "- none detected"
  fi
  echo
  echo "## Detailed findings"
  echo
  echo "### Weak hash algorithms (MD5/SHA1)"
  if [[ -s "$weak_hash_hits" ]]; then
    head -15 "$weak_hash_hits" | sed 's/^/  /'
    if [[ $(wc -l < "$weak_hash_hits") -gt 15 ]]; then
      echo "  ... and $(( $(wc -l < "$weak_hash_hits") - 15 )) more"
    fi
  else
    echo "  none"
  fi
  echo
  echo "### Timing-vulnerable secret comparisons"
  if [[ -s "$timing_hits" ]]; then
    head -15 "$timing_hits" | sed 's/^/  /'
    if [[ $(wc -l < "$timing_hits") -gt 15 ]]; then
      echo "  ... and $(( $(wc -l < "$timing_hits") - 15 )) more"
    fi
  else
    echo "  none"
  fi
  echo
  echo "### ECB mode usage"
  if [[ -s "$ecb_mode_hits" ]]; then
    head -10 "$ecb_mode_hits" | sed 's/^/  /'
  else
    echo "  none"
  fi
  echo
  echo "## Notes"
  echo "- SHA1/MD5 may be acceptable for non-security uses (checksums, dedup)."
  echo "- Verify context before flagging as vulnerability."
  echo "- Timing attacks require network access; prioritize based on threat model."
  echo "- arc4random() without arguments is often used for non-crypto purposes."
} >"$summary"

echo "wrote $summary"
