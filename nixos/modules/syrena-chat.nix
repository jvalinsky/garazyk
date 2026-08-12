# NixOS service module for the Garazyk Syrena Chat service.
{ config, lib, ... }:

let
  cfg = config.services.syrena-chat;
in {
  options.services.syrena-chat = {
    enable = lib.mkEnableOption "Garazyk syrena-chat service";
    package = lib.mkOption { type = lib.types.package; description = "syrena-chat package"; };
    port = lib.mkOption { type = lib.types.port; default = 2585; description = "HTTP API port for chat.bsky.* XRPC endpoints."; };
    dataDir = lib.mkOption { type = lib.types.path; default = "/var/lib/syrena-chat"; description = "Data directory for chat database."; };
    adminPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/chat_admin_password";
      description = ''
        Runtime password file for the embedded admin UI listener (127.0.0.1:2598).
        Loaded as a systemd credential; never copied into the Nix store.
        When unset, the admin listener starts without authentication.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.syrena-chat = { isSystemUser = true; group = "syrena-chat"; };
    users.groups.syrena-chat = { };
    systemd.services.syrena-chat = {
      description = "Garazyk Syrena Chat service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        User = "syrena-chat";
        Group = "syrena-chat";
        StateDirectory = "syrena-chat";
        StateDirectoryMode = "0750";
        Restart = "on-failure";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
      } // lib.optionalAttrs (cfg.adminPasswordFile != null) {
        LoadCredential = [ "chat-admin-password:${cfg.adminPasswordFile}" ];
        Environment = [ "CHAT_ADMIN_PASSWORD_FILE=%d/chat-admin-password" ];
      };
      script = lib.concatStringsSep " " (
        [ "${cfg.package}/bin/syrena-chat" "serve" ]
        ++ [ "--port" (toString cfg.port) ]
        ++ [ "--data-dir" cfg.dataDir ]
        ++ lib.optional (cfg.adminPasswordFile != null)
             "--admin-password-file %d/chat-admin-password"
      );
    };
  };
}
