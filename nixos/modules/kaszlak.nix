# NixOS service module for the Garazyk kaszlak PDS (embedded admin UI).
#
#   services.kaszlak = {
#     enable = true;
#     package = kaszlakPackage;  # via specialArgs
#     port = 2583;
#     adminPort = 2590;
#     adminPasswordFile = "/run/secrets/pds_admin_password";
#   };
#
# The admin listener defaults to loopback. Publish it through nginx or
# cloudflared-tunnel.nix rather than opening 2590 on the host firewall.
{ config, lib, ... }:

let
  cfg = config.services.kaszlak;
in {
  options.services.kaszlak = {
    enable = lib.mkEnableOption "Garazyk kaszlak PDS";

    package = lib.mkOption {
      type = lib.types.package;
      description = "The kaszlak package to run.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 2583;
      description = "TCP port for the PDS protocol listener.";
    };

    adminPort = lib.mkOption {
      type = lib.types.port;
      default = 2590;
      description = "TCP port for the embedded admin UI listener.";
    };

    adminHost = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Bind address for the embedded admin UI (loopback by default).";
    };

    adminPublicURL = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "https://ui.example.invalid/admin";
      description = "Public admin sign-in URL linked from the protocol GET / landing page.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/kaszlak";
      description = "Directory for PDS state (accounts DB, actor stores, blobs).";
    };

    adminPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/pds_admin_password";
      description = "Runtime password file loaded as a systemd credential; never copied into the Nix store.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.kaszlak = { isSystemUser = true; group = "kaszlak"; };
    users.groups.kaszlak = { };

    systemd.services.kaszlak = {
      description = "Garazyk kaszlak PDS";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        User = "kaszlak";
        Group = "kaszlak";
        StateDirectory = "kaszlak";
        StateDirectoryMode = "0750";
        Restart = "on-failure";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ cfg.dataDir ];
      } // lib.optionalAttrs (cfg.adminPasswordFile != null) {
        LoadCredential = [ "pds-admin-password:${cfg.adminPasswordFile}" ];
      };
      environment = {
        PDS_ADMIN_UI_HOST = cfg.adminHost;
        PDS_ADMIN_UI_PORT = toString cfg.adminPort;
      } // lib.optionalAttrs (cfg.adminPasswordFile != null) {
        PDS_ADMIN_PASSWORD_FILE = "%d/pds-admin-password";
      } // lib.optionalAttrs (cfg.adminPublicURL != null) {
        PDS_ADMIN_UI_PUBLIC_URL = cfg.adminPublicURL;
      };
      script = lib.concatStringsSep " " [
        "${cfg.package}/bin/kaszlak" "serve"
        "--port" (toString cfg.port)
        "--data-dir" cfg.dataDir
      ];
    };
  };
}
