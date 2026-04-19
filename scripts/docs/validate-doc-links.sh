#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/../.." && pwd))"

cd "$REPO_ROOT"

python3 scripts/docs/repo_docs.py sync
python3 scripts/docs/repo_docs.py validate --internal-strict
