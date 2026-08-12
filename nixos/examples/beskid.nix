# Dummy example: a Garazyk Beskid edge record and identity cache deployed
# alongside a PDS. All values are placeholders — replace them for a real
# deployment.
#
# From a NixOS flake, wire it up like:
#
#   specialArgs = { beskidPackage = self.packages.x86_64-linux.beskid; };
#   modules = [ ./beskid.nix ];
{ config, lib, pkgs, beskidPackage, ... }:

{
  imports = [
    ../modules/beskid.nix
  ];

  services.beskid = {
    enable = true;
    package = beskidPackage;
    port = 8085;
    dataDir = "/var/lib/beskid";
    # Supply this from sops-nix, agenix, or another runtime secret manager.
    adminPasswordFile = "/run/secrets/beskid_admin_password";
  };
}
