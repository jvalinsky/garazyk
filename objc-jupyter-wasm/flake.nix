{
  description = "Objective-C Jupyter Kernel via WebAssembly";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowBroken = true;
            allowUnsupportedSystem = true; # wasilibc only builds on wasm platforms
          };
        };

        # ── LLVM / Emscripten ──────────────────────────────────────────
        # nixpkgs-unstable ships LLVM 21 as the latest.
        # LLVM PR #169043 (ObjC WASM codegen) landed in LLVM 22.
        # We use llvmPackages_21 (closest available) and note the gap.
        # The wasi-sdk path works without LLVM 22 since libobjc2 is C.
        llvmPackages = pkgs.llvmPackages_21;

        # Emscripten with our LLVM packages (overrides the default set)
        emscriptenPkg = pkgs.emscripten.override {
          inherit llvmPackages;
        };

        # ── WASI cross-compilation ─────────────────────────────────────
        # pkgsCross.wasi32 provides wasm32-unknown-wasi stdenv
        wasiPkgs = pkgs.pkgsCross.wasi32;

        # ── WASM tooling ────────────────────────────────────────────────
        wasmTools = with pkgs; [
          wabt           # wasm2wat, wat2wasm, wasm-validate, wasm-objdump
          binaryen       # wasm-opt, wasm-metadce, wasm-dis
          wasmtime       # WASI runtime for testing
        ];

        # ── Build tools ────────────────────────────────────────────────
        buildTools = with pkgs; [
          cmake
          ninja
          python3
          nodejs
          pkg-config
        ];

        # ── Source paths ───────────────────────────────────────────────
        kernelSrc = "${self}/kernel";
        jsSrc = "${self}/js";
        jupyterliteSrc = "${self}/jupyterlite";

      in {
        # ── Packages (Nix derivations) ─────────────────────────────────

        packages = {
          # libobjc2 compiled to WASM via wasi32 cross-stdenv
          libobjc2-wasm = pkgs.callPackage ./nix/libobjc2-wasm.nix {
            inherit llvmPackages;
          };

          # Extended WASI sysroot with ObjC headers overlaid
          wasi-sysroot = pkgs.callPackage ./nix/wasi-sysroot.nix {
            inherit llvmPackages;
            wasilibc = pkgs.wasilibc;
            libobjc2-wasm = self.packages.${system}.libobjc2-wasm;
          };

          # Jupyter kernel compiled to WASM
          kernel-wasm = pkgs.callPackage ./nix/kernel-wasm.nix {
            inherit llvmPackages;
            libobjc2-wasm = self.packages.${system}.libobjc2-wasm;
            src = kernelSrc;
          };

          # Meta package: build all WASM artifacts
          default = pkgs.symlinkJoin {
            name = "objc-jupyter-wasm-all";
            paths = with self.packages.${system}; [
              libobjc2-wasm
              kernel-wasm
              wasi-sysroot
            ];
          };
        };

        # ── Dev Shells ─────────────────────────────────────────────────

        devShells = {

          # Default: all WASM tools
          default = pkgs.mkShell {
            name = "objc-jupyter-wasm";

            nativeBuildInputs = buildTools ++ wasmTools ++ [
              emscriptenPkg
              llvmPackages.lld
              pkgs.zig  # optional: zig cc -target wasm32-wasi
            ];

            shellHook = ''
              echo "=== objc-jupyter-wasm development environment ==="
              echo "  emcc:    $(emcc --version 2>/dev/null | head -1 || echo 'not found')"
              echo "  clang:   $(clang --version 2>/dev/null | head -1 || echo 'not found')"
              echo "  wasm-opt: $(wasm-opt --version 2>/dev/null || echo 'not found')"
              echo "  wasmtime: $(wasmtime --version 2>/dev/null || echo 'not found')"
              echo ""
              echo "Available shells:"
              echo "  nix develop .#wasm-wasi       — Pure WASI cross-compilation"
              echo "  nix develop .#wasm-emscripten — Emscripten browser builds"
              echo ""
              echo "Build commands:"
              echo "  bash scripts/build-all.sh"
              echo "  nix build .#libobjc2-wasm"
              echo "  nix build .#kernel-wasm"
            '';
          };

          # Pure WASI cross-compilation shell
          wasm-wasi = pkgs.mkShell {
            name = "objc-jupyter-wasm-wasi";

            nativeBuildInputs = buildTools ++ wasmTools ++ [
              llvmPackages.clang
              llvmPackages.lld
              llvmPackages.llvm
            ];

            # WASI sysroot from cross-compiled wasilibc
            # Note: wasilibc is built for wasm32-wasi, not the host.
            # Use pkgsCross.wasi32.buildPackages for cross-compilation tools.
            # For now, we set up the environment for manual WASI builds.
            WASI_SYSROOT = "${wasiPkgs.buildPackages.wasilibc.dev or "${pkgs.wasilibc.dev}"}";

            # ObjC-specific flags
            OBJC_CFLAGS = "-fobjc-runtime=gnustep-2.2 -fwasm-exceptions";

            shellHook = ''
              echo "=== WASI cross-compilation environment ==="
              echo "  Target:      wasm32-wasi"
              echo "  clang:       $(clang --version | head -1)"
              echo ""
              echo "Usage:"
              echo "  # C to WASM (basic):"
              echo "  clang --target=wasm32-wasi -o out.wasm source.c"
              echo "  # C to WASM (with wasi-libc sysroot):"
              echo "  clang --target=wasm32-wasi --sysroot=/path/to/wasi-sysroot -o out.wasm source.c"
              echo "  # ObjC to WASM (needs LLVM 22+):"
              echo "  clang --target=wasm32-wasi $OBJC_CFLAGS -o out.wasm source.m"
              echo "  # Run:"
              echo "  wasmtime out.wasm"
              echo ""
              echo "Note: For full WASI libc support, use emscripten or wasi-sdk."
            '';
          };

          # Emscripten-focused shell (for browser builds)
          wasm-emscripten = pkgs.mkShell {
            name = "objc-jupyter-wasm-emscripten";

            nativeBuildInputs = buildTools ++ wasmTools ++ [
              emscriptenPkg
            ];

            EMSCRIPTEN = "${emscriptenPkg}/share/emscripten";
            EMSDK = "${emscriptenPkg}/share/emscripten";

            shellHook = ''
              echo "=== Emscripten WASM environment ==="
              echo "  emcc: $(emcc --version | head -1)"
              echo "  EMSDK: $EMSDK"
              echo ""
              echo "Usage:"
              echo "  emcc -O2 -s WASM=1 -s ALLOW_MEMORY_GROWTH=1 -o out.js source.c"
              echo "  emcmake cmake -B build-wasm -S ."
            '';
          };
        };
      }
    );
}
