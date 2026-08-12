# Dummy example: a Garazyk Germ E2EE mailbox service deployed alongside
# a local Chat service. All values are placeholders — replace them for a
# real deployment.
#
# From a NixOS flake, wire it up like:
#
#   specialArgs = { germPackage = self.packages.x86_64-linux.germ; };
#   modules = [ ./germ.nix ];
{ config, lib, pkgs, germPackage, ... }:

{
  imports = [
    ../modules/germ.nix
  ];

  services.germ = {
    enable = true;
    package = germPackage;
    port = 8082;
    dataDir = "/var/lib/germ";
    # Supply this from sops-nix, agenix, or another runtime secret manager.
    adminPasswordFile = "/run/secrets/germ_admin_password";
  };
}
