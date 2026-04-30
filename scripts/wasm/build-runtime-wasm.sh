#!/bin/bash
set -euo pipefail

# build-runtime-wasm.sh: build the local libobjc2-compatible smoke runtime.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_LINK="${TMPDIR:-/tmp}/objc-jupyter-wasm-libobjc2-result"
WASM_DIR="$PROJECT_ROOT/objc-jupyter-wasm/compiler"
JUPYTER_KERNEL_DIR="$PROJECT_ROOT/objc-jupyter-wasm/jupyterlite/kernel"

echo "=== Building libobjc2.wasm smoke runtime with Nix ==="

if ! command -v nix >/dev/null 2>&1; then
    echo "ERROR: nix not found. Install Nix or use the flake dev shell."
    exit 1
fi

nix build "$PROJECT_ROOT/objc-jupyter-wasm#libobjc2-wasm-full" --out-link "$OUT_LINK"

mkdir -p "$WASM_DIR" "$JUPYTER_KERNEL_DIR"
cp "$OUT_LINK/wasm/libobjc2.wasm" "$WASM_DIR/libobjc2.wasm"
cp "$OUT_LINK/wasm/libobjc2.wasm" "$JUPYTER_KERNEL_DIR/libobjc2.wasm"

echo "Output: $WASM_DIR/libobjc2.wasm"
