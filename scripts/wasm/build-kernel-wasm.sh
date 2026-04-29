#!/bin/bash
set -euo pipefail

# build-kernel-wasm.sh: Build ObjC Jupyter kernel to WASM
# Requires: libobjc2.wasm, Foundation.wasm (from build-runtime-wasm.sh)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
KERNEL_DIR="$PROJECT_ROOT/objc-jupyter-wasm/kernel"
WASM_DIR="$PROJECT_ROOT/objc-jupyter-wasm/compiler"

echo "=== Building kernel.wasm (Objective-C Jupyter kernel) ==="

# Check prerequisites
if ! command -v emcc >/dev/null 2>&1; then
    echo "ERROR: emcc not found. Source emsdk_env.sh first."
    exit 1
fi

if [ ! -f "$WASM_DIR/libobjc2.wasm" ]; then
    echo "ERROR: libobjc2.wasm not found. Run build-runtime-wasm.sh first."
    exit 1
fi

cd "$KERNEL_DIR"

# Compile kernel implementation to WASM
emcc -O2 \
    -s WASM=1 \
    -s ALLOW_MEMORY_GROWTH=1 \
    -s EXPORTED_FUNCTIONS='["_init_kernel", "_execute_code", "_complete_code", "_inspect_code"]' \
    -s EXPORTED_RUNTIME_METHODS='["ccall", "cwrap", "UTF8ToString"]' \
    --target=wasm32-unknown-emscripten \
    -fobjc-runtime=gnustep-2.2 \
    -fwasm-exceptions \
    -D__EMSCRIPTEN__ \
    -I"$WASM_DIR" \
    -L"$WASM_DIR" \
    -lobjc2 \
    -o "$KERNEL_DIR/kernel.wasm" \
    objc_kernel.m \
    objc_runtime_bridge.c

echo "=== kernel.wasm built: $(du -h "$KERNEL_DIR/kernel.wasm" | cut -f1) ==="
echo "Output: $KERNEL_DIR/kernel.wasm"

# Copy WASM files to jupyterlite directory
mkdir -p "$PROJECT_ROOT/objc-jupyter-wasm/jupyterlite/kernel"
cp "$WASM_DIR/clang.wasm" "$PROJECT_ROOT/objc-jupyter-wasm/jupyterlite/kernel/" 2>/dev/null || true
cp "$WASM_DIR/libobjc2.wasm" "$PROJECT_ROOT/objc-jupyter-wasm/jupyterlite/kernel/"
cp "$WASM_DIR/Foundation.wasm" "$PROJECT_ROOT/objc-jupyter-wasm/jupyterlite/kernel/" 2>/dev/null || true
cp "$KERNEL_DIR/kernel.wasm" "$PROJECT_ROOT/objc-jupyter-wasm/jupyterlite/kernel/"

echo "=== All WASM files copied to jupyterlite/kernel/ ==="
