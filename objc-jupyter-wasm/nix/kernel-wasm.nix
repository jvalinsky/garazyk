{
  lib,
  stdenv,
  llvmPackages,
  wasiSysroot,
  libobjc2WasmFull,
  src,
}:

# Compile the browser-side Jupyter kernel to WebAssembly, linked with the
# full GNUstep libobjc2 runtime and wasi-libc.
#
# The kernel provides a stable C ABI (JSON request/reply) that JavaScript
# calls into. The runtime provides real Objective-C method dispatch, class
# registration, and selector management. The interpreter layer (next phase)
# will sit between the kernel ABI and the runtime, parsing ObjC source and
# evaluating it against the runtime.

stdenv.mkDerivation {
  pname = "kernel-wasm";
  version = "0.2.0";

  inherit src;

  nativeBuildInputs = [
    llvmPackages.clang
    llvmPackages.lld
    llvmPackages.llvm
  ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    # Compile the kernel bridge with wasi-libc headers
    ${llvmPackages.clang-unwrapped}/bin/clang --target=wasm32-wasi \
      -O2 \
      --sysroot=${wasiSysroot} \
      -I${libobjc2WasmFull}/include/objc \
      -I. \
      -Wall \
      -Wextra \
      -Wno-unused-parameter \
      -Wno-unused-variable \
      -Wno-unused-function \
      -c objc_runtime_bridge.c \
      -o objc_runtime_bridge.o

    # Compile the interpreter
    ${llvmPackages.clang-unwrapped}/bin/clang --target=wasm32-wasi \
      -O2 \
      --sysroot=${wasiSysroot} \
      -I${libobjc2WasmFull}/include/objc \
      -I. \
      -Wall \
      -Wextra \
      -Wno-unused-parameter \
      -Wno-unused-variable \
      -Wno-unused-function \
      -c objc_interpreter.c \
      -o objc_interpreter.o

    # Link: kernel + libobjc2 runtime + wasi-libc
    ${llvmPackages.lld}/bin/wasm-ld \
      --no-entry \
      --export-memory \
      --export=objc_kernel_init \
      --export=objc_kernel_info_json \
      --export=objc_kernel_execute_json \
      --export=objc_kernel_complete_json \
      --export=objc_kernel_inspect_json \
      --export=objc_kernel_free \
      --export=objc_kernel_request_buffer \
      --export=objc_kernel_request_buffer_size \
      --export=__objc_wasm_init \
      --export=objc_getClass \
      --export=objc_getMetaClass \
      --export=sel_registerName \
      --export=sel_getName \
      --export=class_getName \
      --export=class_getInstanceSize \
      --export=objc_allocateClassPair \
      --export=objc_registerClassPair \
      --export=class_addMethod \
      --export=class_addIvar \
      --export=objc_msgSend \
      --export=objc_msg_lookup_sender \
      --export=class_createInstance \
      --export=objc_retain \
      --export=objc_release \
      --export=objc_autorelease \
      --export=objc_storeStrong \
      --export=objc_setAssociatedObject \
      --export=objc_getAssociatedObject \
      --export=objc_enumerationMutation \
      --export=objc_getProperty \
      --export=objc_setProperty \
      --export=_NSConcreteGlobalBlock \
      --export=_NSConcreteStackBlock \
      -L${wasiSysroot}/lib/wasm32-wasi \
      -lc \
      -o kernel.wasm \
      objc_runtime_bridge.o \
      objc_interpreter.o \
      ${libobjc2WasmFull}/obj/*.o

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/wasm $out/lib
    cp kernel.wasm $out/wasm/
    cp objc_runtime_bridge.o $out/lib/

    runHook postInstall
  '';

  meta = with lib; {
    description = "Objective-C Jupyter kernel compiled to WebAssembly with libobjc2 runtime";
    homepage = "https://github.com/jvalinsky/garazyk";
    platforms = platforms.all;
    license = licenses.mit;
  };
}
