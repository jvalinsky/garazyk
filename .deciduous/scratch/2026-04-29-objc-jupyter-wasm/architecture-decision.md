# Architecture Decision Record

Date: 2026-04-29

## Node Links
- Decision nodes: # (fill in after creation)

## Decisions

### D1: Runtime Selection
**Decision:** Use GNUstep libobjc2

**Alternatives considered:**
1. **Apple objc4** — Rejected: macOS-only, complex dependencies, not Emscripten-compatible
2. **GNUstep libobjc2** — Chosen: portable, Emscripten-compatible, active maintenance, LLVM PR #169043 tested with it
3. **Custom minimal runtime** — Rejected: high effort, likely incomplete, no Foundation integration

**Consequences:**
- (+) Portable across platforms
- (+) Emscripten precedent (WasmPatch uses it)
- (+) Proven WASM compilation path (LLVM PR #169043)
- (-) Larger WASM binary than custom minimal
- (-) Depends on GNUstep maintenance

---

### D2: Build Toolchain
**Decision:** Emscripten

**Alternatives considered:**
1. **LLVM wasm backend directly** — Complex setup, no POSIX compatibility layer
2. **wasm-pack (Rust-focused)** — Not relevant for ObjC
3. **Emscripten** — Chosen: Mature, well-documented, POSIX compatibility, `-fobjc-runtime=gnustep-2.2` support

**Consequences:**
- (+) Mature, well-documented
- (+) POSIX compatibility layer (WASI)
- (+) Good C/ObjC support
- (-) Learning curve for Emscripten-specific flags
- (-) Larger toolchain dependency

---

### D3: Jupyter Transport
**Decision:** postMessage + IFrame

**Alternatives considered:**
1. **WebSocket** — Requires server, not pure browser
2. **HTTP polling** — Too slow for REPL
3. **postMessage + IFrame** — Chosen: Works in pure browser environment, JupyterLite pattern

**Consequences:**
- (+) Works in pure browser environment
- (+) JupyterLite can proxy via kernel.js
- (+) No server required
- (-) Requires IFrame bridge for cross-origin
- (-) Needs COOP/COEP headers for SharedArrayBuffer

---

### D4: Runtime Scope
**Decision:** Minimal stub (no Foundation)

**Consequences:**
- (+) Smaller WASM binary
- (+) Faster compilation
- (-) Limited ObjC standard library
- (-) NSString/NSArray must be implemented separately

**Revision:** Changed to include minimal Foundation (NSString, NSArray, NSDictionary) after further research showed WasmPatch pattern needs basic classes.

---

### D5: Kernel Template
**Decision:** xeus-like C wrapper pattern

**Consequences:**
- (+) Proven pattern (xeus-wasm compiles to WASM)
- (+) Clear separation of concerns
- (+) Jupyter protocol already defined in C++
- (-) Need to port to ObjC
- (-) Additional abstraction layer

---

### D6: WASM Compiler Strategy
**Decision:** Build clang to WASM (c2wasm pattern)

**Alternatives:**
1. **Interpret ObjC in browser** — Too complex, slow
2. **JIT compilation** — WASM doesn't support JIT (yet)
3. **Ahead-of-time compile** — Chosen: Compile clang to WASM, use it to compile ObjC snippets

**Consequences:**
- (+) Self-hosting possible (c2wasm proves it)
- (+) Full ObjC support via clang
- (-) Large compiler binary (~2-5MB)
- (-) Compilation latency for each cell

---

### D7: JavaScript Layer
**Decision:** TypeScript implementing JupyterLite IKernel

**Consequences:**
- (+) Type-safe kernel interface
- (+) JupyterLite integration patterns available
- (+) Web Worker isolation for UI thread
- (-) Additional build step (TypeScript → JS)
