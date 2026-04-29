#!/bin/bash
set -euo pipefail

# build-clang-wasm.sh: Build clang/LLVM to WASM for Objective-C
# Requires: Emscripten SDK with LLVM ≥ 22.0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WASM_DIR="$PROJECT_ROOT/objc-jupyter-wasm/compiler"
BUILD_DIR="$WASM_DIR/build-clang"

echo "=== Building clang.wasm (Objective-C compiler for WASM) ==="

# Check prerequisites
if ! command -v emcc >/dev/null 2>&1; then
    echo "ERROR: emcc not found. Source emsdk_env.sh first."
    echo "  source \$EMSDK/emsdk_env.sh"
    exit 1
fi

# Create build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Configure with Emscripten toolchain
emcmake cmake -G Ninja \
    -S "$PROJECT_ROOT/llvm-project/llvm" \
    -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=MinSizeRel \
    -DLLVM_TARGETS_TO_BUILD=WebAssembly \
    -DLLVM_ENABLE_PROJECTS="clang;lld" \
    -DLLVM_PARALLEL_LINK_JOBS=1 \
    -DLLVM_BUILD_TOOLS=ON \
    -DLLVM_BUILD_UTILS=OFF \
    -DLLVM_BUILD_TESTS=OFF \
    -DLLVM_BUILD_EXAMPLES=OFF \
    -DCLANG_ENABLE_ARCMT=OFF \
    -DCLANG_ENABLE_STATIC_ANALYZER=OFF

# Build clang (this will take a while)
ninja clang

# Compile clang to WASM using Emscripten
echo "=== Compiling clang to WASM ==="

emcc -O3 \
    -s WASM=1 \
    -s ALLOW_MEMORY_GROWTH=1 \
    -s EXPORTED_FUNCTIONS='["_main", "_executeCompiler"]' \
    -s EXPORTED_RUNTIME_METHODS='["ccall", "cwrap"]' \
    --target=wasm32-unknown-emscripten \
    -fobjc-runtime=gnustep-2.2 \
    -fwasm-exceptions \
    -mllvm -wasm-enable-sjlj \
    -mllvm -disable-lsr \
    -D__EMSCRIPTEN__ \
    -I"$BUILD_DIR/include" \
    -o "$WASM_DIR/clang.wasm" \
    "$BUILD_DIR/bin/clang"

echo "=== clang.wasm built: $(du -h "$WASM_DIR/clang.wasm" | cut -f1) ==="
echo "Output: $WASM_DIR/clang.wasm"
