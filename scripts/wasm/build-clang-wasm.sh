#!/bin/bash
set -euo pipefail

# build-clang-wasm.sh: placeholder for the later in-browser compiler layer.
#
# The previous script attempted to compile an already-built host clang binary
# into WebAssembly, which is not a valid clang.wasm build path. Keep this as an
# explicit blocker until node 749 is implemented with a real LLVM/Emscripten
# build.

echo "clang.wasm is not implemented in the current smoke milestone."
echo "Next layer: build LLVM/Clang from source with an ObjC/WASM-capable toolchain."
exit 2
