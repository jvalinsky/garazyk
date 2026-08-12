# NixOS service module for the Garazyk Jelcz video processing service.
{ config, lib, ... }:

let
  cfg = config.services.jelcz;
in {
  options.services.jelcz = {
    enable = lib.mkEnableOption "Garazyk jelcz video processing service";
    package = lib.mkOption { type = lib.types.package; description = "jelcz package"; };
    port = lib.mkOption { type = lib.types.port; default = 2586; };
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/jelcz";
      description = "Data directory for job database.";
    };
    blobDir = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Blob storage directory. Defaults to <dataDir>/blobs when unset.
      '';
    };
    pdsURL = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:2583";
      description = "PDS URL for blob upload.";
    };
    s3Bucket = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "S3 bucket for blob storage (disables local disk storage).";
    };
    s3Region = lib.mkOption {
      type = lib.types.str;
      default = "us-east-1";
      description = "S3 region when using S3 storage backend.";
    };
    s3Endpoint = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "S3-compatible endpoint URL (e.g. MinIO).";
    };
    hlsDir = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "HLS output directory.";
    };
    hlsBaseURL = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Base URL for HLS playlist URLs.";
    };
    hls1080p = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Include 1080p HLS variant.";
    };
    adminPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/jelcz_admin_password";
      description = ''
        Runtime password file for the embedded admin UI listener (127.0.0.1:2597).
        Loaded as a systemd credential; never copied into the Nix store.
        When unset, the embedded admin listener starts without authentication
        and the host logs a warning.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.jelcz = { isSystemUser = true; group = "jelcz"; };
    users.groups.jelcz = { };
    systemd.services.jelcz = {
      description = "Garazyk Jelcz video processing service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        User = "jelcz";
        Group = "jelcz";
        StateDirectory = "jelcz";
        StateDirectoryMode = "0750";
        Restart = "on-failure";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
      } // lib.optionalAttrs (cfg.adminPasswordFile != null) {
        LoadCredential = [ "jelcz-admin-password:${cfg.adminPasswordFile}" ];
        Environment = [ "JELCZ_ADMIN_PASSWORD_FILE=%d/jelcz-admin-password" ];
      };
      script = lib.concatStringsSep " " (
        [ "${cfg.package}/bin/jelcz" "serve" ]
        ++ [ "--port" (toString cfg.port) ]
        ++ [ "--data-dir" cfg.dataDir ]
        ++ [ "--pds-url" cfg.pdsURL ]
        ++ lib.optional (cfg.blobDir != null) "--blob-dir ${cfg.blobDir}"
        ++ lib.optional (cfg.s3Bucket != null) "--s3-bucket ${cfg.s3Bucket}"
        ++ lib.optional (cfg.s3Endpoint != null) "--s3-endpoint ${cfg.s3Endpoint}"
        ++ lib.optional (cfg.s3Bucket != null) "--s3-region ${cfg.s3Region}"
        ++ lib.optional (cfg.hlsDir != null) "--hls-dir ${cfg.hlsDir}"
        ++ lib.optional (cfg.hlsBaseURL != null) "--hls-base-url ${cfg.hlsBaseURL}"
        ++ lib.optional cfg.hls1080p "--hls-1080p"
        ++ lib.optional (cfg.adminPasswordFile != null)
             "--admin-password-file %d/jelcz-admin-password"
      );
    };
  };
}
