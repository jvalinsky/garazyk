#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/../.." && pwd))"

cd "$REPO_ROOT"

deno run -A scripts/docs/repo_docs.ts sync
deno run -A scripts/docs/repo_docs.ts validate --internal-strict
