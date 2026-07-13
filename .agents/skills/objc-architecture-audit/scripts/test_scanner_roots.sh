#!/usr/bin/env bash
# Smoke-test the repository layout assumptions used by the architecture scans.
set -euo pipefail

repo_root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
output_dir="$(mktemp -d "${TMPDIR:-/tmp}/garazyk-architecture-scanner.XXXXXX")"
trap 'rm -rf "$output_dir"' EXIT

"$script_dir/scan_service_boundaries.sh" "$repo_root" "$output_dir/services" >/dev/null
"$script_dir/map_test_gaps.sh" "$repo_root" "$output_dir/tests" >/dev/null

service_count="$(wc -l < "$output_dir/services/service_files.txt" | tr -d ' ')"
test_count="$(wc -l < "$output_dir/tests/test_files.txt" | tr -d ' ')"

if [[ "$service_count" -eq 0 || "$test_count" -eq 0 ]]; then
  echo "expected nonzero service and test counts; got services=$service_count tests=$test_count" >&2
  exit 1
fi

grep -Fx "$repo_root/Garazyk/Sources/Services/PDS/PDSRelayService.m" \
  "$output_dir/services/service_files.txt" >/dev/null
grep -Fx "$repo_root/Garazyk/Tests/Network/XrpcMethodRegistryTests.m" \
  "$output_dir/tests/test_files.txt" >/dev/null

echo "scanner roots verified: services=$service_count tests=$test_count"
