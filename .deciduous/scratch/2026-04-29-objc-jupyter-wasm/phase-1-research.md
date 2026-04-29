# Phase 1 - Research & Discovery

Date: 2026-04-29
Action node: (fill in from deciduous)

## Scope
- Survey existing Objective-C WASM ports
- Evaluate GNUstep/libobjc2 compilation path
- Study xeus-wasm, pyodide patterns
- Assess feasibility of ObjC REPL in browser

## Node Links
- Action node: # (fill in after creation)
- Related decisions: # (D1, D2, D3 - fill in)

## Findings

### Existing ObjC WASM Work
- **LLVM PR #169043** (merged 2026-02-27): Adds ObjC Wasm support to clang
  - Flags: `-fobjc-runtime=gnustep-2.2`, `-fwasm-exceptions`
  - Files changed: `clang/lib/CodeGen/CGObjCGNU.cpp`, `clang/lib/Driver/ToolChains/Clang.cpp`
  
- **c2wasm** (github.com/divsmith/c2wasm): Self-hosting C compiler to WASM (~667KB)
  - Pattern: Compile clang to WASM using wasi-sdk
  - WASI harness: `wasi-harness.js` implements `wasi_snapshot_preview1`
  
- **WasmPatch** (github.com/everettjf/WasmPatch): ObjC ↔ WASM bridging
  - Hot-fix iOS/macOS apps using WASM payloads
  - Compiles C to WASM, calls ObjC classes/methods dynamically

### Jupyter WASM Kernels (for pattern reference)
- **xeus-lite**: C++ kernel framework compiled to WASM via Emscripten
  - Runs in Web Workers
  - Uses postMessage (not ZeroMQ in browser)
  - Implements Jupyter protocol: execute_request, complete_request, inspect_request
  
- **pyodide**: Python distribution compiled to WASM
  - `jupyterlite-pyodide-kernel` package
  - Pattern: WASM module + JS kernel layer

### GNUstep Emscripten Experiments
- **GNUstep libobjc2** ≥ 2.3: Portable ObjC runtime
  - Can be compiled with `-fobjc-runtime=gnustep-2.2`
  - Tested with LLVM PR #169043
  
- **GNUstep libs-base** ≥ 1.29: Foundation classes
  - Minimal subset: NSString, NSArray, NSDictionary
  - Disable: ICU, libxml, OpenSSL for smaller WASM

## Feasibility Assessment
- [x] Runtime compilation: LLVM PR merged, flags available
- [x] Message passing: xeus-lite proves postMessage works
- [x] ObjC REPL in browser: WasmPatch proves ObjC ↔ WASM works
- [ ] Full Foundation: Too large, use minimal subset

## Risks
1. ObjC runtime size when compiled to WASM (~500KB-2MB estimated)
2. Browser memory limits for runtime + compiler
3. Jupyter protocol complexity without ZeroMQ

## Decision Needed
- [ ] Choose runtime (libobjc2 vs custom minimal)
- [ ] Choose transport mechanism (postMessage vs WebSocket vs IFrame)
- [ ] Kernel implementation approach (C wrapper vs C++ xeus vs from scratch)
