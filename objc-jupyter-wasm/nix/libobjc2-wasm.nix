{
  lib,
  stdenv,
  llvmPackages,
  src,
}:

# Build the local libobjc2-compatible smoke runtime to WASM.
# This is intentionally small and freestanding; it provides a stable package
# boundary while the real libobjc2 port is brought up behind the same output
# shape.

stdenv.mkDerivation {
  pname = "libobjc2-wasm";
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

    ${llvmPackages.clang-unwrapped}/bin/clang --target=wasm32-wasi \
      -O2 \
      -ffreestanding \
      -nostdlib \
      -Iinclude \
      -c libobjc2_smoke.c \
      -o libobjc2_smoke.o

    ${llvmPackages.llvm}/bin/llvm-ar rcs libobjc2.a libobjc2_smoke.o

    ${llvmPackages.lld}/bin/wasm-ld \
      -o libobjc2.wasm \
      libobjc2_smoke.o \
      --no-entry \
      --export=objc_getClass \
      --export=sel_registerName \
      --export=sel_getName \
      --export=class_getName \
      --export=objc_allocateClassPair \
      --export=class_addMethod \
      --export=objc_msgSend \
      --export=objc_runtime_smoke_version \
      --export-memory

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/include $out/lib $out/wasm
    cp -r include/. $out/include/
    cp libobjc2.a $out/lib/
    cp libobjc2.wasm $out/wasm/

    runHook postInstall
  '';

  meta = with lib; {
    description = "Minimal libobjc2-compatible smoke runtime compiled to WebAssembly";
    homepage = "https://github.com/jvalinsky/garazyk";
    platforms = platforms.all;
    license = licenses.mit;
  };
}
