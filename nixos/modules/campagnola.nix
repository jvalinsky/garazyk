# NixOS service module for the Garazyk PLC directory.
{ config, lib, ... }:

let
  cfg = config.services.campagnola;
in {
  options.services.campagnola = {
    enable = lib.mkEnableOption "Garazyk campagnola PLC directory";
    package = lib.mkOption { type = lib.types.package; description = "campagnola package"; };
    port = lib.mkOption { type = lib.types.port; default = 2582; };
    adminPort = lib.mkOption { type = lib.types.port; default = 2592; };
    dataDir = lib.mkOption { type = lib.types.path; default = "/var/lib/campagnola"; };
    adminPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/plc_admin_password";
      description = "Runtime password file loaded as a systemd credential; it is never copied into the Nix store.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.campagnola = { isSystemUser = true; group = "campagnola"; };
    users.groups.campagnola = { };
    systemd.services.campagnola = {
      description = "Garazyk PLC directory";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        User = "campagnola";
        Group = "campagnola";
        StateDirectory = "campagnola";
        StateDirectoryMode = "0750";
        Restart = "on-failure";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
      } // lib.optionalAttrs (cfg.adminPasswordFile != null) {
        LoadCredential = [ "plc-admin-password:${cfg.adminPasswordFile}" ];
        Environment = [ "GARAZYK_PLC_ADMIN_PASSWORD_FILE=%d/plc-admin-password" ];
      };
      script = lib.concatStringsSep " " [
        "${cfg.package}/bin/campagnola" "serve"
        "--database" "${cfg.dataDir}/plc.db"
        "--port" (toString cfg.port)
        "--admin-ui-host" "127.0.0.1"
        "--admin-ui-port" (toString cfg.adminPort)
      ];
    };
  };
}
