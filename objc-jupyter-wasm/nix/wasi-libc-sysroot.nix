{
  lib,
  stdenv,
  fetchFromGitHub,
  llvmPackages,
}:

# Build wasi-libc from source using the LLVM 21 toolchain from nixpkgs.
# This ensures the resulting libc.a is compatible with our LLVM 21 linker.
#
# The output is a sysroot directory that can be used with --sysroot=
# when compiling C/C++ code for wasm32-wasi.
#
# wasi-libc uses a simple Makefile-based build system (not CMake).

let
  version = "27";
in
stdenv.mkDerivation {
  pname = "wasi-libc-sysroot";
  version = version;

  src = fetchFromGitHub {
    owner = "WebAssembly";
    repo = "wasi-libc";
    rev = "wasi-sdk-${version}";
    hash = "sha256-RIjph1XdYc1aGywKks5JApcLajbNFEuWm+Wy/GMHddg=";
    fetchSubmodules = true;
  };

  nativeBuildInputs = [
    llvmPackages.clang
    llvmPackages.lld
    llvmPackages.llvm
  ];

  # wasi-libc uses Make, not CMake
  dontConfigure = true;

  # Remove -Werror from the Makefile to avoid build failures
  postPatch = ''
    substituteInPlace Makefile --replace "-Werror" ""
    patchShebangs scripts/
  '';

  preBuild = ''
    export CC="${llvmPackages.clang-unwrapped}/bin/clang --target=wasm32-wasi"
    export CXX="${llvmPackages.clang-unwrapped}/bin/clang++ --target=wasm32-wasi"
    export AR="${llvmPackages.llvm}/bin/llvm-ar"
    export NM="${llvmPackages.llvm}/bin/llvm-nm"
    export RANLIB="${llvmPackages.llvm}/bin/llvm-ranlib"

    export SYSROOT_LIB=$out/lib/wasm32-wasi
    export SYSROOT_INC=$out/include
    export SYSROOT_SHARE=$out/share
    mkdir -p "$SYSROOT_LIB" "$SYSROOT_INC" "$SYSROOT_SHARE"

    makeFlagsArray+=(
      "SYSROOT_LIB:=$SYSROOT_LIB"
      "SYSROOT_INC:=$SYSROOT_INC"
      "SYSROOT_SHARE:=$SYSROOT_SHARE"
      "TARGET_TRIPLE:=wasm32-wasi"
    )
  '';

  enableParallelBuilding = true;

  # wasi-libc builds directly into the install paths
  dontInstall = true;

  meta = with lib; {
    description = "WASI libc sysroot built from source with LLVM 21";
    homepage = "https://github.com/WebAssembly/wasi-libc";
    platforms = platforms.all;
    license = with licenses; [ asl20 llvm-exception mit ];
  };
}
