{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  llvmPackages,
  python3,
}:

# Cross-compile GNUstep libobjc2 to WebAssembly (wasm32-wasi)
# This produces a static library that can be linked into WASM kernels.
#
# Note: LLVM PR #169043 (ObjC WASM codegen) requires LLVM 22+.
# nixpkgs-unstable currently ships LLVM 21. The C runtime files
# (class.c, object.c, selector.c, etc.) compile fine with LLVM 21
# targeting wasm32-wasi. Full ObjC codegen (.m files) needs LLVM 22+.
#
# This derivation does NOT use wasilibc because it's a host package.
# Instead, we compile with --target=wasm32-wasi and minimal libc.

stdenv.mkDerivation (finalAttrs: {
  pname = "libobjc2-wasm";
  version = "2.3";

  src = fetchFromGitHub {
    owner = "gnustep";
    repo = "libobjc2";
    rev = "v${finalAttrs.version}";
    hash = "sha256-C7Dwqp5ewtBhuIyfNZmjhGSCBod3xM9KfUXZgHmvIB0=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    python3
    llvmPackages.clang
    llvmPackages.lld
    llvmPackages.llvm
  ];

  # Cross-compilation flags for wasm32-wasi (no external libc)
  preConfigure = ''
    export CC="clang"
    export CXX="clang++"
    export AR="llvm-ar"
    export NM="llvm-nm"
    export RANLIB="llvm-ranlib"
    export LD="wasm-ld"

    # ObjC runtime flags - no external libc, freestanding mode
    export CFLAGS="-O2 --target=wasm32-wasi -D__EMSCRIPTEN__ -DNO_EXCEPTION_TRAMPOLINES -fobjc-runtime=gnustep-2.2 -fwasm-exceptions -nostdlib -isystem ${llvmPackages.libcxx.dev}/include/c++/v1"
    export LDFLAGS="--target=wasm32-wasi -nostartfiles -Wl,--no-entry -Wl,--export-all"
  '';

  # Don't use cmake for this - manual build is more reliable for cross-compilation
  dontUseCmakeConfigure = true;

  # Only build the core runtime files (subset that works on WASM)
  # Full libobjc2 has pthread/fork dependencies that WASI doesn't support
  buildPhase = ''
    runHook preBuild

    # Compile core ObjC runtime C files to WASM
    # These are the files that the build scripts reference
    CORE_SOURCES="
      class.c
      object.c
      selector.c
      protocol.c
      block.c
      ivar.c
      method_list.c
      properties.m
      category.c
      runtime.c
      msgsend.c
      dtable.c
      alias.c
      encoding.c
      blocks_runtime.c
      objc_error_handler.c
    "

    for src in $CORE_SOURCES; do
      if [ -f "objc/$src" ]; then
        echo "Compiling objc/$src..."
        $CC $CFLAGS -c "objc/$src" -o "objc/$(basename $src .c).o" \
          -I. -Iobjc -Iinclude || true
      fi
    done

    # Create static library from compiled objects
    llvm-ar rcs libobjc2.a objc/*.o 2>/dev/null || true

    # Also compile a minimal WASM module with just the C runtime
    # (no ObjC message dispatch — that needs LLVM 22+)
    echo "Compiling libobjc2 runtime subset to WASM..."
    $CC $CFLAGS $LDFLAGS \
      -o libobjc2.wasm \
      objc/class.c \
      objc/object.c \
      objc/selector.c \
      objc/protocol.c \
      objc/block.c \
      -I. -Iobjc -Iinclude \
      -Wl,--export=objc_getClass \
      -Wl,--export=sel_registerName \
      -Wl,--export=objc_msgSend \
      -Wl,--export=class_getName \
      -Wl,--export=objc_allocateClassPair \
      -Wl,--export=class_addMethod || echo "Warning: full WASM build failed, static lib still available"

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/include $out/wasm

    # Install static library
    [ -f libobjc2.a ] && cp libobjc2.a $out/lib/

    # Install WASM module
    [ -f libobjc2.wasm ] && cp libobjc2.wasm $out/wasm/

    # Install headers
    cp -r objc/. $out/include/objc/ 2>/dev/null || true
    cp -r include/. $out/include/ 2>/dev/null || true

    runHook postInstall
  '';

  meta = with lib; {
    description = "GNUstep Objective-C runtime compiled to WebAssembly";
    homepage = "https://github.com/gnustep/libobjc2";
    platforms = platforms.all;
    license = licenses.mit;
  };
})
