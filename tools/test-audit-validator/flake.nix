{
  description = "Development shell for test-audit-validator (Go + libclang)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        # Prefer an older LLVM toolchain on unstable when available; latest can be
        # less compatible with Objective-C/Xcode SDK parsing in libclang flows.
        llvm18 = builtins.tryEval (if pkgs ? llvmPackages_18 then pkgs.llvmPackages_18 else null);
        llvm19 = builtins.tryEval (if pkgs ? llvmPackages_19 then pkgs.llvmPackages_19 else null);
        llvm = if llvm18.success && llvm18.value != null then llvm18.value else
          if llvm19.success && llvm19.value != null then llvm19.value else
          if pkgs ? llvmPackages then pkgs.llvmPackages else pkgs.llvmPackages_latest;
        libclang = llvm.libclang;
        libclangLib = pkgs.lib.getLib libclang;
        libclangDev = pkgs.lib.getDev libclang;
        goPkg = if pkgs ? go_1_25 then pkgs.go_1_25 else pkgs.go;
        isDarwin = pkgs.stdenv.isDarwin;
        xcodeToolchain = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain";
        clangExecutable = if isDarwin then "${xcodeToolchain}/usr/bin/clang" else "${llvm.clang}/bin/clang";
        libclangLibDir = if isDarwin then "${xcodeToolchain}/usr/lib" else "${libclangLib}/lib";
        cgoIncludeDir = if isDarwin then "${xcodeToolchain}/usr/include" else "${libclangDev}/include";
      in {
        devShells.default = pkgs.mkShell {
          packages = [
            goPkg
            pkgs.gnumake
            pkgs.pkg-config
            pkgs.bear
          ] ++ pkgs.lib.optionals (!isDarwin) [
            llvm.clang
            libclang
          ];

          CLANG_EXECUTABLE = clangExecutable;
          LIBCLANG_PATH = libclangLibDir;
          CGO_CFLAGS = if isDarwin then "" else "-I${cgoIncludeDir}";
          CGO_LDFLAGS = "-L${libclangLibDir}";
          CPATH = if isDarwin then "" else cgoIncludeDir;
          LIBRARY_PATH = libclangLibDir;
          DYLD_LIBRARY_PATH = if isDarwin then libclangLibDir else "";
          LD_LIBRARY_PATH = if isDarwin then "" else libclangLibDir;

          shellHook = ''
            export GOCACHE="$PWD/.cache/go-build"
            export GOMODCACHE="$PWD/.cache/go-mod"
            export CLANG_MODULE_CACHE_PATH="$PWD/.cache/clang-module-cache"
            export CLANG_RESOURCE_DIR="$($CLANG_EXECUTABLE -print-resource-dir)"
            mkdir -p "$GOCACHE" "$GOMODCACHE" "$CLANG_MODULE_CACHE_PATH"

            echo "test-audit-validator dev shell (${system})"
            echo "  go: $(go version)"
            echo "  libclang path: $LIBCLANG_PATH"
            echo "  clang executable: $CLANG_EXECUTABLE"
            echo "  clang resource dir: $CLANG_RESOURCE_DIR"
            echo "Suggested checks:"
            echo "  go test ./internal/config ./internal/validation"
            echo "  go test ./cmd/test-audit-validator"
          '';
        };
      }
    );
}
