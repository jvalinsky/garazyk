# Tutorial 6: Production Deployment Example

This example demonstrates a complete production deployment setup for ATProto PDS using Docker, including configuration, nginx reverse proxy, and automated backups.

## Directory Structure

```
tutorial-6-deployment/
├── README.md                    # This file
├── flake.nix                    # Nix flake for nix-darwin environments
├── docker/
│   ├── docker-compose.yml       # Production Docker Compose configuration
│   ├── config.json              # Production PDS configuration
│   └── .env.example             # Environment variables template
├── nginx/
│   ├── pds.conf                 # nginx site configuration
│   └── proxy_params_pds         # Proxy headers configuration
├── scripts/
│   ├── deploy.sh                # Deployment automation script
│   ├── backup.sh                # Backup script wrapper
│   ├── health-check.sh          # Health monitoring script
│   └── update.sh                # Update automation script
└── systemd/
    ├── pds-backup.service       # Systemd backup service
    └── pds-backup.timer         # Systemd backup timer
```

## Prerequisites

- Linux server (Ubuntu 22.04 LTS recommended)
- Docker and Docker Compose installed
- Domain name with DNS configured
- Root or sudo access

For nix-darwin environments, use the provided `flake.nix`.

## Quick Start

### 1. Clone and Configure

```bash
# Copy example to deployment location
cp -r examples/tutorial-6-deployment /opt/atprotopds-deploy
cd /opt/atprotopds-deploy

# Copy environment template
cp docker/.env.example docker/.env

# Edit configuration
nano docker/.env
nano docker/config.json
```

### 2. Deploy

```bash
# Run deployment script
./scripts/deploy.sh

# Follow prompts for:
# - Domain name
# - Email for Let's Encrypt
# - Initial admin email
```

### 3. Verify

```bash
# Check status
docker compose -f docker/docker-compose.yml ps

# Test endpoint
curl https://your-domain.com/xrpc/com.atproto.server.describeServer
```

## Nix-Darwin Setup

For nix-darwin environments:

```bash
# Enter development shell with all dependencies
nix develop

# Or use nix-shell
nix-shell -p docker docker-compose nginx sqlite

# Then proceed with deployment
./scripts/deploy.sh
```

## Manual Deployment Steps

See [Tutorial 6 Documentation](../../docs/10-tutorials/tutorial-6-deployment.md) for detailed manual deployment instructions.

## Backup and Restore

### Create Backup

```bash
./scripts/backup.sh
```

### Restore from Backup

```bash
# Stop PDS
docker compose -f docker/docker-compose.yml down

# Restore
tar -xzf /var/backups/atprotopds/pds-backup-TIMESTAMP.tar.gz
sudo rsync -av TIMESTAMP/ /var/lib/docker/volumes/pds_pds_data/_data/

# Restart
docker compose -f docker/docker-compose.yml up -d
```

## Monitoring

### Health Check

```bash
./scripts/health-check.sh
```

### View Logs

```bash
# PDS logs
docker compose -f docker/docker-compose.yml logs -f pds

# nginx logs
sudo tail -f /var/log/nginx/pds_access.log
```

## Updates

```bash
./scripts/update.sh
```

## Security Notes

**CRITICAL:** Never deploy with these settings:
- `invite_code_required: false`
- `plc.url: "mock"`
- Any `debug.*` flags set to `true`

Always use:
- TLS certificates (Let's Encrypt)
- Firewall rules (ufw)
- Rate limiting (nginx + PDS)
- Automated backups
- Security updates (unattended-upgrades)

## Troubleshooting

See [Troubleshooting Guide](../../docs/11-reference/troubleshooting.md) for common issues and solutions.

## License

Same as parent project.
