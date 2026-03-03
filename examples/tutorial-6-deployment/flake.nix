{
  description = "ATProto PDS Production Deployment Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          name = "atprotopds-deployment";

          buildInputs = with pkgs; [
            # Container runtime
            docker
            docker-compose

            # Web server
            nginx

            # Database tools
            sqlite

            # TLS certificates
            certbot

            # Monitoring and utilities
            curl
            jq
            htop
            lsof

            # Backup tools
            rsync
            gnutar
            gzip

            # Security
            fail2ban
            ufw

            # Shell utilities
            bash
            coreutils
            findutils
            gnugrep
            gnused
          ];

          shellHook = ''
            echo "ATProto PDS Production Deployment Environment"
            echo "=============================================="
            echo ""
            echo "Available tools:"
            echo "  - docker, docker-compose: Container runtime"
            echo "  - nginx: Reverse proxy"
            echo "  - sqlite3: Database management"
            echo "  - certbot: TLS certificate management"
            echo ""
            echo "Quick start:"
            echo "  1. Edit docker/config.json with your domain"
            echo "  2. Run: ./scripts/deploy.sh"
            echo ""
            echo "Documentation: ../../docs/10-tutorials/tutorial-6-deployment.md"
            echo ""
          '';

          # Environment variables
          PDS_DEPLOYMENT_DIR = builtins.toString ./.;
          DOCKER_BUILDKIT = "1";
          COMPOSE_DOCKER_CLI_BUILD = "1";
        };

        # Optional: NixOS module for system-wide deployment
        nixosModules.atprotopds = { config, lib, pkgs, ... }:
          with lib;
          let
            cfg = config.services.atprotopds;
          in
          {
            options.services.atprotopds = {
              enable = mkEnableOption "ATProto PDS";

              domain = mkOption {
                type = types.str;
                example = "pds.example.com";
                description = "Domain name for the PDS instance";
              };

              dataDir = mkOption {
                type = types.path;
                default = "/var/lib/atprotopds";
                description = "Data directory for PDS";
              };

              port = mkOption {
                type = types.port;
                default = 2583;
                description = "Internal port for PDS";
              };

              inviteCodeRequired = mkOption {
                type = types.bool;
                default = true;
                description = "Require invite codes for registration";
              };
            };

            config = mkIf cfg.enable {
              # Docker service
              virtualisation.docker.enable = true;

              # nginx reverse proxy
              services.nginx = {
                enable = true;
                recommendedProxySettings = true;
                recommendedTlsSettings = true;
                recommendedOptimisation = true;
                recommendedGzipSettings = true;

                virtualHosts.${cfg.domain} = {
                  enableACME = true;
                  forceSSL = true;

                  locations."/" = {
                    proxyPass = "http://127.0.0.1:${toString cfg.port}";
                    proxyWebsockets = true;
                    extraConfig = ''
                      proxy_set_header X-Real-IP $remote_addr;
                      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                      proxy_set_header X-Forwarded-Proto $scheme;
                      proxy_buffering off;
                    '';
                  };
                };
              };

              # Firewall
              networking.firewall.allowedTCPPorts = [ 80 443 ];

              # Automated backups
              systemd.services.atprotopds-backup = {
                description = "ATProto PDS Backup";
                serviceConfig = {
                  Type = "oneshot";
                  ExecStart = "${pkgs.bash}/bin/bash ${./scripts/backup.sh}";
                  User = "root";
                };
              };

              systemd.timers.atprotopds-backup = {
                description = "ATProto PDS Backup Timer";
                wantedBy = [ "timers.target" ];
                timerConfig = {
                  OnCalendar = "daily";
                  Persistent = true;
                };
              };
            };
          };
      }
    );
}
