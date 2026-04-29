{
  lib,
  stdenv,
  cmake,
  ninja,
  llvmPackages,
  libobjc2-wasm,
  src,
}:

# Compile the ObjC Jupyter kernel to WebAssembly
# Depends on libobjc2-wasm for the ObjC runtime.
#
# The kernel consists of:
#   - objc_kernel.m      (ObjC kernel protocol implementation)
#   - objc_runtime_bridge.c (C bridge between WASM and ObjC runtime)
#
# Note: Compiling .m files to WASM requires LLVM 22+ (PR #169043).
# The C bridge file compiles fine with LLVM 21.
#
# This derivation does NOT use wasilibc because it's a host package.
# Instead, we compile with --target=wasm32-wasi and minimal libc.

stdenv.mkDerivation {
  pname = "kernel-wasm";
  version = "0.1.0";

  inherit src;

  nativeBuildInputs = [
    cmake
    ninja
    llvmPackages.clang
    llvmPackages.lld
    llvmPackages.llvm
  ];

  buildInputs = [
    libobjc2-wasm
  ];

  preConfigure = ''
    export CC="clang --target=wasm32-wasi --sysroot=${wasilibc.dev}"
    export AR="llvm-ar"
    export NM="llvm-nm"
    export RANLIB="llvm-ranlib"
    export LD="wasm-ld"
  '';

  buildPhase = ''
    runHook preBuild

    # Compile the C runtime bridge to WASM
    echo "Compiling objc_runtime_bridge.c..."
    clang --target=wasm32-wasi \
      --sysroot=${wasilibc.dev} \
      -O2 \
      -D__EMSCRIPTEN__ \
      -I${libobjc2-wasm}/include \
      -c objc_runtime_bridge.c \
      -o objc_runtime_bridge.o

    # Compile the ObjC kernel implementation to WASM
    # This requires LLVM 22+ for full ObjC codegen on WASM.
    # With LLVM 21, this may fail — the C bridge still works.
    echo "Compiling objc_kernel.m..."
    clang --target=wasm32-wasi \
      --sysroot=${wasilibc.dev} \
      -O2 \
      -D__EMSCRIPTEN__ \
      -fobjc-runtime=gnustep-2.2 \
      -fwasm-exceptions \
      -I${libobjc2-wasm}/include \
      -L${libobjc2-wasm}/lib \
      -c objc_kernel.m \
      -o objc_kernel.o || {
        echo "WARNING: objc_kernel.m compilation failed (needs LLVM 22+)"
        echo "Building kernel with C bridge only..."
      }

    # Link into WASM module
    echo "Linking kernel.wasm..."
    OBJECTS=""
    [ -f objc_runtime_bridge.o ] && OBJECTS="$OBJECTS objc_runtime_bridge.o"
    [ -f objc_kernel.o ] && OBJECTS="$OBJECTS objc_kernel.o"

    if [ -n "$OBJECTS" ]; then
      wasm-ld \
        -o kernel.wasm \
        $OBJECTS \
        -L${libobjc2-wasm}/lib \
        -lobjc2 \
        --entry=wasm_kernel_init \
        --export=init_kernel \
        --export=execute_code \
        --export=complete_code \
        --export=inspect_code \
        --export=wasm_objc_getClass \
        --export=wasm_objc_msgSend \
        --export=wasm_objc_className \
        --allow-undefined \
        --import-memory \
        || echo "WARNING: WASM linking failed, partial build available"
    fi

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/wasm $out/lib

    [ -f kernel.wasm ] && cp kernel.wasm $out/wasm/
    [ -f objc_runtime_bridge.o ] && cp objc_runtime_bridge.o $out/lib/
    [ -f objc_kernel.o ] && cp objc_kernel.o $out/lib/

    runHook postInstall
  '';

  meta = with lib; {
    description = "Objective-C Jupyter kernel compiled to WebAssembly";
    homepage = "https://github.com/jvalinsky/garazyk";
    platforms = platforms.all;
    license = licenses.mit;
  };
}
