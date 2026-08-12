{ config, lib, pkgs, ... }:

let
  cfg = config.services.garazyk-syrena;
  inherit (lib) mkOption types mkIf mkEnableOption;
in
{
  options.services.garazyk-syrena = {
    enable = mkEnableOption "Garazyk Syrena (AppView) server";

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/garazyk-syrena";
      description = "Data directory for AppView database and state.";
    };

    httpPort = mkOption {
      type = types.port;
      default = 3200;
      description = "HTTP API port for app.bsky.* XRPC endpoints.";
    };

    relayURLs = mkOption {
      type = types.listOf types.str;
      default = [ "wss://bsky.network" ];
      description = "Relay firehose URLs.";
    };

    plcURL = mkOption {
      type = types.str;
      default = "https://plc.directory";
      description = "PLC directory URL for identity resolution.";
    };

    adminUIPort = mkOption {
      type = types.port;
      default = 2596;
      description = "Admin UI port (loopback only).";
    };

    adminPasswordFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Path to admin password file (loaded via LoadCredential).";
    };

    backfillEnabled = mkOption {
      type = types.bool;
      default = true;
      description = "Enable the backfill orchestrator.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.garazyk-syrena = {
      description = "Garazyk Syrena AppView Server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        ExecStart = "${pkgs.garazyk.syrena}/bin/syrena serve"
          + " --port ${toString cfg.httpPort}"
          + " --data-dir ${cfg.dataDir}"
          + lib.optionalString (cfg.relayURLs != [])
              (lib.concatMapStrings (u: " --relay ${u}") cfg.relayURLs)
          + " --plc-url ${cfg.plcURL}"
          + lib.optionalString (!cfg.backfillEnabled) " --no-backfill"
          + " --admin-ui-port ${toString cfg.adminUIPort}"
          + lib.optionalString (cfg.adminPasswordFile != null)
              " --admin-password-file \${CREDENTIALS_DIRECTORY}/syrena-admin-password";
        Restart = "always";
        RestartSec = 5;
        StateDirectory = "garazyk-syrena";
        StateDirectoryMode = "0700";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        LoadCredential = lib.mkIf (cfg.adminPasswordFile != null)
          "syrena-admin-password:${cfg.adminPasswordFile}";
      };
    };
  };
}
