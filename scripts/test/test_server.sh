#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/../.." && pwd))"

echo "[INFO] test_server.sh is retired; running Docker e2e wrapper."
exec "$REPO_ROOT/scripts/test/e2e-docker-test.sh" "$@"
