---
title: Deployment
---

# Deployment

## Local services

Start the local Docker topology with:

```sh
./scripts/scenarios/setup_local_network.sh
```

The underlying Compose file is `docker/local-network/docker-compose.yml`.

For a standalone PDS:

```sh
docker compose -f docker/pds/docker-compose.yml up -d
```

## Production requirements

Garazyk services listen over plain HTTP. Put public services behind Caddy,
nginx, or another TLS reverse proxy. The public issuer and forwarded scheme must
use HTTPS.

Before a deployment:

1. Build and test the revision you plan to run.
2. Validate the production configuration.
3. Back up the databases and local blob storage.
4. Keep the previous binary or image for rollback.

Validate the supplied production configuration with:

```sh
deno run --config ./deno.json -A scripts/validate_pds_config.ts config/production.json
```

## Configuration

Start from `config/production.json` or `config/examples/production.docker.json`.
Keep passwords, master secrets, provider credentials, and storage keys outside
the repository.

Common environment overrides include:

| Variable                  | Purpose                                       |
| ------------------------- | --------------------------------------------- |
| `PDS_ISSUER`              | Public HTTPS issuer URL                       |
| `PDS_HOSTNAME`            | Public hostname                               |
| `PDS_DATA_DIR`            | Service data directory                        |
| `PDS_MASTER_SECRET`       | Server secret                                 |
| `PDS_ADMIN_PASSWORD_FILE` | File containing the admin password            |
| `PDS_ADMIN_PASSWORD`      | Admin password when a secret file is not used |
| `PDS_PLC_URL`             | PLC directory URL                             |
| `PDS_CRAWL_RELAYS`        | Relay URLs announced or contacted by the PDS  |
| `PDS_APPVIEW_URL`         | Remote AppView URL                            |

OAuth client policy can be set to `dynamic` or `allowlist` with
`PDS_OAUTH_CLIENT_POLICY`. The allowlist and trusted-client variables accept
comma-separated client IDs.

See `ATProtoServiceConfiguration.m` for the full set of environment overrides.

## Reverse proxy

Examples are available in:

- `ops/deploy/Caddyfile`
- `ops/deploy/nginx.conf`

A minimal Caddy site looks like:

```caddy
pds.example.com {
    reverse_proxy 127.0.0.1:2583
}
```

Preserve the original host and scheme headers. Configure WebSocket proxying for
firehose endpoints and raise body limits if the PDS accepts large blobs.

## Service process

Example service definitions are in `ops/deploy/pds.service` and
`config/pds.service`.

After installing a new binary:

```sh
sudo systemctl daemon-reload
sudo systemctl restart pds
sudo systemctl status pds --no-pager
journalctl -u pds -n 100 --no-pager
```

Use the actual unit name from your installation.

## Backups

The backup script uses SQLite's backup API for WAL databases:

```sh
./scripts/ops/backup_pds.sh \
  --data-dir /var/lib/atprotopds/data \
  --backup-dir /var/backups/atprotopds
```

Verify the archive it creates:

```sh
./scripts/ops/verify_backup.sh /var/backups/atprotopds/pds-backup-TIMESTAMP.tar.gz
```

The database script does not copy a separate local blob directory. Back up that
directory with the same retention policy when local blob storage is enabled.

## Verify a deployment

Check the service through the public proxy:

```sh
curl -fsS https://pds.example.com/xrpc/_health
curl -fsS https://pds.example.com/xrpc/com.atproto.server.describeServer
```

If federation changed, also test a relay crawl and an active `subscribeRepos`
connection. Roll back the binary if startup or public checks fail and the change
does not require a database migration.
