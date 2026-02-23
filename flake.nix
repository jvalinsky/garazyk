{
  description = "Objective-C development environment - GNUstep on Linux, native Apple SDK on darwin";

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
        ];

        devTools = with pkgs; [
          clang-tools
          lldb
          bear
          valgrind
        ];

        darwinFrameworks = pkgs.lib.optionals isDarwin (with pkgs; [
          xcbuild
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
          echo "  Using system Foundation framework"
        '';

      in {
        devShells.default = pkgs.mkShell {
          buildInputs = gnustepPackages ++ darwinFrameworks;
          nativeBuildInputs = buildTools ++ devTools;

          shellHook = ''
            echo "Objective-C development environment (${system})"
            echo "  clang --version: $(clang --version | head -1)"
            ${if isLinux then linuxShellHook else darwinShellHook}
          '';
        };
      }
    );
}
