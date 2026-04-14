#!/usr/bin/env bash
set -euo pipefail

root_dir="${1:-.}"
out_dir="${2:-/tmp/objc-service-boundary-audit}"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: rg is required but not installed" >&2
  exit 1
fi

services_path="$root_dir/Garazyk/Sources/App/Services"
security_path="$root_dir/Garazyk/Sources/Security"
if [[ ! -d "$services_path" ]]; then
  services_path="$root_dir/Sources/App/Services"
fi
if [[ ! -d "$security_path" ]]; then
  security_path="$root_dir/Sources/Security"
fi

mkdir -p "$out_dir"

service_files_list="$out_dir/service_files.txt"
auth_hits="$out_dir/auth_hits.txt"
privileged_hits="$out_dir/privileged_hits.txt"
input_hits="$out_dir/input_hits.txt"

find "$services_path" -type f \( -name '*.m' -o -name '*.mm' -o -name '*.h' \) | sort >"$service_files_list" || true

rg -n --glob '*.{m,mm,h}' \
  -e '\bauthorize\b' \
  -e 'authz' \
  -e 'checkPermission' \
  -e 'require(Auth|Admin)' \
  -e '\bisAdmin\b' \
  -e '\bscope\b' \
  -e '\bcan[A-Z]' \
  "$services_path" "$security_path" 2>/dev/null >"$auth_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e '\bdelete\b' \
  -e '\bdisable\b' \
  -e '\benable\b' \
  -e '\bcreate\b' \
  -e '\bupdate\b' \
  -e '\brevoke\b' \
  -e '\bgrant\b' \
  -e '\blabel\b' \
  "$services_path" "$security_path" 2>/dev/null >"$privileged_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e '\brequest\b' \
  -e '\bparams\b' \
  -e '\bbody\b' \
  -e '\bactor\b' \
  -e '\brepo\b' \
  -e '\bdid\b' \
  -e '\bhandle\b' \
  "$services_path" "$security_path" 2>/dev/null >"$input_hits" || true

cut -d: -f1 "$auth_hits" | sort -u >"$out_dir/auth_files.txt"
cut -d: -f1 "$privileged_hits" | sort -u >"$out_dir/privileged_files.txt"
cut -d: -f1 "$input_hits" | sort -u >"$out_dir/input_files.txt"

comm -23 "$service_files_list" "$out_dir/auth_files.txt" >"$out_dir/services_without_auth_signal.txt"
comm -12 "$service_files_list" "$out_dir/privileged_files.txt" >"$out_dir/privileged_service_files.txt"
comm -23 "$out_dir/privileged_service_files.txt" "$out_dir/auth_files.txt" >"$out_dir/privileged_without_auth_signal.txt"

summary="$out_dir/summary.md"
{
  echo "# Objective-C Service Boundary Scan"
  echo
  echo "- Root: $root_dir"
  echo "- Services path: $services_path"
  echo "- Security path: $security_path"
  echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo
  echo "## Counts"
  echo "- Service files: $(wc -l < "$service_files_list" | tr -d ' ')"
  echo "- Authz signals: $(wc -l < "$auth_hits" | tr -d ' ')"
  echo "- Privileged-operation signals: $(wc -l < "$privileged_hits" | tr -d ' ')"
  echo "- External-input signals: $(wc -l < "$input_hits" | tr -d ' ')"
  echo
  echo "## Prioritize first (privileged service files without auth signal)"
  if [[ -s "$out_dir/privileged_without_auth_signal.txt" ]]; then
    sed 's/^/- /' "$out_dir/privileged_without_auth_signal.txt"
  else
    echo "- none"
  fi
  echo
  echo "## Secondary priority (service files without auth signal)"
  if [[ -s "$out_dir/services_without_auth_signal.txt" ]]; then
    sed 's/^/- /' "$out_dir/services_without_auth_signal.txt"
  else
    echo "- none"
  fi
  echo
  echo "## Notes"
  echo "- Upstream authorization may exist; verify boundary ownership before filing findings."
} >"$summary"

echo "wrote $summary"
