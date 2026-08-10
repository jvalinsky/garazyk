# NixOS service module for the Garazyk zuk AT Protocol relay.
#
#   services.zuk = {
#     enable = true;
#     package = self.packages.x86_64-linux.zuk;   # via specialArgs
#     port = 2470;
#   };
#
# The relay binds all interfaces; keep the host firewall closed on the port
# and publish it through a Cloudflare tunnel (see cloudflared-tunnel.nix).
{ config, lib, pkgs, ... }:

let
  cfg = config.services.zuk;
in
{
  options.services.zuk = {
    enable = lib.mkEnableOption "Garazyk zuk AT Protocol relay";

    package = lib.mkOption {
      type = lib.types.package;
      description = "The zuk package to run (the flake's packages.<system>.zuk).";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 2470;
      description = "TCP port the relay listens on.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/zuk";
      description = "Directory for relay state (CAR store, SQLite database).";
    };

    upstreams = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Upstream firehose URLs (wss://...) to relay from. Empty means this
        relay is itself a source and runs in passthrough mode (--no-upstream).
      '';
    };

    validationMode = lib.mkOption {
      type = lib.types.enum [ "strict" "log-only" "lenient" ];
      default = "log-only";
      description = "Event continuity policy (strict, log-only, or lenient).";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open the relay port on the host firewall. The relay binds all
        interfaces and is normally only reached through the Cloudflare tunnel
        (which connects to the loopback), so keep this off.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.zuk = {
      isSystemUser = true;
      group = "zuk";
    };
    users.groups.zuk = { };

    systemd.services.zuk = {
      description = "Garazyk zuk AT Protocol relay";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        User = "zuk";
        Group = "zuk";
        Type = "simple";
        Restart = "on-failure";
        RestartSec = "5s";
        StateDirectory = "zuk";
        StateDirectoryMode = "0750";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
      };
      script = lib.concatStringsSep " " (
        [ "${cfg.package}/bin/zuk" "serve" ]
        ++ (if cfg.upstreams == [ ] then
          [ "--no-upstream" ]
        else
          lib.concatMap (u: [ "--upstream" u ]) cfg.upstreams)
        ++ [ "--port" (toString cfg.port) ]
        ++ [ "--data-dir" cfg.dataDir ]
        ++ [ "--validation-mode" cfg.validationMode ]
      );
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}
