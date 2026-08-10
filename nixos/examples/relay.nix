# Dummy, non-server-specific example: a Garazyk zuk relay published through a
# Cloudflare tunnel. All values are placeholders — replace them for a real
# deployment.
#
# From a NixOS flake, wire it up like:
#
#   specialArgs = { zukPackage = self.packages.x86_64-linux.zuk; };
#   modules = [ ./relay.nix ];
{ config, lib, pkgs, zukPackage, ... }:

{
  imports = [
    ../modules/zuk.nix
    ../modules/cloudflared-tunnel.nix
  ];

  services.zuk = {
    enable = true;
    package = zukPackage;
    port = 2470;
    dataDir = "/var/lib/zuk";
    validationMode = "log-only";
    # Empty: this relay is itself a source (passthrough mode, --no-upstream).
    upstreams = [ ];
  };

  services.cloudflaredTunnel = {
    enable = true;
    tunnelId = "00000000-0000-0000-0000-000000000000";
    hostname = "relay.example.invalid";
    credentialsFile = "/var/lib/cloudflared/00000000-0000-0000-0000-000000000000.json";
    origin = "http://127.0.0.1:2470";
  };
}
