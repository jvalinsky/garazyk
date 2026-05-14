{
  description = "ATProto scenario runner — Deno environment for end-to-end testing";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

      in {
        devShells.default = pkgs.mkShell {
          name = "garazyk-scenarios";

          nativeBuildInputs = [
            pkgs.deno
            pkgs.docker-client
            pkgs.docker-compose
            pkgs.jq
          ];

          shellHook = ''
            echo "=== Garazyk ATProto Scenario Runner ==="
            echo "  deno:    $(deno --version | head -1)"
            echo "  docker:  $(docker --version 2>/dev/null | head -1 || echo 'not found')"
            echo ""
            echo "Usage:"
            echo "  ../run_scenarios.ts --list              # List scenarios"
            echo "  ../run_scenarios.ts --setup-only        # Start local network"
            echo "  ../run_scenarios.ts 01 04 10            # Run specific scenarios"
            echo "  ../run_scenarios.ts --setup --teardown  # Full run"
          '';
        };
      }
    );
}
