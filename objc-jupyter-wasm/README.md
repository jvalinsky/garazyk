# objc-jupyter-wasm

Objective-C Jupyter Kernel running in the browser via WebAssembly.

## Overview

This subproject is bringing up an Objective-C Jupyter kernel that runs in the browser via
WebAssembly. The current milestone is a validated smoke slice:

1. A stable C ABI compiled to `kernel.wasm`
2. A minimal libobjc2-compatible runtime smoke module
3. A JavaScript/JupyterLite layer that loads WASM, passes JSON requests, and parses JSON replies
4. A static browser smoke site that exercises the worker and WASM asset path

Full Objective-C compilation and GNUstep Foundation are planned follow-up layers. The smoke kernel
remains the protocol proving ground; production Objective-C cells should run through a separate
compile plane that targets `wasm32-unknown-emscripten` side modules.

Status as of April 30, 2026:

- Objective-C WebAssembly support is not upstream in LLVM. PR #169043 was closed unmerged; PR
  #183753 is the active open path.
- Browser-executed Objective-C cells should target Emscripten dynamic linking, not raw WASI dynamic
  loading.
- In-browser `clang.wasm` is optional/offline future work, not the default execution path.

## Architecture

```
Browser (JupyterLab UI)
  └── Web Worker (Kernel)
        ├── kernel.wasm         (stable smoke ABI and future main module)
        └── side modules        (future compiled Objective-C cells)

Compile service / CI artifact cache
  └── wasm32-unknown-emscripten SIDE_MODULE=2 cell artifacts
```

## Quick Start

### Prerequisites

- Nix
- Node.js >= 18.x for the smoke harness

### Build

```bash
cd .

# Build the current smoke slice
bash scripts/build-all.sh

# Or build individually
bash scripts/wasm/build-runtime-wasm.sh
bash scripts/wasm/build-kernel-wasm.sh

# Direct Nix builds
nix build ./objc-jupyter-wasm#libobjc2-wasm-full
nix build ./objc-jupyter-wasm#kernel-wasm
```

`scripts/wasm/build-clang-wasm.sh` is intentionally a blocker for now. The old script tried to turn
a host `clang` binary into WASM, which is not a valid build path. `clang.wasm` is tracked as the
next compiler layer.

### Build The Browser Smoke Site

```bash
nix build ./objc-jupyter-wasm#jupyterlite-smoke-site
node objc-jupyter-wasm/tests/browser-smoke.mjs result
```

The packaged JupyterLite integration is registered from `src/index.ts`. `jupyterlite/kernel.js`
remains only as a static-demo helper for direct local serving during bring-up.

## Directory Structure

| Path                 | Purpose                                                   |
| -------------------- | --------------------------------------------------------- |
| `compiler/`          | Built runtime/compiler artifacts copied by helper scripts |
| `kernel/`            | ObjC Jupyter kernel implementation                        |
| `runtime/`           | Minimal libobjc2-compatible smoke runtime                 |
| `js/`                | JavaScript/TypeScript kernel layer                        |
| `src/`               | JupyterLite extension registration                        |
| `jupyterlite/`       | Static demo helper (kernel.js, kernelspec.json)           |
| `objc_jupyter_wasm/` | Python package and labextension install target            |
| `demo/`              | Demo notebooks                                            |
| `scripts/wasm/`      | Build scripts for WASM targets                            |
| `tests/`             | Node smoke harness                                        |

## Features

- [x] Stable C ABI loaded from `kernel.wasm`
- [x] JSON request/reply smoke execution
- [x] Node smoke harness
- [x] Browser worker smoke harness
- [x] Full JupyterLite notebook execution protocol path
- [x] NSLog capture to IOPub stream
- [x] Worker init, timeout, stale-message, and retry handling
- [x] Browser WASI preview1 host shim for stdio, random, clocks, fd stats, and env
- [x] Length-delimited allocated request/response ABI
- [ ] Compile service or CI-produced Objective-C artifact cache
- [ ] Emscripten main module plus `SIDE_MODULE=2` cell loading
- [ ] Interactive compiled Objective-C evaluation in browser
- [ ] Variable inspection across cells
- [ ] Code completion
- [ ] Object introspection
- [ ] Exception handling with Jupyter error messages

## References

- LLVM PR #169043: closed unmerged ObjC WebAssembly attempt
- LLVM PR #183753: active ObjC WebAssembly codegen path
- GNUstep libobjc2: https://github.com/gnustep/libobjc2
- GNUstep Base: https://github.com/gnustep/libs-base
- Emscripten dynamic linking: https://emscripten.org/docs/compiling/Dynamic-Linking.html
- Emscripten exceptions: https://emscripten.org/docs/porting/exceptions.html
- Jupyter messaging: https://jupyter-client.readthedocs.io/en/latest/messaging.html
- JupyterLite custom kernels:
  https://jupyterlite.readthedocs.io/en/stable/howto/extensions/kernel.html
