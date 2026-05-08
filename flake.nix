{
  description = "Garazyk PDS with fuzzing support - GNUstep on Linux, native Apple SDK on darwin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        
        isLinux = pkgs.stdenv.isLinux;
        isDarwin = pkgs.stdenv.isDarwin;

        gnustepPackages = pkgs.lib.optionals isLinux (with pkgs; [
          gnustep-libobjc
          gnustep-make
          gnustep-base
        ]);

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
          llvmPackages_17.clang
          llvmPackages_17.llvm
        ]);

        linuxShellHook = ''
          export GNUSTEP_MAKEFILES="${pkgs.gnustep-make}/Library/Makefiles"
          export GNUSTEP_SYSTEM_ROOT="${pkgs.gnustep-base}"
          export LIBRARY_PATH="${pkgs.gnustep-base}/lib:$LIBRARY_PATH"
          export CPATH="${pkgs.gnustep-base}/include:$CPATH"
          export PKG_CONFIG_PATH="${pkgs.gnustep-base}/lib/pkgconfig:$PKG_CONFIG_PATH"
          export LD_LIBRARY_PATH="${pkgs.gnustep-base}/lib:$LD_LIBRARY_PATH"
          echo "GNUstep Foundation development environment loaded"
          echo "  GNUSTEP_MAKEFILES=$GNUSTEP_MAKEFILES"
        '';

        darwinShellHook = ''
          echo "Native Apple SDK development environment loaded"
          echo "  Note: macOS clang lacks libFuzzer - use Linux for full fuzzing"
        '';

        fuzzerShellHook = pkgs.lib.optionalString isLinux ''
          export FUZZER_CFLAGS="-g -O1 -fno-omit-frame-pointer -fsanitize=fuzzer,address,undefined"
          export FUZZER_LDFLAGS="-fsanitize=fuzzer,address,undefined"
          echo "Fuzzing environment: -fsanitize=fuzzer available on Linux"
        '';

      in {
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
    );
}