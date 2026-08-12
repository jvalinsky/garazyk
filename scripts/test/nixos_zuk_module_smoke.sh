#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${ROOT}"

echo "nixos zuk module: eval nixosModules.zuk"
nix eval .#nixosModules.zuk --apply 'x: builtins.typeOf x' | grep -q 'lambda'

echo "nixos zuk module: check admin credential wiring"
nix eval --impure --expr "
  let
    flake = builtins.getFlake \"${ROOT}\";
    pkgs = import flake.inputs.nixpkgs { system = \"x86_64-linux\"; };
    eval = import (flake.inputs.nixpkgs + \"/nixos/lib/eval-config.nix\") {
      system = \"x86_64-linux\";
      modules = [
        (import ${ROOT}/nixos/modules/zuk.nix)
        {
          services.zuk = {
            enable = true;
            package = pkgs.hello;
            adminPasswordFile = \"/run/secrets/relay-admin-password\";
            adminHost = \"127.0.0.1\";
            adminPort = 2594;
          };
        }
      ];
    };
  in
    eval.config.systemd.services.zuk.serviceConfig.Environment or []
" | grep -q 'RELAY_ADMIN_PASSWORD_FILE'

echo "nixos zuk module smoke: OK"
