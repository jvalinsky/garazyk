# Dummy example: a Garazyk Syrena Chat service deployed alongside a local PDS.
# All values are placeholders — replace them for a real deployment.
#
# From a NixOS flake, wire it up like:
#
#   specialArgs = { syrenaChatPackage = self.packages.x86_64-linux.syrena-chat; };
#   modules = [ ./syrena-chat.nix ];
{ config, lib, pkgs, syrenaChatPackage, ... }:

{
  imports = [
    ../modules/syrena-chat.nix
  ];

  services.syrena-chat = {
    enable = true;
    package = syrenaChatPackage;
    port = 2585;
    dataDir = "/var/lib/syrena-chat";
    # Supply this from sops-nix, agenix, or another runtime secret manager.
    adminPasswordFile = "/run/secrets/chat_admin_password";
  };
}
