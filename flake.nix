{
  description = "GNUstep Foundation development environment for Linux and nix-darwin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        gnustepPackages = with pkgs; [
          gnustep-libobjc
          gnustep-make
          gnustep-base
        ];

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
        ];

        runtimeDeps = with pkgs; [
          libdispatch
        ];

      in {
        devShells.default = pkgs.mkShell {
          buildInputs = gnustepPackages ++ runtimeDeps;
          nativeBuildInputs = buildTools ++ devTools;

          shellHook = ''
            export GNUSTEP_MAKEFILES="${pkgs.gnustep-make}/Library/Makefiles"
            export GNUSTEP_SYSTEM_ROOT="${pkgs.gnustep-base}"

            export LIBRARY_PATH="${pkgs.gnustep-base}/lib:${pkgs.libdispatch}/lib:$LIBRARY_PATH"
            export CPATH="${pkgs.gnustep-base}/include:${pkgs.libdispatch}/include:$CPATH"
            export PKG_CONFIG_PATH="${pkgs.gnustep-base}/lib/pkgconfig:$PKG_CONFIG_PATH"

            export LD_LIBRARY_PATH="${pkgs.gnustep-base}/lib:${pkgs.libdispatch}/lib:$LD_LIBRARY_PATH"

            echo "GNUstep Foundation development environment loaded"
            echo "  GNUSTEP_MAKEFILES=$GNUSTEP_MAKEFILES"
            echo "  clang --version: $(clang --version | head -1)"
          '';
        };
      }
    );
}
