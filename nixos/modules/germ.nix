# NixOS service module for the Garazyk Germ E2EE mailbox service.
{ config, lib, ... }:

let
  cfg = config.services.germ;
in {
  options.services.germ = {
    enable = lib.mkEnableOption "Garazyk germ E2EE mailbox service";
    package = lib.mkOption { type = lib.types.package; description = "germ package"; };
    port = lib.mkOption { type = lib.types.port; default = 8082; description = "HTTP API port for com.germnetwork.* XRPC endpoints."; };
    dataDir = lib.mkOption { type = lib.types.path; default = "/var/lib/germ"; description = "Data directory for mailbox database."; };
    adminPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/germ_admin_password";
      description = ''
        Runtime password file for the embedded admin UI listener (127.0.0.1:2599).
        Loaded as a systemd credential; never copied into the Nix store.
        When unset, the admin listener starts without authentication.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.germ = { isSystemUser = true; group = "germ"; };
    users.groups.germ = { };
    systemd.services.germ = {
      description = "Garazyk Germ E2EE mailbox service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        User = "germ";
        Group = "germ";
        StateDirectory = "germ";
        StateDirectoryMode = "0750";
        Restart = "on-failure";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
      } // lib.optionalAttrs (cfg.adminPasswordFile != null) {
        LoadCredential = [ "germ-admin-password:${cfg.adminPasswordFile}" ];
        Environment = [ "GERM_ADMIN_PASSWORD_FILE=%d/germ-admin-password" ];
      };
      script = lib.concatStringsSep " " (
        [ "${cfg.package}/bin/germ" "serve" ]
        ++ [ "--port" (toString cfg.port) ]
        ++ [ "--data-dir" cfg.dataDir ]
        ++ lib.optional (cfg.adminPasswordFile != null)
             "--admin-password-file %d/germ-admin-password"
      );
    };
  };
}
