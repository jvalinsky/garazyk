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
        isLinux = pkgs.stdenv.isLinux;

      in {
        devShells.default = pkgs.mkShell {
          name = "garazyk-scenarios";

          nativeBuildInputs = with pkgs; [
            deno
            docker-client
            docker-compose
            jq
          ] ++ pkgs.lib.optionals isLinux [
            pkgs.playwright-driver
          ];

          shellHook = ''
            echo "=== Garazyk ATProto Scenario Runner ==="
            echo "  deno:    $(deno --version | head -1)"
            echo "  docker:  $(docker --version 2>/dev/null | head -1 || echo 'not found')"
            echo "  system:  ${system}"
            echo ""

            # Linux: point Playwright at nixpkgs browser builds
            ${pkgs.lib.optionalString isLinux ''
            export PLAYWRIGHT_BROWSERS_PATH="${pkgs.playwright-driver.browsers}"
            ''}

            # macOS: download Playwright browsers on first enter
            ${pkgs.lib.optionalString (!isLinux) ''
            if ! deno eval 'await import("npm:playwright@1.52.0").then(m => m.chromium.launch()).then(b => b.close())' 2>/dev/null; then
              echo "[setup] Installing Playwright browsers for Chromium..."
              deno install --allow-scripts npm:playwright@1.52.0 2>/dev/null || true
              npx --yes playwright install chromium 2>/dev/null || echo "[warn] Could not install Playwright browsers — run manually: npx playwright install chromium"
            fi
            ''}

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
