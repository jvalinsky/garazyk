{
  description = "ATProto scenario runner — Python environment for end-to-end testing";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        pythonEnv = pkgs.python3.withPackages (ps: with ps; [
          requests
          websockets
          cbor2
          playwright
        ]);

      in {
        devShells.default = pkgs.mkShell {
          name = "garazyk-scenarios";

          nativeBuildInputs = [
            pythonEnv
            pkgs.docker-client
            pkgs.docker-compose
            pkgs.jq
          ];

          shellHook = ''
            echo "=== Garazyk ATProto Scenario Runner ==="
            echo "  python:  $(python3 --version)"
            echo "  docker:  $(docker --version 2>/dev/null | head -1 || echo 'not found')"
            echo ""
            echo "Usage:"
            echo "  python run_scenario.py --list           # List scenarios"
            echo "  python run_scenario.py --setup          # Start local network"
            echo "  python run_scenario.py 01 04 10         # Run specific scenarios"
            echo "  python run_scenario.py --setup --teardown  # Full run"
          '';
        };
      }
    );
}
