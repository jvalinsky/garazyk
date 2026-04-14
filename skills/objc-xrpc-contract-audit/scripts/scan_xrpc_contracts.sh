#!/usr/bin/env bash
set -euo pipefail

root_dir="${1:-.}"
out_dir="${2:-/tmp/objc-xrpc-contract-audit}"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: rg is required but not installed" >&2
  exit 1
fi

scan_path="$root_dir"
if [[ -d "$root_dir/Garazyk/Sources" ]]; then
  scan_path="$root_dir/Garazyk/Sources"
fi

mkdir -p "$out_dir"

method_hits="$out_dir/method_hits.txt"
auth_hits="$out_dir/auth_hits.txt"
validation_hits="$out_dir/validation_hits.txt"
error_hits="$out_dir/error_hits.txt"

rg -n --glob '*.{m,mm,h}' \
  -e 'registerMethod:@"[a-z0-9.]+' \
  -e 'register[A-Za-z0-9_]+' \
  "$scan_path" >"$method_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'require(Auth|Admin)' \
  -e '\bauthorize\b' \
  -e 'checkPermission' \
  -e '\bisAdmin\b' \
  -e '\bscope\b' \
  "$scan_path" >"$auth_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e '\bvalidate' \
  -e '\blexicon\b' \
  -e '\brequired\b' \
  -e '\bparseJSON\b' \
  -e '\bjsonObject\b' \
  "$scan_path" >"$validation_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'XRPC' \
  -e 'ATProtoError' \
  -e '\bstatusCode\b' \
  -e '@"error"' \
  -e '@"message"' \
  "$scan_path" >"$error_hits" || true

nsid_file="$out_dir/nsids.txt"
registry_file="$scan_path/Network/XrpcMethodRegistry.m"
if [[ -f "$registry_file" ]]; then
  rg -o --no-filename 'com\.[a-z0-9.]+' "$registry_file" | sort -u >"$nsid_file" || true
else
  : >"$nsid_file"
fi

cut -d: -f1 "$method_hits" | sort -u >"$out_dir/method_files.txt"
cut -d: -f1 "$auth_hits" | sort -u >"$out_dir/auth_files.txt"
cut -d: -f1 "$validation_hits" | sort -u >"$out_dir/validation_files.txt"

comm -23 "$out_dir/method_files.txt" "$out_dir/auth_files.txt" >"$out_dir/method_files_without_auth_signal.txt"
comm -23 "$out_dir/method_files.txt" "$out_dir/validation_files.txt" >"$out_dir/method_files_without_validation_signal.txt"

summary="$out_dir/summary.md"
{
  echo "# Objective-C XRPC Contract Scan"
  echo
  echo "- Root: $root_dir"
  echo "- Scan path: $scan_path"
  echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo
  echo "## Counts"
  echo "- Method registration signals: $(wc -l < "$method_hits" | tr -d ' ')"
  echo "- Unique NSIDs (registry grep): $(wc -l < "$nsid_file" | tr -d ' ')"
  echo "- Auth enforcement signals: $(wc -l < "$auth_hits" | tr -d ' ')"
  echo "- Validation signals: $(wc -l < "$validation_hits" | tr -d ' ')"
  echo "- Error-shape signals: $(wc -l < "$error_hits" | tr -d ' ')"
  echo
  echo "## Prioritize first (method files without auth signal)"
  if [[ -s "$out_dir/method_files_without_auth_signal.txt" ]]; then
    sed 's/^/- /' "$out_dir/method_files_without_auth_signal.txt"
  else
    echo "- none"
  fi
  echo
  echo "## Secondary priority (method files without validation signal)"
  if [[ -s "$out_dir/method_files_without_validation_signal.txt" ]]; then
    sed 's/^/- /' "$out_dir/method_files_without_validation_signal.txt"
  else
    echo "- none"
  fi
  echo
  echo "## Notes"
  echo "- Registration files can rely on downstream handler auth."
  echo "- Treat these as triage candidates, not automatic findings."
} >"$summary"

echo "wrote $summary"
