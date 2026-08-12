# Dummy example: a Garazyk Mikrus link index deployed alongside a relay.
# All values are placeholders — replace them for a real deployment.
#
# From a NixOS flake, wire it up like:
#
#   specialArgs = { mikrusPackage = self.packages.x86_64-linux.mikrus; };
#   modules = [ ./mikrus.nix ];
{ config, lib, pkgs, mikrusPackage, ... }:

{
  imports = [
    ../modules/mikrus.nix
  ];

  services.mikrus = {
    enable = true;
    package = mikrusPackage;
    port = 3210;
    dataDir = "/var/lib/mikrus";
    relayURLs = [ "wss://127.0.0.1:2470" ];
    # Supply this from sops-nix, agenix, or another runtime secret manager.
    adminPasswordFile = "/run/secrets/mikrus_admin_password";
  };
}
