# NixOS service module for the Garazyk Syrena AppView server.
{ config, lib, ... }:

let
  cfg = config.services.syrena;
in {
  options.services.syrena = {
    enable = lib.mkEnableOption "Garazyk syrena AppView server";
    package = lib.mkOption { type = lib.types.package; description = "syrena package"; };
    httpPort = lib.mkOption { type = lib.types.port; default = 3200; description = "HTTP API port for app.bsky.* XRPC endpoints."; };
    dataDir = lib.mkOption { type = lib.types.path; default = "/var/lib/syrena"; description = "Data directory for AppView database and state."; };
    relayURLs = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ "wss://bsky.network" ]; description = "Relay firehose URLs."; };
    plcURL = lib.mkOption { type = lib.types.str; default = "https://plc.directory"; description = "PLC directory URL for identity resolution."; };
    backfillEnabled = lib.mkOption { type = lib.types.bool; default = true; description = "Enable the backfill orchestrator."; };
    adminPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/syrena_admin_password";
      description = ''
        Runtime password file for the embedded admin UI listener.
        Loaded as a systemd credential; never copied into the Nix store.
        When unset, the admin listener starts without authentication.
      '';
    };
    adminPort = lib.mkOption {
      type = lib.types.port;
      default = 2596;
      description = "TCP port for the embedded admin UI listener (loopback only).";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.syrena = { isSystemUser = true; group = "syrena"; };
    users.groups.syrena = { };
    systemd.services.syrena = {
      description = "Garazyk Syrena AppView server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        User = "syrena";
        Group = "syrena";
        StateDirectory = "syrena";
        StateDirectoryMode = "0750";
        Restart = "on-failure";
        RestartSec = "5s";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
      } // lib.optionalAttrs (cfg.adminPasswordFile != null) {
        LoadCredential = [ "syrena-admin-password:${cfg.adminPasswordFile}" ];
        Environment = [
          "SYRENA_ADMIN_PASSWORD_FILE=%d/syrena-admin-password"
        ];
      };
      script = lib.concatStringsSep " " (
        [ "${cfg.package}/bin/syrena" "serve" ]
        ++ [ "--port" (toString cfg.httpPort) ]
        ++ [ "--data-dir" cfg.dataDir ]
        ++ lib.concatMap (r: [ "--relay" r ]) cfg.relayURLs
        ++ [ "--plc-url" cfg.plcURL ]
        ++ [ "--admin-ui-host" "127.0.0.1" ]
        ++ [ "--admin-ui-port" (toString cfg.adminPort) ]
        ++ lib.optional (!cfg.backfillEnabled) "--no-backfill"
        ++ lib.optional (cfg.adminPasswordFile != null)
             "--admin-password-file %d/syrena-admin-password"
      );
    };
  };
}
