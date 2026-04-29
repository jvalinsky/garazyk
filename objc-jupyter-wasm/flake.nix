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
        };

        # Relaxed nixpkgs config for WASM cross-compilation derivations only.
        # Some LLVM/wasm packages are marked broken or unsupported on the host
        # platform because they only build for wasm32-wasi targets. Scoping
        # these overrides to the specific callPackage sites avoids masking real
        # build failures in other packages.
        pkgsWasm = import nixpkgs {
          inherit system;
          config = {
            allowBroken = true;
            allowUnsupportedSystem = true;
          };
        };

        # ── LLVM / Emscripten ──────────────────────────────────────────
        # nixpkgs-unstable ships LLVM 21 as the latest.
        # LLVM PR #169043 (ObjC WASM codegen) landed in LLVM 22.
        # We use llvmPackages_21 (closest available) and note the gap.
        # The wasi-sdk path works without LLVM 22 since libobjc2 is C.
        llvmPackages = pkgs.llvmPackages_21;

        # Emscripten from nixpkgs (wired to LLVM 21 by default)
        # Note: Emscripten 5.0.6 expects LLVM 22, but nixpkgs uses LLVM 21.
        # This may cause version check warnings. Use pkgs.emscripten directly.
        emscriptenPkg = pkgs.emscripten;

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
        kernelSrc = ./kernel;
        runtimeSrc = ./runtime;

      in {
        # ── Packages (Nix derivations) ─────────────────────────────────

        packages = {
          # Jupyter kernel compiled to WASM (linked with libobjc2 runtime)
          kernel-wasm = pkgs.callPackage ./nix/kernel-wasm.nix {
            inherit llvmPackages;
            wasiSysroot = self.packages.${system}.wasi-libc-sysroot;
            libobjc2WasmFull = self.packages.${system}.libobjc2-wasm-full;
            src = kernelSrc;
          };

          # Full GNUstep libobjc2 runtime compiled to WASM (C core + stubs).
          libobjc2-wasm-full = pkgsWasm.callPackage ./nix/libobjc2-wasm-full.nix {
            inherit llvmPackages;
            wasiSysroot = self.packages.${system}.wasi-libc-sysroot;
          };

          # WASI libc sysroot built from source with LLVM 21
          wasi-libc-sysroot = pkgs.callPackage ./nix/wasi-libc-sysroot.nix {
            inherit llvmPackages;
          };

          # Static browser smoke site with Nix-built WASM assets.
          jupyterlite-smoke-site = pkgs.runCommand "objc-jupyter-wasm-jupyterlite-smoke-site" {
            nativeBuildInputs = [
              pkgs.nodejs
            ];
          } ''
            node ${self}/scripts/build-smoke-site.mjs \
              --out $out \
              --kernel-wasm ${self.packages.${system}.kernel-wasm}/wasm/kernel.wasm
          '';

          # Meta package: build all WASM artifacts
          default = pkgs.symlinkJoin {
            name = "objc-jupyter-wasm-all";
            paths = with self.packages.${system}; [
              kernel-wasm
              libobjc2-wasm-full
              jupyterlite-smoke-site
            ];
          };
        };

        checks = {
          libobjc2-wasm-full-smoke = pkgs.runCommand "objc-jupyter-wasm-libobjc2-wasm-full-smoke" {
            nativeBuildInputs = [
              pkgs.wabt
            ];
          } ''
            wasm-validate ${self.packages.${system}.libobjc2-wasm-full}/wasm/libobjc2.wasm
            mkdir -p $out
            touch $out/passed
          '';

          kernel-smoke = pkgs.runCommand "objc-jupyter-wasm-kernel-smoke" {
            nativeBuildInputs = [
              pkgs.nodejs
              pkgs.wabt
            ];
          } ''
            wasm-validate ${self.packages.${system}.kernel-wasm}/wasm/kernel.wasm
            node ${self}/tests/kernel-smoke.mjs ${self.packages.${system}.kernel-wasm}/wasm/kernel.wasm
            mkdir -p $out
            touch $out/passed
          '';

          js-syntax = pkgs.runCommand "objc-jupyter-wasm-js-syntax" {
            nativeBuildInputs = [
              pkgs.nodejs
            ];
          } ''
            node --check ${self}/js/wasm-loader.js
            node --check ${self}/js/objc-worker.js
            node --check ${self}/jupyterlite/kernel.js
            node --check ${self}/scripts/copy-static-assets.mjs
            node --check ${self}/scripts/build-smoke-site.mjs
            node --check ${self}/tests/browser-smoke.mjs
            node --check ${self}/tests/browser-smoke-page.mjs
            node --check ${self}/tests/kernel-smoke.mjs
            mkdir -p $out
            touch $out/passed
          '';

          smoke-site-assets = pkgs.runCommand "objc-jupyter-wasm-smoke-site-assets" {
            nativeBuildInputs = [
              pkgs.nodejs
            ];
          } ''
            cp -R ${self.packages.${system}.jupyterlite-smoke-site} site
            test -f site/index.html
            test -f site/browser-smoke-page.mjs
            test -f site/js/objc-worker.js
            test -f site/js/wasm-loader.js
            test -f site/kernel/kernel.wasm
            test -f site/files/demo/hello.ipynb
            test -f site/kernelspecs/objective-c/kernel.json
            mkdir -p $out
            touch $out/passed
          '';
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

            # ObjC-specific flags
            OBJC_CFLAGS = "-fobjc-runtime=gnustep-2.2 -fwasm-exceptions";

            shellHook = ''
              echo "=== WASI cross-compilation environment ==="
              echo "  Target:      wasm32-wasi"
              echo "  clang:       $(clang --version | head -1)"
              echo ""
              echo "Usage:"
              echo "  # C to WASM (freestanding, no libc):"
              echo "  clang --target=wasm32-wasi -o out.wasm source.c"
              echo "  # ObjC to WASM (needs LLVM 22+):"
              echo "  clang --target=wasm32-wasi $OBJC_CFLAGS -o out.wasm source.m"
              echo "  # Run:"
              echo "  wasmtime out.wasm"
              echo ""
              echo "Note: For WASI libc support, use emscripten shell:"
              echo "  nix develop .#wasm-emscripten"
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
