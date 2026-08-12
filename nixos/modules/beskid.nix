# NixOS service module for the Garazyk Beskid edge record and identity cache.
{ config, lib, ... }:

let
  cfg = config.services.beskid;
in {
  options.services.beskid = {
    enable = lib.mkEnableOption "Garazyk beskid edge cache";
    package = lib.mkOption { type = lib.types.package; description = "beskid package"; };
    port = lib.mkOption { type = lib.types.port; default = 8085; };
    dataDir = lib.mkOption { type = lib.types.path; default = "/var/lib/beskid"; };
    adminPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/beskid_admin_password";
      description = "Runtime password file loaded as a systemd credential; it is never copied into the Nix store.";
    };
    adminPort = lib.mkOption {
      type = lib.types.port;
      default = 2595;
      description = "TCP port for the separate Beskid admin listener (loopback only).";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.beskid = { isSystemUser = true; group = "beskid"; };
    users.groups.beskid = { };
    systemd.services.beskid = {
      description = "Garazyk Beskid edge cache";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        User = "beskid";
        Group = "beskid";
        StateDirectory = "beskid";
        StateDirectoryMode = "0750";
        Restart = "on-failure";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
      } // lib.optionalAttrs (cfg.adminPasswordFile != null) {
        LoadCredential = [ "beskid-admin-password:${cfg.adminPasswordFile}" ];
        Environment = [
          "BESKID_ADMIN_PASSWORD_FILE=%d/beskid-admin-password"
          "GARAZYK_BESKID_ADMIN_UI_HOST=127.0.0.1"
          "GARAZYK_BESKID_ADMIN_UI_PORT=${toString cfg.adminPort}"
        ];
      };
      script = lib.concatStringsSep " " [
        "${cfg.package}/bin/beskid" "serve"
        "--port" (toString cfg.port)
        "--data-dir" cfg.dataDir
        "--admin-ui-host" "127.0.0.1"
        "--admin-ui-port" (toString cfg.adminPort)
      ];
    };
  };
}
