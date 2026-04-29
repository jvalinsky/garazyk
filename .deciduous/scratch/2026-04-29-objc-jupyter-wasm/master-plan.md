# objc-jupyter-wasm: Objective-C Jupyter Kernel via WASM

Date: 2026-04-29

## Goal

Run an Objective-C REPL as a Jupyter kernel inside the browser using WebAssembly,
enabling interactive Objective-C exploration without a native toolchain.

## Decision Nodes

- Goal node: # (created first)
- Architecture decision: Runtime approach (objc-js bridge vs portable objc runtime in WASM)
- Decision: WASM compilation target (bare metal vs Emscripten vs LLVM wasm backend)
- Decision: Jupyter protocol transport (WebSocket vs postMessage vs HTTP)
- Decision: ObjC runtime selection (GNUstep libobjc vs Apple objc4 vs custom minimal)

## Action Nodes

### Phase 1: Research & Discovery
- Action node: Survey existing Objective-C WASM ports and Jupyter kernel templates
- Action node: Evaluate GNUstep/libobjc编译到WASM的可行性
- Action node: Prototype minimal objc message send in WASM

### Phase 2: Architecture
- Action node: Implement WASM-compiled objc runtime stub
- Action node: Implement Jupyter kernel protocol handler (ZeroMQ-less browser transport)
- Action node: Wire REPL eval loop: Jupyter msg -> objc runtime -> response

### Phase 3: Implementation
- Action node: Build WASM module with objc runtime + stub classes
- Action node: Implement kernel.js bootstrap and Jupyter handshake
- Action node: Add code completion and introspection stubs

### Phase 4: Testing & Demo
- Action node: Create demo notebook with basic objc expressions
- Action node: Test in JupyterLab + classic notebook
- Action node: Document build pipeline and usage

## Outcome

- Outcome node: objc-jupyter-wasm builds and runs basic Objective-C expressions in browser
- Outcome node: Demo notebook published
