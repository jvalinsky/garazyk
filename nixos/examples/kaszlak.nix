# Dummy composition: kaszlak PDS with embedded admin UI published through a
# Cloudflare tunnel. Placeholder values — replace for a real deployment.
#
# From a NixOS flake:
#
#   specialArgs = { kaszlakPackage = self.packages.x86_64-linux.kaszlak; };
#   modules = [ ./kaszlak.nix ];
{ config, lib, pkgs, kaszlakPackage, ... }:

{
  imports = [
    ../modules/kaszlak.nix
    ../modules/cloudflared-tunnel.nix
  ];

  services.kaszlak = {
    enable = true;
    package = kaszlakPackage;
    port = 2583;
    adminPort = 2590;
    adminHost = "127.0.0.1";
    adminPublicURL = "https://ui.example.invalid/admin";
    dataDir = "/var/lib/kaszlak";
    # Supply from sops-nix, agenix, or another runtime secret manager.
    adminPasswordFile = "/run/secrets/pds_admin_password";
  };

  # Publish only the admin UI through the tunnel; keep the protocol port on
  # the private network / a separate origin.
  services.cloudflaredTunnel = {
    enable = true;
    tunnelId = "00000000-0000-0000-0000-000000000000";
    hostname = "ui.example.invalid";
    credentialsFile = "/var/lib/cloudflared/00000000-0000-0000-0000-000000000000.json";
    origin = "http://127.0.0.1:2590";
  };
}
