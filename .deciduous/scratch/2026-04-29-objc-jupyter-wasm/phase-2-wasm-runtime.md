# Phase 2 - WASM Runtime Build

Date: 2026-04-29
Action node: (fill in from deciduous)

## Scope
- Set up Emscripten build environment
- Cross-compile GNUstep libobjc2 to WASM
- Create minimal runtime stub
- Build clang.wasm from LLVM

## Node Links
- Action node: # (fill in after creation)
- Related decisions: # (D1: Runtime - GNUstep libobjc2, D2: Build Toolchain - Emscripten)

## Emscripten Setup

```bash
# Install Emscripten SDK
git clone https://github.com/emscripten-core/emsdk.git
cd emsdk
./emsdk install latest
./emsdk activate latest
source ./emsdk_env.sh

# Verify
emcc --version  # Should be ≥ 4.0.0
```

## libobjc2 Compilation

```bash
# Clone GNUstep libobjc2
git clone https://github.com/gnustep/libobjc2.git
cd libobjc2

# Configure with Emscripten toolchain
emcmake cmake -B build-wasm \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DOLDABI_COMPAT=OFF \
  -DEMBEDDED_BLOCKS_RUNTIME=OFF \
  -DTESTS=OFF

# Build
cd build-wasm
emmake ninja

# Compile to WASM
emcc -O2 \
  -target wasm32-unknown-emscripten \
  -fobjc-runtime=gnustep-2.2 \
  -fwasm-exceptions \
  -D__EMSCRIPTEN__ \
  -DNO_EXCEPTION_TRAMPOLINES \
  -DNO_ARC \
  -I. \
  -o libobjc2.wasm \
  class.c object.c selector.c protocol.c block.c

echo "libobjc2.wasm built: $(du -h libobjc2.wasm | cut -f1)"
```

## Minimal Foundation Subset

```bash
# Clone GNUstep libs-base
git clone https://github.com/gnustep/libs-base.git
cd libs-base

# Configure minimal build
emcmake cmake -B build-wasm \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DGNUSTEP_BASE_WITH_ICU=OFF \
  -DGNUSTEP_BASE_WITH_LIBXML=OFF \
  -DGNUSTEP_BASE_WITH_OPENSSL=OFF \
  -DTESTS=OFF

# Build only needed classes
emcc -O2 \
  -target wasm32-unknown-emscripten \
  -fobjc-runtime=gnustep-2.2 \
  -o Foundation.wasm \
  NSString.m NSArray.m NSDictionary.m
```

## clang.wasm Build

```bash
# Build clang to WASM (based on c2wasm pattern)
emcc -O3 -s WASM=1 -s ALLOW_MEMORY_GROWTH=1 \
  --target=wasm32-unknown-emscripten \
  -fobjc-runtime=gnustep-2.2 \
  -fwasm-exceptions \
  -mllvm -wasm-enable-sjlj \
  -mllvm -disable-lsr \
  -D__EMSCRIPTEN__ \
  -I${LLVM_SOURCE}/include \
  -o clang.wasm \
  ${LLVM_SOURCE}/clang/tools/driver/cc1_main.cpp \
  # ... other required LLVM libs

echo "clang.wasm built: $(du -h clang.wasm | cut -f1)"
```

## Build Artifacts
- [ ] libobjc2.wasm (WASM-compatible ObjC runtime)
- [ ] Foundation.wasm (Minimal Foundation subset)
- [ ] clang.wasm (ObjC compiler for WASM)
- [ ] Runtime size: ___ KB (fill in after build)

## Issues Encountered
- [ ] Fill in any compilation errors and fixes
- [ ] LLVM version compatibility issues
- [ ] Emscripten flag deprecation warnings

## Build Commands Reference

| Flag | Purpose |
|------|---------|
| `-fobjc-runtime=gnustep-2.2` | Select GNUstep v2 ObjC runtime |
| `-fwasm-exceptions` | Enable Wasm-compatible ObjC exception handling |
| `-target wasm32-unknown-emscripten` | Target Emscripten Wasm |
| `-mllvm -wasm-enable-sjlj` | Setjmp/longjmp for ObjC exceptions |
| `-s WASM=1` | Output WASM binary (not JavaScript) |
| `-s ALLOW_MEMORY_GROWTH=1` | Allow dynamic memory growth |
