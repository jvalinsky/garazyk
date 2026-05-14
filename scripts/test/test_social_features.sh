#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/../.." && pwd))"

echo "[INFO] test_social_features.sh is retired; running canonical scenarios 02 and 03."
exec deno run -A "$REPO_ROOT/scripts/run_scenarios.ts" --setup --teardown 02 03 "$@"
