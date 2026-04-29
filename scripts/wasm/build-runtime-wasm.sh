#!/bin/bash
set -euo pipefail

# build-runtime-wasm.sh: Build GNUstep libobjc2 + minimal Foundation to WASM
# Requires: Emscripten SDK, GNUstep libobjc2 ≥ 2.3

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WASM_DIR="$PROJECT_ROOT/objc-jupyter-wasm/compiler"
RUNTIME_DIR="$PROJECT_ROOT/objc-jupyter-wasm/kernel/runtime"

echo "=== Building libobjc2.wasm (Objective-C runtime for WASM) ==="

# Check prerequisites
if ! command -v emcc >/dev/null 2>&1; then
    echo "ERROR: emcc not found. Source emsdk_env.sh first."
    exit 1
fi

# Clone libobjc2 if not present
if [ ! -d "$RUNTIME_DIR/libobjc2" ]; then
    echo "Cloning GNUstep libobjc2..."
    git clone https://github.com/gnustep/libobjc2.git "$RUNTIME_DIR/libobjc2"
fi

cd "$RUNTIME_DIR/libobjc2"

# Build with Emscripten
emcmake cmake -G Ninja \
    -B build-wasm \
    -DCMAKE_BUILD_TYPE=MinSizeRel \
    -DOLDABI_COMPAT=OFF \
    -DEMBEDDED_BLOCKS_RUNTIME=OFF \
    -DTESTS=OFF

ninja -C build-wasm

# Compile to WASM
echo "=== Compiling libobjc2 to WASM ==="

emcc -O2 \
    -s WASM=1 \
    -s ALLOW_MEMORY_GROWTH=1 \
    --target=wasm32-unknown-emscripten \
    -fobjc-runtime=gnustep-2.2 \
    -fwasm-exceptions \
    -D__EMSCRIPTEN__ \
    -DNO_EXCEPTION_TRAMPOLINES \
    -DNO_ARC \
    -I. \
    -I"$RUNTIME_DIR/libobjc2" \
    -o "$WASM_DIR/libobjc2.wasm" \
    class.c object.c selector.c protocol.c block.c

echo "=== libobjc2.wasm built: $(du -h "$WASM_DIR/libobjc2.wasm" | cut -f1) ==="

# Build minimal Foundation subset
echo "=== Building Foundation.wasm (minimal subset) ==="

if [ ! -d "$RUNTIME_DIR/gnustep-base" ]; then
    echo "Cloning GNUstep Base..."
    git clone https://github.com/gnustep/libs-base.git "$RUNTIME_DIR/gnustep-base"
fi

cd "$RUNTIME_DIR/gnustep-base"

emcmake cmake -G Ninja \
    -B build-wasm \
    -DCMAKE_BUILD_TYPE=MinSizeRel \
    -DGNUSTEP_BASE_WITH_ICU=OFF \
    -DGNUSTEP_BASE_WITH_LIBXML=OFF \
    -DGNUSTEP_BASE_WITH_OPENSSL=OFF \
    -DTESTS=OFF

ninja -C build-wasm

emcc -O2 \
    --target=wasm32-unknown-emscripten \
    -fobjc-runtime=gnustep-2.2 \
    -D__EMSCRIPTEN__ \
    -I"$RUNTIME_DIR/libobjc2" \
    -o "$WASM_DIR/Foundation.wasm" \
    NSString.m NSArray.m NSDictionary.m

echo "=== Foundation.wasm built: $(du -h "$WASM_DIR/Foundation.wasm" | cut -f1) ==="
echo "Output directory: $WASM_DIR"
