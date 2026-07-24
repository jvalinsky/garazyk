# ADR 0011: WASM Kernel Compiled-Cell Plane (Emscripten)

## Status

Accepted (Active Development) — 2026-07-23 (Workstream 05 E1)

## Context

ADR 0010 deferred the Emscripten compiled-cell plane to focus on the capability baseline for the interpreted `wasi-libc` kernel. The interpreter handles JSON messaging, AST parsing, and basic evaluation via `libobjc2`, but it cannot execute arbitrary compiled code, handle C++ integrations, or leverage Emscripten's rich Web API bindings.

To achieve production parity with standard Jupyter kernels and support high-performance Objective-C execution in the browser, we must implement the "compiled-cell plane":
1. The kernel and `libobjc2` must be compiled as an Emscripten `MAIN_MODULE=1` (or `2`).
2. Notebook cells will be compiled out-of-band (via a compile service or artifact cache) into `SIDE_MODULE=2` WASM artifacts.
3. The kernel will dynamically load these side modules using `emscripten_dlopen` or `dlopen` and execute a standardized entry point (`cell_<id>_run()`).

This requires migrating the current kernel build from `wasm32-wasi` (using `clang --target=wasm32-wasi`) to `wasm32-unknown-emscripten` (using `emcc`).

## Decision

We will implement the compiled-cell plane in phased slices to minimize disruption to the existing stable `kernel.wasm`:

1.  **Phase A: Emscripten Toolchain Migration.** 
    *   Update `flake.nix` and build scripts to compile `libobjc2` and `kernel.c` using `emcc` (`-s MAIN_MODULE=1` or `2`).
    *   Replace WASI `proc_exit` and host imports with Emscripten's JS library equivalents (`mergeInto(LibraryManager.library, ...)`).
    *   Ensure the existing JSON request/response ABI and interpreter still pass the 91/91 runtime gap probes under Emscripten.

2.  **Phase B: Dynamic Loading Bridge.**
    *   Export a new ABI `objc_kernel_load_cell(const char *path, const char *symbol)` that wraps `dlopen` and `dlsym`.
    *   Modify `js/wasm-loader.js` to initialize the Emscripten runtime (using the generated JS glue code) and provide a virtual filesystem (MEMFS) to place cell artifacts for `dlopen`.

3.  **Phase C: Side-Module Prototyping.**
    *   Write a mock `SIDE_MODULE=2` C file.
    *   Compile it using `emcc -s SIDE_MODULE=2`.
    *   Load it in a Node.js smoke test via the kernel and verify execution.

4.  **Phase D: Objective-C Cell Compilation.**
    *   Define the Objective-C compiler flags (`-fobjc-runtime=gnustep-2.2 -fwasm-exceptions`) for side modules.
    *   Implement the cell wrapper (`cell_<id>_run()`).

## Consequences

*   **Build Complexity:** The build shifts from raw LLVM/WASI to the Emscripten SDK. Nix derivations will need to use `pkgs.emscripten`.
*   **Artifact Size:** Emscripten main modules are larger due to the JS glue code.
*   **Memory:** `dlopen` requires memory growth (`ALLOW_MEMORY_GROWTH=1`) and function pointer table adjustments.
*   **Interop:** We can drop the custom `wasm_stubs.c` WASI shims in favor of Emscripten's POSIX support.