- xeus-wasm: https://github.com/jupyter-xeus/xeus-wasm
- c2wasm: https://github.com/divsmith/c2wasm
- WasmPatch: https://github.com/everettjf/WasmPatch

## Nix Build

Nix is the authoritative build path for the current milestone. The flake provides:

- **Dev shells** with all WASM tooling pre-configured
- **Derivations** for `libobjc2-wasm-full` and `kernel-wasm`
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
nix build .#libobjc2-wasm-full
nix build .#kernel-wasm
nix build .#jupyterlite-smoke-site

# Evaluate checks without building
nix flake check --no-build

# Run the full checks
nix flake check
```

### Dev Shells

| Shell             | Purpose                        | Tools                                            |
| ----------------- | ------------------------------ | ------------------------------------------------ |
| `default`         | All WASM tools                 | emscripten, clang, wabt, binaryen, wasmtime, zig |
| `wasm-emscripten` | Future browser compiler builds | emscripten                                       |
| `wasm-wasi`       | WASI cross-compilation         | clang 21, lld, wasm tools                        |

### LLVM Version Notes

- **nixpkgs-unstable** ships LLVM 21 as the latest
- **Objective-C WASM codegen** is still pending upstream LLVM work.
- **Future compiled cells** target `wasm32-unknown-emscripten` with `-fobjc-runtime=gnustep-2.2`,
  `-fwasm-exceptions`, `-sWASM_LEGACY_EXCEPTIONS=0`, `-fblocks`, and
  `-fconstant-string-class=NSConstantString`.
- **Current smoke path** uses WASI for C ABI validation only.

### Current ABI

`kernel.wasm` exports:

- `objc_kernel_init()`
- `objc_kernel_max_request_bytes()`
- `objc_kernel_max_response_bytes()`
- `objc_kernel_alloc(unsigned int size)`
- `objc_kernel_free(void *ptr)`
- `objc_kernel_info_json(unsigned int *out_ptr_ptr, unsigned int *out_len_ptr)`
- `objc_kernel_execute_json(const unsigned char *request_ptr, unsigned int request_len, unsigned int *out_ptr_ptr, unsigned int *out_len_ptr)`
- `objc_kernel_complete_json(const unsigned char *request_ptr, unsigned int request_len, unsigned int *out_ptr_ptr, unsigned int *out_len_ptr)`
- `objc_kernel_inspect_json(const unsigned char *request_ptr, unsigned int request_len, unsigned int *out_ptr_ptr, unsigned int *out_len_ptr)`

JavaScript now allocates request bytes explicitly, passes byte lengths into the module, and receives
allocated response buffers plus explicit lengths back. Transport failures return integer status
codes (`INVALID_ARGUMENT`, `REQUEST_TOO_LARGE`, `RESPONSE_TOO_LARGE`, `OOM`, `INTERNAL_ERROR`);
domain failures still return structured JSON payloads.

The packaged labextension and smoke site also emit `runtime-manifest.json` alongside a
content-hashed `kernel/kernel.<sha256>.wasm` URL, plus a stable `kernel/kernel.wasm` compatibility
alias for debugging and cache clearing.

### JupyterLite Extension Packaging

The extension has both Node and Python package metadata:

```bash
cd objc-jupyter-wasm
npm install
npm run build
python -m build
```

`npm run build` compiles TypeScript, runs the JupyterLab prebuilt-extension builder, and copies only
the runtime `kernel.wasm` into `objc_jupyter_wasm/labextension/static/kernel/`. Worker and loader
chunks are owned by webpack.

### Future Compile Plane

The production architecture is a persistent Emscripten main module containing libobjc2, allocator,
filesystem, runtime host ABI, and the curated Foundation subset. Each cell is compiled by a service
or CI artifact cache into a uniquely named `SIDE_MODULE=2` artifact with a generated `cell_<id>_run`
C ABI shim and loaded with async `emscripten_dlopen`. Unload is best-effort; kernel restart is the
only true cleanup for Objective-C class state, side-module table slots, static data, and leaked
runtime state.

The first runtime gates are libobjc2 dispatch, selector lookup, allocation,
retain/release/autorelease, typed IMP dispatch, constant strings, then a curated micro-base
(`NSObject`, autorelease pool, `NSString`, `NSData`, collections, `NSNumber`/`NSValue`, and
`NSLog`). Heavy GNUstep Base features stay disabled until those gates pass.

### Troubleshooting

**"invalid thread model 'single'"**: wasilibc cannot be built on host platforms. Use the
`wasm-emscripten` shell instead, which bundles a complete WASM toolchain.

**LLVM version mismatch**: Emscripten 5.0.6 expects LLVM 22. The nixpkgs emscripten package bundles
the correct LLVM version automatically.
