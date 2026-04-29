#!/bin/bash
set -euo pipefail

# build-jupyterlite-smoke.sh: build the browser smoke site with Nix-owned WASM assets.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_LINK="${TMPDIR:-/tmp}/objc-jupyter-wasm-site-result"
SITE_DIR="$PROJECT_ROOT/objc-jupyter-wasm/dist/jupyterlite-smoke"

echo "=== Building Objective-C JupyterLite browser smoke site with Nix ==="

if ! command -v nix >/dev/null 2>&1; then
    echo "ERROR: nix not found. Install Nix or use the flake dev shell."
    exit 1
fi

nix build "$PROJECT_ROOT/objc-jupyter-wasm#jupyterlite-smoke-site" --out-link "$OUT_LINK"

rm -rf "$SITE_DIR"
mkdir -p "$(dirname "$SITE_DIR")"
cp -R "$OUT_LINK" "$SITE_DIR"

echo "Output: $SITE_DIR"
