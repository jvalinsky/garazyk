#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
exec deno run --allow-read "$ROOT/scripts/dev/check_module_boundaries.ts" "$ROOT"
