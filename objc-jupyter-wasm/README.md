# objc-jupyter-wasm

Objective-C Jupyter Kernel running in the browser via WebAssembly.

## Overview

This subproject enables interactive Objective-C programming directly in the browser by compiling:
1. An Objective-C compiler (clang) to WebAssembly
2. The GNUstep Objective-C runtime (libobjc2) to WASM
3. A Jupyter kernel protocol handler to WASM

Based on research:
- LLVM PR #169043 (merged 2026-02-27): Adds ObjC Wasm support
- GNUstep libobjc2: Portable ObjC runtime
- xeus-wasm / c2wasm: Patterns for WASM kernels in browsers

## Architecture

```
Browser (JupyterLab UI)
  └── Web Worker (Kernel)
        ├── clang.wasm          (ObjC compiler)
        ├── libobjc2.wasm       (ObjC runtime)
        ├── Foundation.wasm     (Minimal Foundation)
        └── kernel.wasm         (Jupyter kernel protocol)
```

## Quick Start

### Prerequisites
- Emscripten SDK ≥ 4.0.0
- LLVM ≥ 22.0 (with ObjC Wasm support)
- Node.js ≥ 18.x
- CMake ≥ 3.25

### Build

```bash
# Source Emscripten
source $EMSDK/emsdk_env.sh

# Build all WASM components
bash scripts/build-all.sh

# Or build individually
bash scripts/wasm/build-clang-wasm.sh
bash scripts/wasm/build-runtime-wasm.sh
bash scripts/wasm/build-kernel-wasm.sh
```

### Run Demo

```bash
cd jupyterlite
python -m http.server 8000
# Open http://localhost:8000 in browser
# Select "Objective-C" kernel
```

## Directory Structure

| Path | Purpose |
|------|---------|
| `compiler/` | Clang/LLVM compiled to WASM |
| `kernel/` | ObjC Jupyter kernel implementation |
| `kernel/runtime/` | libobjc2 WASM port |
| `js/` | JavaScript/TypeScript kernel layer |
| `jupyterlite/` | JupyterLab integration files |
| `demo/` | Demo notebooks |
| `scripts/wasm/` | Build scripts for WASM targets |

## Features

- [ ] Interactive ObjC evaluation in browser
- [ ] Variable inspection across cells
- [ ] Code completion
- [ ] Object introspection
- [ ] NSLog capture to IOPub stream
- [ ] Exception handling with Jupyter error messages

## References

- LLVM PR #169043: [CodeGen][ObjC] Initial WebAssembly Support for GNUstep
- GNUstep libobjc2: https://github.com/gnustep/libobjc2
- xeus-wasm: https://github.com/jupyter-xeus/xeus-wasm
- c2wasm: https://github.com/divsmith/c2wasm
- WasmPatch: https://github.com/everettjf/WasmPatch
