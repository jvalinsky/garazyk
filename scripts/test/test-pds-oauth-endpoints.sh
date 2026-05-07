#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/../.." && pwd))"

echo "[INFO] test-pds-oauth-endpoints.sh is retired; running canonical scenario 08."
exec python3 "$REPO_ROOT/scripts/scenarios/run_scenario.py" --setup --teardown 08 "$@"
