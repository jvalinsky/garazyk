{
  description = "Garazyk PDS with fuzzing support - GNUstep on Linux, native Apple SDK on darwin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = import nixpkgs { inherit system; };
          lib = pkgs.lib;

          isLinux = pkgs.stdenv.isLinux;
          isDarwin = pkgs.stdenv.isDarwin;

          # Linux-only GNUstep toolchain: pinned libs-base master, patched
          # nixpkgs build, standalone libdispatch. See nix/toolchain.nix.
          toolchain = if isLinux then import ./nix/toolchain.nix { inherit pkgs; } else null;
          gnustepPrefix = if isLinux then toolchain.gnustepPrefix else null;
          runtimeLibs = if isLinux then toolchain.runtimeLibs else [ ];

          buildTools = with pkgs; [
            clang
            pkg-config
            gnumake
            cmake
            sqlite
            shellcheck
            shfmt
            jq
          ];

          devTools = with pkgs; [
            clang-tools
            lldb
            bear
          ];

          formatter = pkgs.nixpkgs-fmt;

          darwinFrameworks = pkgs.lib.optionals isDarwin (with pkgs; [
            xcbuild
          ]);

          linuxFuzzingDeps = pkgs.lib.optionals isLinux (with pkgs; [
            llvmPackages_18.clang
            llvmPackages_18.llvm
          ]);

          gnustepPackages = pkgs.lib.optionals isLinux ([ gnustepPrefix ] ++ runtimeLibs);

          # zuk (AT Protocol relay) from this repository's source. Filters the
          # flake source down to what the CMake build needs; scripts/scenarios
          # alone is 2+ GB of scenario data.
          zukSource = lib.cleanSourceWith {
            src = self;
            filter = path: type:
              let
                rel = lib.removePrefix (toString self + "/") (toString path);
              in
              rel != "scripts/scenarios"
              && !(builtins.elem (builtins.head (builtins.split "/" rel)) [
                "build"
                "node_modules"
                "coverage"
              ]);
          };

          zuk = pkgs.clangStdenv.mkDerivation {
            pname = "zuk";
            version = "1.0.0";

            src = zukSource;

            nativeBuildInputs = with pkgs; [ cmake ninja pkg-config ];
            buildInputs = [ gnustepPrefix ] ++ runtimeLibs;

            preConfigure = ''
              export GNUSTEP_PREFIX="${gnustepPrefix}"
            '';

            cmakeFlags = [
              "-DCMAKE_BUILD_TYPE=Release"
              "-DBUILD_TESTS=OFF"
              "-DBUILD_FUZZERS=OFF"
              "-DBUILD_SECP256K1=ON"
            ];

            buildPhase = ''
              cmake --build build --target zuk --parallel 4
            '';

            installPhase = ''
              install -Dm755 build/bin/zuk $out/bin/zuk
            '';

            meta = with lib; {
              description = "Garazyk AT Protocol relay";
              license = [ licenses.unlicense licenses.cc0 ];
              platforms = platforms.linux;
            };
          };

          linuxShellHook =
            if isLinux then ''
              export GNUSTEP_PREFIX="${gnustepPrefix}"
              export GNUSTEP_MAKEFILES="${gnustepPrefix}/Library/Makefiles"
              export LIBRARY_PATH="${gnustepPrefix}/lib:$LIBRARY_PATH"
              export CPATH="${gnustepPrefix}/include:$CPATH"
              export PKG_CONFIG_PATH="${gnustepPrefix}/lib/pkgconfig:$PKG_CONFIG_PATH"
              export LD_LIBRARY_PATH="${gnustepPrefix}/lib:$LD_LIBRARY_PATH"
              echo "GNUstep Foundation development environment loaded"
              echo "  GNUSTEP_MAKEFILES=$GNUSTEP_MAKEFILES"
            '' else "";

          darwinShellHook = ''
            echo "Native Apple SDK development environment loaded"
            echo "  Note: macOS clang lacks libFuzzer - use Linux for full fuzzing"
          '';

          fuzzerShellHook = pkgs.lib.optionalString isLinux ''
            export FUZZER_CFLAGS="-g -O1 -fno-omit-frame-pointer -fsanitize=fuzzer,address,undefined"
            export FUZZER_LDFLAGS="-fsanitize=fuzzer,address,undefined"
            echo "Fuzzing environment: -fsanitize=fuzzer available on Linux"
          '';

        in
        {
          packages = lib.optionalAttrs isLinux {
            inherit zuk;
          };

          inherit formatter;

          devShells.default = pkgs.mkShell {
            buildInputs = gnustepPackages ++ darwinFrameworks;
            nativeBuildInputs = buildTools ++ devTools;

            # Add script check target
            shellHook = ''
              echo "Objective-C development environment (${system})"
              echo "  clang --version: $(clang --version | head -1)"
              echo "  Script check enabled: run 'nix flake check'"
              ${if isLinux then linuxShellHook else darwinShellHook}
            '';
          };

          checks = {
            shell-check = pkgs.runCommand "shell-check" { buildInputs = [ pkgs.shellcheck ]; } ''
              FILES=$(find . -name "*.sh" -not -path "./vendor/*" -not -path "./build/*" -print0)
              if [ -n "$FILES" ]; then
                echo "$FILES" | xargs -0 shellcheck
              fi
              touch $out
            '';
          };

          devShells.fuzzing = pkgs.mkShell {
            buildInputs = gnustepPackages ++ darwinFrameworks ++ linuxFuzzingDeps;
            nativeBuildInputs = buildTools ++ devTools;

            shellHook = ''
              echo "Fuzzer development environment (${system})"
              echo "  clang --version: $(clang --version | head -1)"
              ${if isLinux then linuxShellHook else darwinShellHook}
              ${fuzzerShellHook}
            '';
          };
        }
      )
    // {
      # Reusable NixOS service modules. See nixos/examples/relay.nix for a
      # working (dummy) composition.
      nixosModules = {
        zuk = import ./nixos/modules/zuk.nix;
        cloudflaredTunnel = import ./nixos/modules/cloudflared-tunnel.nix;
      };
    };
}
