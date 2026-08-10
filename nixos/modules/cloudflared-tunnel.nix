# NixOS service module that publishes a local service through a Cloudflare
# tunnel, so no host port needs to be exposed.
#
#   services.cloudflaredTunnel = {
#     enable = true;
#     tunnelId = "...";
#     hostname = "relay.example.com";
#     credentialsFile = "/var/lib/cloudflared/<tunnelId>.json";
#     origin = "http://127.0.0.1:2470";
#   };
{ config, lib, pkgs, ... }:

let
  cfg = config.services.cloudflaredTunnel;
in
{
  options.services.cloudflaredTunnel = {
    enable = lib.mkEnableOption "cloudflared tunnel publishing a local service";

    tunnelId = lib.mkOption {
      type = lib.types.str;
      description = "ID of the Cloudflare tunnel (from the Zero Trust dashboard).";
    };

    hostname = lib.mkOption {
      type = lib.types.str;
      description = "Public hostname published through the tunnel.";
    };

    credentialsFile = lib.mkOption {
      type = lib.types.path;
      description = "JSON credentials file for the tunnel.";
    };

    origin = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:2470";
      description = "Local origin the tunnel forwards to.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.cloudflared = {
      enable = true;
      tunnels = {
        ${cfg.tunnelId} = {
          credentialsFile = cfg.credentialsFile;
          default = "http_status:404";
          ingress = {
            ${cfg.hostname} = cfg.origin;
          };
        };
      };
    };
  };
}
