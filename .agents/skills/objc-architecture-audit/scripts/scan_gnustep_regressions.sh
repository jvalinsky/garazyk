#!/usr/bin/env bash
set -euo pipefail

root_dir="${1:-.}"
out_dir="${2:-/tmp/objc-gnustep-regression-audit}"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: rg is required but not installed" >&2
  exit 1
fi

scan_path="$root_dir"
if [[ -d "$root_dir/ATProtoPDS/Sources" ]]; then
  scan_path="$root_dir/ATProtoPDS/Sources"
fi

mkdir -p "$out_dir"

mac_api_hits="$out_dir/mac_api_hits_raw.txt"
import_hits="$out_dir/import_hits_raw.txt"
guard_hits="$out_dir/guard_hits_raw.txt"

rg -n --glob '*.{m,mm,h}' \
  -e 'NSURLSession' \
  -e 'NSWorkspace' \
  -e 'NSApplication' \
  -e 'SecKey' \
  -e 'SecItem' \
  -e 'SecTrust' \
  -e '\bos_log\b' \
  -e 'CommonCrypto' \
  "$scan_path" >"$mac_api_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e '#import <Security/Security.h>' \
  -e '#import <CommonCrypto/CommonCrypto.h>' \
  -e '#import <os/log.h>' \
  "$scan_path" >"$import_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'TARGET_OS_LINUX' \
  -e '__linux__' \
  -e 'GNUSTEP' \
  "$scan_path" >"$guard_hits" || true

# Compat sources intentionally include wrappers; exclude them for candidate triage.
grep -v '/Compat/' "$mac_api_hits" >"$out_dir/mac_api_hits.txt" || true
grep -v '/Compat/' "$import_hits" >"$out_dir/import_hits.txt" || true
grep -v '/Compat/' "$guard_hits" >"$out_dir/guard_hits.txt" || true

cut -d: -f1 "$out_dir/mac_api_hits.txt" | sort -u >"$out_dir/mac_api_files.txt"
cut -d: -f1 "$out_dir/import_hits.txt" | sort -u >"$out_dir/import_files.txt"
cut -d: -f1 "$out_dir/guard_hits.txt" | sort -u >"$out_dir/guard_files.txt"

comm -23 "$out_dir/mac_api_files.txt" "$out_dir/guard_files.txt" >"$out_dir/mac_api_without_guard_files.txt"
comm -23 "$out_dir/import_files.txt" "$out_dir/guard_files.txt" >"$out_dir/import_without_guard_files.txt"

summary="$out_dir/summary.md"
{
  echo "# Objective-C GNUstep Regression Scan"
  echo
  echo "- Root: $root_dir"
  echo "- Scan path: $scan_path"
  echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo
  echo "## Counts (excluding Compat/)"
  echo "- macOS-sensitive API signals: $(wc -l < "$out_dir/mac_api_hits.txt" | tr -d ' ')"
  echo "- Platform-sensitive import signals: $(wc -l < "$out_dir/import_hits.txt" | tr -d ' ')"
  echo "- Linux guard signals: $(wc -l < "$out_dir/guard_hits.txt" | tr -d ' ')"
  echo
  echo "## Prioritize first (mac API without guard signal)"
  if [[ -s "$out_dir/mac_api_without_guard_files.txt" ]]; then
    sed 's/^/- /' "$out_dir/mac_api_without_guard_files.txt"
  else
    echo "- none"
  fi
  echo
  echo "## Secondary priority (platform import without guard signal)"
  if [[ -s "$out_dir/import_without_guard_files.txt" ]]; then
    sed 's/^/- /' "$out_dir/import_without_guard_files.txt"
  else
    echo "- none"
  fi
  echo
  echo "## Notes"
  echo "- Some wrappers rely on build-system include path rather than file-local guards."
  echo "- Confirm intended compat pattern before filing findings."
} >"$summary"

echo "wrote $summary"
