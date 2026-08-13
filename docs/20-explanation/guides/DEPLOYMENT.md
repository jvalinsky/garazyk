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

### Streamplace + multi-jelcz peership lab

To add a Streamplace origin and three HTTPS-peering `jelcz` nodes on the same
Docker network (ports 38080 / 2596–2598):

```sh
./scripts/demo/streamplace_peership_up.sh
./scripts/demo/streamplace_peership_smoke.sh
```

Guide: [Streamplace and jelcz peership lab](streamplace-jelcz-peership-lab.md).
Compose: `docker/streamplace-peership/`.

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
| `PDS_LINUX_KEYCHAIN_KEY`  | Linux secret-store encryption key             |
| `PDS_LINUX_KEYCHAIN_KEY_FILE` | File containing the Linux secret-store key |
| `PDS_PLC_URL`             | PLC directory URL                             |
| `PDS_CRAWL_RELAYS`        | Relay URLs announced or contacted by the PDS  |
| `PDS_APPVIEW_URL`         | Remote AppView URL                            |

OAuth client policy can be set to `dynamic` or `allowlist` with
`PDS_OAUTH_CLIENT_POLICY`. The allowlist and trusted-client variables accept
comma-separated client IDs.

See `ATProtoServiceConfiguration.m` for the full set of environment overrides.

### Linux secret-store key

Linux `SecItem` storage is encrypted at rest with an operator-managed key. Set
exactly one of `PDS_LINUX_KEYCHAIN_KEY` or `PDS_LINUX_KEYCHAIN_KEY_FILE` before
starting a service that uses the secret store; a secret file mounted with
restricted permissions is preferred. The service refuses to start without a
usable key and never falls back to plaintext storage.

The database remains permission-restricted (`0700` parent directory and `0600`
database file), but this is operator-key-based encryption rather than
hardware-backed keychain protection. Preserve the key with the database backup:
if the key is lost, encrypted secret-store contents cannot be recovered. An
upgrade migrates existing plaintext rows to encrypted form; the legacy reader
is retained for at least one release.

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
connection. For a Zuk relay, check `/api/relay/health` and
`/api/relay/upstreams`; the root URL serves the operator dashboard. A short
firehose monitor run provides a repeatable stream check:

```sh
deno run -A scripts/monitor_relay_firehose.ts \
  --relay-url https://relay.example.com \
  --duration 30 \
  --no-color
```

Roll back the binary if startup or public checks fail and the change does not
require a database migration.
