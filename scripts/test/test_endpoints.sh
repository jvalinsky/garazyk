#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/../.." && pwd))"

echo "[INFO] test_endpoints.sh is retired; running canonical endpoint scenarios."
exec deno run -A "$REPO_ROOT/scripts/run_scenarios.ts" --setup --teardown 01 02 03 07 08 10 "$@"
