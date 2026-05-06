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

    # Compile the lexer module
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
      -c objc_interp_lexer.c \
      -o objc_interp_lexer.o

    # Compile the state module
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
      -c objc_interp_state.c \
      -o objc_interp_state.o

    # Compile the class declaration / implementation parser
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
      -c objc_interp_class.c \
      -o objc_interp_class.o

    # Compile the formatting / NSLog module
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
      -c objc_interp_format.c \
      -o objc_interp_format.o

    # Compile the AST module
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
      -c objc_interp_ast.c \
      -o objc_interp_ast.o

    # Compile method dispatch and NSLog evaluation helpers
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
      -c objc_interp_dispatch.c \
      -o objc_interp_dispatch.o

    # Compile the parser module
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
      -c objc_interp_parser.c \
      -o objc_interp_parser.o

    # Compile the primary expression module
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
      -c objc_interp_primary.c \
      -o objc_interp_primary.o

    # Compile the messages module
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
      -c objc_interp_messages.c \
      -o objc_interp_messages.o

    # Link: kernel + libobjc2 runtime + wasi-libc
    # Stack configuration: 1 MB stack with stack-first placement to trap on overflow rather than silently corrupt heap
    ${llvmPackages.lld}/bin/wasm-ld \
      --no-entry \
      --allow-undefined \
      --export-memory \
      --initial-memory=16777216 \
      -z stack-size=1048576 \
      --stack-first \
      --export=objc_kernel_init \
      --export=objc_kernel_max_request_bytes \
      --export=objc_kernel_max_response_bytes \
      --export=objc_kernel_alloc \
      --export=objc_kernel_free \
      --export=objc_kernel_info_json \
      --export=objc_kernel_execute_json \
      --export=objc_kernel_complete_json \
      --export=objc_kernel_inspect_json \
      --export=__objc_wasm_init \
      --export=objc_getClass \
      --export=objc_getMetaClass \
      --export=objc_lookUpClass \
      --export=sel_registerName \
      --export=sel_getName \
      --export=class_getName \
      --export=class_getInstanceSize \
      --export=objc_allocateClassPair \
      --export=objc_registerClassPair \
      --export=class_addMethod \
      --export=class_addIvar \
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
      --export=objc_interp_full_reset \
      --export=class_conformsToProtocol: \
      --export=coll_create_new \
      --export=coll_add \
      --export=coll_make_marker \
      --export=string_pool_alloc \
      --export=coll_add_string_val \
      --export=coll_add_int_val \
      --export=coll_add_double_val \
      --export=coll_add_bool_val \
      --export=coll_add_marker_val \
      --export=objc_kernel_on_fetch_complete \
      --export=objc_kernel_has_pending_tasks \
      -L${wasiSysroot}/lib/wasm32-wasi \
      -lc \
      -o kernel.wasm \
      objc_runtime_bridge.o \
      objc_interpreter.o \
      objc_interp_lexer.o \
      objc_interp_state.o \
      objc_interp_class.o \
      objc_interp_format.o \
      objc_interp_dispatch.o \
      objc_interp_ast.o \
      objc_interp_parser.o \
      objc_interp_primary.o \
      objc_interp_messages.o \
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
