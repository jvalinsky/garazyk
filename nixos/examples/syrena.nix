# Dummy example: a Garazyk Syrena AppView server consuming a relay firehose.
# All values are placeholders — replace them for a real deployment.
#
# From a NixOS flake, wire it up like:
#
#   specialArgs = { syrenaPackage = self.packages.x86_64-linux.syrena; };
#   modules = [ ./syrena.nix ];
{ config, lib, pkgs, syrenaPackage, ... }:

{
  imports = [
    ../modules/syrena.nix
  ];

  services.syrena = {
    enable = true;
    package = syrenaPackage;
    httpPort = 3200;
    dataDir = "/var/lib/syrena";
    relayURLs = [ "wss://bsky.network" ];
    plcURL = "https://plc.directory";
    # Supply this from sops-nix, agenix, or another runtime secret manager.
    adminPasswordFile = "/run/secrets/syrena_admin_password";

    # --- Backfill ---
    # Disable the backfill orchestrator for read-only follower mode:
    # backfillEnabled = false;
  };
}
