# NixOS service module for the Garazyk Mikrus link index.
{ config, lib, ... }:

let
  cfg = config.services.mikrus;
in {
  options.services.mikrus = {
    enable = lib.mkEnableOption "Garazyk mikrus link index";
    package = lib.mkOption { type = lib.types.package; description = "mikrus package"; };
    port = lib.mkOption { type = lib.types.port; default = 3210; };
    dataDir = lib.mkOption { type = lib.types.path; default = "/var/lib/mikrus"; };
    relayURLs = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; description = "Relay WebSocket URLs"; };
    adminPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/mikrus_admin_password";
      description = "Runtime password file loaded as a systemd credential.";
    };
    adminPort = lib.mkOption { type = lib.types.port; default = 2593; };
  };

  config = lib.mkIf cfg.enable {
    users.users.mikrus = { isSystemUser = true; group = "mikrus"; };
    users.groups.mikrus = { };
    systemd.services.mikrus = {
      description = "Garazyk Mikrus link index";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        User = "mikrus"; Group = "mikrus";
        StateDirectory = "mikrus"; StateDirectoryMode = "0750";
        Restart = "on-failure";
        NoNewPrivileges = true; PrivateTmp = true;
        ProtectHome = true; ProtectSystem = "strict";
      } // lib.optionalAttrs (cfg.adminPasswordFile != null) {
        LoadCredential = [ "mikrus-admin-password:${cfg.adminPasswordFile}" ];
        Environment = [
          "MIKRUS_ADMIN_PASSWORD_FILE=%d/mikrus-admin-password"
          "GARAZYK_MIKRUS_ADMIN_UI_HOST=127.0.0.1"
          "GARAZYK_MIKRUS_ADMIN_UI_PORT=${toString cfg.adminPort}"
        ];
      };
      script = lib.concatStringsSep " " (
        [ "${cfg.package}/bin/mikrus" "serve" "--port" (toString cfg.port) "--data-dir" cfg.dataDir
          "--admin-ui-host" "127.0.0.1" "--admin-ui-port" (toString cfg.adminPort) ]
        ++ lib.concatMap (u: [ "--relay" u ]) cfg.relayURLs
        ++ lib.optional (cfg.relayURLs == []) "--no-ingest"
      );
    };
  };
}
