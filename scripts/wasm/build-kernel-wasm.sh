#!/bin/bash
set -euo pipefail

# build-kernel-wasm.sh: build the stable C ABI smoke kernel with Nix.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_LINK="${TMPDIR:-/tmp}/objc-jupyter-wasm-kernel-result"
KERNEL_DIR="$PROJECT_ROOT/objc-jupyter-wasm/kernel"
JUPYTER_KERNEL_DIR="$PROJECT_ROOT/objc-jupyter-wasm/jupyterlite/kernel"

echo "=== Building kernel.wasm smoke ABI with Nix ==="

if ! command -v nix >/dev/null 2>&1; then
    echo "ERROR: nix not found. Install Nix or use the flake dev shell."
    exit 1
fi

nix build "$PROJECT_ROOT/objc-jupyter-wasm#kernel-wasm" --out-link "$OUT_LINK"

mkdir -p "$JUPYTER_KERNEL_DIR"
cp "$OUT_LINK/wasm/kernel.wasm" "$KERNEL_DIR/kernel.wasm"
cp "$OUT_LINK/wasm/kernel.wasm" "$JUPYTER_KERNEL_DIR/kernel.wasm"

node "$PROJECT_ROOT/objc-jupyter-wasm/tests/kernel-smoke.mjs" "$KERNEL_DIR/kernel.wasm"

echo "Output: $KERNEL_DIR/kernel.wasm"
