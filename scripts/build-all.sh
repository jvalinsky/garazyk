#!/bin/bash
set -euo pipefail

# build-all.sh: Master orchestrator for objc-jupyter-wasm
# Builds all WASM components in correct order

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WASM_SCRIPTS="$SCRIPT_DIR/wasm"

echo "=========================================="
echo "  objc-jupyter-wasm Build Orchestrator"
echo "=========================================="

# Check Emscripten
if [ -z "${EMSDK+x}" ] && [ ! -f "$HOME/emsdk/emsdk_env.sh" ]; then
    echo "WARNING: EMSDK not set. Attempting to find emsdk..."
    if [ -d "$HOME/emsdk" ]; then
        source "$HOME/emsdk/emsdk_env.sh"
    else
        echo "ERROR: Emscripten SDK not found."
        echo "  Install: git clone https://github.com/emscripten-core/emsdk.git"
        echo "         cd emsdk && ./emsdk install latest && ./emsdk activate latest"
        exit 1
    fi
fi

# Step 1: Build clang.wasm (ObjC compiler)
echo ""
echo "[1/3] Building clang.wasm (ObjC compiler for WASM)..."
bash "$WASM_SCRIPTS/build-clang-wasm.sh"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to build clang.wasm"
    exit 1
fi

# Step 2: Build libobjc2.wasm + Foundation.wasm
echo ""
echo "[2/3] Building libobjc2.wasm + Foundation.wasm (ObjC runtime)..."
bash "$WASM_SCRIPTS/build-runtime-wasm.sh"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to build runtime WASM"
    exit 1
fi

# Step 3: Build kernel.wasm
echo ""
echo "[3/3] Building kernel.wasm (Jupyter kernel)..."
bash "$WASM_SCRIPTS/build-kernel-wasm.sh"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to build kernel.wasm"
    exit 1
fi

echo ""
echo "=========================================="
echo "  Build Complete!"
echo "=========================================="
echo ""
echo "Output files:"
echo "  - objc-jupyter-wasm/compiler/clang.wasm"
echo "  - objc-jupyter-wasm/compiler/libobjc2.wasm"
echo "  - objc-jupyter-wasm/compiler/Foundation.wasm"
echo "  - objc-jupyter-wasm/kernel/kernel.wasm"
echo ""
echo "Next: cd objc-jupyter-wasm/jupyterlite && python -m http.server 8000"
