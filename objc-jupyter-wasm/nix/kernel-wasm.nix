{
  lib,
  stdenv,
  llvmPackages,
  src,
}:

# Compile the browser-side Jupyter kernel smoke ABI to WebAssembly.
#
# This is the first vertical slice: a freestanding C module with stable exported
# functions that JavaScript can load, pass JSON into, and parse JSON replies
# from. Objective-C compilation and the full runtime are later layers behind the
# same ABI.
#
# Note: libobjc2-wasm is NOT linked here because the kernel is fully
# freestanding. It will be added as a buildInput when the kernel calls into the
# runtime (next milestone).

stdenv.mkDerivation {
  pname = "kernel-wasm";
  version = "0.1.0";

  inherit src;

  nativeBuildInputs = [
    llvmPackages.clang
    llvmPackages.lld
    llvmPackages.llvm
  ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    ${llvmPackages.clang-unwrapped}/bin/clang --target=wasm32-unknown-unknown \
      -O2 \
      -nostdlib \
      -ffreestanding \
      -Wall \
      -Wextra \
      -Werror \
      -c objc_runtime_bridge.c \
      -o objc_runtime_bridge.o

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
      -o kernel.wasm \
      objc_runtime_bridge.o

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
    description = "Objective-C Jupyter kernel smoke ABI compiled to WebAssembly";
    homepage = "https://github.com/jvalinsky/garazyk";
    platforms = platforms.all;
    license = licenses.mit;
  };
}
