# objc-jupyter-wasm

Objective-C Jupyter Kernel running in the browser via WebAssembly.

## Overview

This subproject is bringing up an Objective-C Jupyter kernel that runs in the
browser via WebAssembly. The current milestone is a validated smoke slice:

1. A stable C ABI compiled to `kernel.wasm`
2. A minimal libobjc2-compatible runtime smoke module
3. A JavaScript/JupyterLite layer that loads WASM, passes JSON requests, and parses JSON replies
4. A static browser smoke site that exercises the worker and WASM asset path

Full Objective-C compilation, GNUstep Foundation, and stateful browser-side cell
execution are planned follow-up layers.

Based on research:
- LLVM PR #169043 (merged 2026-02-27): Adds ObjC Wasm support
- GNUstep libobjc2: Portable ObjC runtime
- xeus-wasm / c2wasm: Patterns for WASM kernels in browsers

## Architecture

```
Browser (JupyterLab UI)
  └── Web Worker (Kernel)
        ├── kernel.wasm         (stable smoke ABI)
        ├── libobjc2.wasm       (runtime-shaped smoke artifact)
        └── clang.wasm          (future ObjC compiler layer)
```

## Quick Start

### Prerequisites
- Nix
- Node.js >= 18.x for the smoke harness

### Build

```bash
cd /Users/jack/Software/garazyk

# Build the current smoke slice
bash scripts/build-all.sh

# Or build individually
bash scripts/wasm/build-runtime-wasm.sh
bash scripts/wasm/build-kernel-wasm.sh

# Direct Nix builds
nix build ./objc-jupyter-wasm#libobjc2-wasm
nix build ./objc-jupyter-wasm#kernel-wasm
```

`scripts/wasm/build-clang-wasm.sh` is intentionally a blocker for now. The old
script tried to turn a host `clang` binary into WASM, which is not a valid build
path. `clang.wasm` is tracked as the next compiler layer.

### Build The Browser Smoke Site

```bash
nix build ./objc-jupyter-wasm#jupyterlite-smoke-site
node objc-jupyter-wasm/tests/browser-smoke.mjs result
```

The packaged JupyterLite integration is registered from `src/index.ts`.
`jupyterlite/kernel.js` remains only as a static-demo helper for direct local
serving during bring-up.

## Directory Structure

| Path | Purpose |
|------|---------|
| `compiler/` | Built runtime/compiler artifacts copied by helper scripts |
| `kernel/` | ObjC Jupyter kernel implementation |
| `runtime/` | Minimal libobjc2-compatible smoke runtime |
| `js/` | JavaScript/TypeScript kernel layer |
| `src/` | JupyterLite extension registration |
| `jupyterlite/` | Static demo helper (kernel.js, kernelspec.json) |
| `objc_jupyter_wasm/` | Python package and labextension install target |
| `demo/` | Demo notebooks |
| `scripts/wasm/` | Build scripts for WASM targets |
| `tests/` | Node smoke harness |

## Features

- [x] Stable C ABI loaded from `kernel.wasm`
- [x] JSON request/reply smoke execution
- [x] Node smoke harness
- [x] Browser worker smoke harness
- [ ] Full JupyterLite notebook execution
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

## Nix Build

Nix is the authoritative build path for the current milestone. The flake provides:

- **Dev shells** with all WASM tooling pre-configured
- **Derivations** for `libobjc2-wasm` and `kernel-wasm`
- **Derivations** for the browser smoke site and pinned libobjc2 source probe
- **Checks** for WASM validation, JavaScript syntax, smoke-site assets, and the Node smoke harness

### Quick Start with Nix

```bash
# Enter default dev shell (all tools)
nix develop --impure path:.

# Or use a specific shell:
nix develop --impure .#wasm-emscripten  # Emscripten for browser builds
nix develop --impure .#wasm-wasi        # WASI cross-compilation

# Build WASM artifacts
nix build .#libobjc2-wasm
nix build .#kernel-wasm
nix build .#jupyterlite-smoke-site

# Evaluate checks without building
nix flake check --no-build

# Run the full checks
nix flake check
```

### Dev Shells

| Shell | Purpose | Tools |
|-------|---------|-------|
| `default` | All WASM tools | emscripten, clang, wabt, binaryen, wasmtime, zig |
| `wasm-emscripten` | Future browser compiler builds | emscripten |
| `wasm-wasi` | WASI cross-compilation | clang 21, lld, wasm tools |

### LLVM Version Notes

- **nixpkgs-unstable** ships LLVM 21 as the latest
- **LLVM PR #169043** (ObjC WASM codegen) requires LLVM 22+
- **Emscripten 5.0.6** bundles LLVM 22 — use this for ObjC `.m` files
- **WASI path** (clang `--target=wasm32-wasi`) works for C files with LLVM 21

### Current ABI

`kernel.wasm` exports:

- `objc_kernel_init()`
- `objc_kernel_info_json()`
- `objc_kernel_execute_json(char *request_json)`
- `objc_kernel_complete_json(char *request_json)`
- `objc_kernel_inspect_json(char *request_json)`
- `objc_kernel_free(char *)`
- `objc_kernel_request_buffer()`
- `objc_kernel_request_buffer_size()`

The request-buffer helpers are used by JavaScript to marshal strings into WASM
memory before calling the JSON ABI.

Requests are validated as small JSON objects. Malformed JSON, missing `code`,
non-string `code`, and oversized code payloads return structured
`{"status":"error", ...}` replies while preserving valid JSON output.

### JupyterLite Extension Packaging

The extension has both Node and Python package metadata:

```bash
cd objc-jupyter-wasm
npm install
npm run build
python -m build
```

`npm run build` compiles TypeScript, runs the JupyterLab prebuilt-extension
builder, and copies `kernel.wasm` plus `libobjc2.wasm` into
`objc_jupyter_wasm/labextension/static/kernel/`.

### Troubleshooting

**"invalid thread model 'single'"**: wasilibc cannot be built on host platforms. Use the `wasm-emscripten` shell instead, which bundles a complete WASM toolchain.

**LLVM version mismatch**: Emscripten 5.0.6 expects LLVM 22. The nixpkgs emscripten package bundles the correct LLVM version automatically.
