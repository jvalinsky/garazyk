#!/bin/bash
set -euo pipefail

# build-all.sh: build the current objc-jupyter-wasm smoke slice.
#
# Nix is the authoritative build path. clang.wasm is intentionally not built by
# default; set INCLUDE_CLANG=1 to run the placeholder clang script once that
# later layer is ready.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WASM_SCRIPTS="$SCRIPT_DIR/wasm"

echo "=========================================="
echo "  objc-jupyter-wasm Smoke Build"
echo "=========================================="

echo ""
echo "[1/2] Building libobjc2-compatible runtime smoke module..."
bash "$WASM_SCRIPTS/build-runtime-wasm.sh"

echo ""
echo "[2/2] Building kernel.wasm smoke ABI..."
bash "$WASM_SCRIPTS/build-kernel-wasm.sh"

if [ "${INCLUDE_CLANG:-0}" = "1" ]; then
    echo ""
    echo "[optional] Building clang.wasm..."
    bash "$WASM_SCRIPTS/build-clang-wasm.sh"
fi

echo ""
echo "=========================================="
echo "  Build Complete"
echo "=========================================="
echo ""
echo "Output files:"
echo "  - $PROJECT_ROOT/objc-jupyter-wasm/compiler/libobjc2.wasm"
echo "  - $PROJECT_ROOT/objc-jupyter-wasm/kernel/kernel.wasm"
echo "  - $PROJECT_ROOT/objc-jupyter-wasm/jupyterlite/kernel/kernel.wasm"
echo ""
echo "Smoke test:"
echo "  node objc-jupyter-wasm/tests/kernel-smoke.mjs objc-jupyter-wasm/kernel/kernel.wasm"
