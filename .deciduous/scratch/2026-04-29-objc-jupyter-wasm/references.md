# References

Date: 2026-04-29

## Repositories

| Project | URL | Purpose |
|---------|-----|---------|
| **GNUstep libobjc2** | https://github.com/gnustep/libobjc2 | ObjC runtime for WASM |
| **GNUstep libs-base** | https://github.com/gnustep/libs-base | Foundation classes (subset) |
| **LLVM Project** | https://github.com/llvm/llvm-project | Clang/LLVM for WASM |
| **LLVM PR #169043** | https://github.com/llvm/llvm-project/pull/169043 | ObjC Wasm support (merged 2026-02-27) |
| **Emscripten SDK** | https://github.com/emscripten-core/emsdk | WASM cross-compilation |
| **xeus-wasm** | https://github.com/jupyter-xeus/xeus-wasm | C++ kernel → WASM pattern |
| **xeus-lite** | https://github.com/jupyterlite/xeus | JupyterLite xeus integration |
| **c2wasm** | https://github.com/divsmith/c2wasm | Self-hosting C compiler → WASM |
| **WasmPatch** | https://github.com/everettjf/WasmPatch | ObjC ↔ WASM bridging |
| **pyodide-kernel** | https://github.com/jupyterlite/pyodide-kernel | Python in WASM (reference) |
| **Wasmer clang** | https://wasmer.io/posts/clang-in-browser | clang running in browser |

## Documentation

| Topic | URL |
|-------|-----|
| Jupyter Kernel Protocol | https://jupyter-client.readthedocs.io/en/latest/messaging.html |
| JupyterLite Architecture | https://github.com/jupyterlite/jupyterlite |
| Emscripten Docs | https://emscripten.org/docs/ |
| Objective-C Runtime Guide | https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/ |
| WebAssembly Spec | https://www.w3.org/TR/wasm-core-2/ |
| WASI API | https://github.com/WebAssembly/WASI |

## Papers/Articles

| Title | Source | Key Insight |
|-------|--------|--------------|
| The States of WebAssembly (2026) | https://webassembly.org/news/2026-01-21-states-of-webassembly/ | Wasm adoption stats, new features |
| Extending Emscripten to Support ObjC (2017) | https://medium.com/tombo-blog/extending-emscripten-to-support-objective-c-running-ios-apps-on-the-web-10e54b854671 | Porting ObjC to WASM |
| LLVM ObjC Wasm Support (2025) | https://github.com/llvm/llvm-project/pull/169043 | Implementation details |

## Tools

| Tool | Version | Purpose |
|------|---------|---------|
| Emscripten SDK | ≥ 4.0.0 | WASM cross-compilation |
| LLVM/Clang | ≥ 22.0 | ObjC Wasm support (PR #169043) |
| wasi-sdk | ≥ 22.0 | Build self-hosting `clang.wasm` |
| Node.js/npm | ≥ 18.x | Browser JS layer, `@wasmer/wasi` package |
| CMake | ≥ 3.25 | Build system integration |
| Ninja | latest | Fast build tool |

## Key Research Findings

1. **LLVM PR #169043** (merged 2026-02-27): Adds ObjC Wasm support
   - Flags: `-fobjc-runtime=gnustep-2.2`, `-fwasm-exceptions`
   - Tested with libobjc2 and swift-corelibs-blocksruntime

2. **c2wasm pattern**: Self-hosting C compiler → WASM
   - ~667 KB standalone WASM binary
   - Uses WASI snapshots, no JavaScript runtime bundled
   - Proves clang can run in browser

3. **WasmPatch**: ObjC ↔ WASM bridging works
   - Compiles C to WASM, calls ObjC classes/methods dynamically
   - Works on iOS and macOS (proves concept)

4. **JupyterLite**: Runs kernels in Web Workers
   - Uses postMessage (not ZeroMQ in browser)
   - xeus-wasm proves C++ kernels compile to WASM
   - IKernel TypeScript interface for integration

5. **Build flags** (from PR #169043):
   ```bash
   emcc -target wasm32-unknown-emscripten \
     -fobjc-runtime=gnustep-2.2 \
     -fwasm-exceptions \
     -mllvm -wasm-enable-sjlj
   ```
