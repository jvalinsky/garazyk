{
  lib,
  stdenv,
  fetchFromGitHub,
  llvmPackages,
}:

# First pinned GNUstep libobjc2 source probe.
#
# This does not replace the local smoke runtime yet. It proves that a pinned
# libobjc2 source checkout can enter the WASM build graph and that its public
# runtime headers compile for the selected target before we start porting source
# files with platform dependencies.

stdenv.mkDerivation {
  pname = "libobjc2-real-subset-wasm";
  version = "2.3-smoke";

  src = fetchFromGitHub {
    owner = "gnustep";
    repo = "libobjc2";
    rev = "v2.3";
    hash = "sha256-C7Dwqp5ewtBhuIyfNZmjhGSCBod3xM9KfUXZgHmvIB0=";
  };

  nativeBuildInputs = [
    llvmPackages.clang
    llvmPackages.lld
    llvmPackages.llvm
  ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    cat > objc/objc-config.h <<'EOF'
    /* Minimal generated config for the WASM source probe. */
EOF

    mkdir -p sys
    cat > sys/types.h <<'EOF'
    #ifndef OBJC_WASM_SYS_TYPES_H
    #define OBJC_WASM_SYS_TYPES_H
    #include <stddef.h>
    #endif
EOF

    cat > libobjc2_real_subset_smoke.c <<'EOF'
    #include "objc/runtime.h"

    __attribute__((used))
    const char *objc_real_subset_source(void) {
      return "gnustep/libobjc2@v2.3";
    }

    __attribute__((used))
    int objc_real_subset_header_smoke(void) {
      Class cls = (Class)0;
      SEL sel = (SEL)0;
      Method method = (Method)0;
      Ivar ivar = (Ivar)0;
      return (cls == 0 && sel == 0 && method == 0 && ivar == 0) ? 0 : 1;
    }
EOF

    ${llvmPackages.clang-unwrapped}/bin/clang --target=wasm32-wasi \
      -O2 \
      -ffreestanding \
      -nostdlib \
      -I. \
      -c libobjc2_real_subset_smoke.c \
      -o libobjc2_real_subset_smoke.o

    ${llvmPackages.lld}/bin/wasm-ld \
      --no-entry \
      --export=objc_real_subset_source \
      --export=objc_real_subset_header_smoke \
      --export-memory \
      -o libobjc2-real-subset.wasm \
      libobjc2_real_subset_smoke.o

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/wasm $out/libobjc2-source
    cp libobjc2-real-subset.wasm $out/wasm/
    cp -R objc $out/libobjc2-source/objc

    runHook postInstall
  '';

  meta = with lib; {
    description = "Pinned GNUstep libobjc2 source/header smoke compiled to WebAssembly";
    homepage = "https://github.com/gnustep/libobjc2";
    platforms = platforms.all;
    license = licenses.mit;
  };
}
