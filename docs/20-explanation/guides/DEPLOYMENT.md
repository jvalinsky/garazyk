---
title: Deployment Guide
---

# Deployment Guide

## Local Development

Start the local ATProto services stack (PLC, PDS, Relay, AppView) inside Docker for local testing:

```bash
./scripts/scenarios/setup_local_network.sh
```

Or run the Compose file directly:

```bash
docker compose -f docker/local-network/docker-compose.yml up
```

## Standalone PDS Self-Hosting

For a standalone PDS instance, use the Compose configuration in `docker/pds/`:

```bash
docker compose -f docker/pds/docker-compose.yml up -d
```

## Production Deployment

Garazyk services speak plain HTTP. Place them behind a reverse proxy to terminate TLS/HTTPS.

### Reverse Proxy (Caddy)

Sample Caddyfile in `ops/deploy/Caddyfile`:

```caddy
pds.garazyk.xyz {
    reverse_proxy localhost:2583
}
```

### Reverse Proxy (nginx)

Sample nginx config in `ops/deploy/nginx.conf`.

### Systemd Service

Sample unit file in `ops/deploy/pds.service`.

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `PDS_ISSUER` | Yes | DID of the PDS instance |
| `PDS_ADMIN_PASSWORD` | Yes | Admin UI password |
| `PDS_HOSTNAME` | Yes | Public hostname |
| `PDS_PORT` | No | Listen port (default: 2583) |
| `PDS_OAUTH_CLIENT_POLICY` | No | OAuth client policy: `dynamic` (default) or `allowlist` |
| `PDS_OAUTH_ALLOWED_CLIENT_IDS` | No | Comma-separated list of allowed OAuth Client IDs (when using `allowlist` policy) |
| `PDS_OAUTH_TRUSTED_CLIENT_IDS` | No | Comma-separated list of trusted OAuth Client IDs permitted to display custom names |

### Configurable OAuth Client Policy

Garazyk enforces operator policies for AT Protocol OAuth clients. The default `dynamic` policy follows the ATProto spec for dynamic client registration.

Set the `oauth` configuration map in JSON:

```json
{
  "oauth": {
    "client_policy": "dynamic",
    "allowed_client_ids": [
      "https://bsky.app/oauth/client-metadata.json"
    ],
    "trusted_client_ids": [
      "https://bsky.app/oauth/client-metadata.json"
    ]
  }
}
```

> [!NOTE]
> Database-registered clients are implicitly trusted and allowed under both policies.
> The server sanitizes untrusted `client_name` metadata to the client ID HTTPS URL to prevent spoofing.

## JSON Configuration

Garazyk uses JSON configuration files (e.g., `config/production.json`). The parser enforces types and supports fallback keys.

### Key Blocks

#### 1. Remote AppView Block (`appview`)
The AppView block uses lowercase keys:
```json
"appview": {
  "url": "https://api.bsky.app",
  "did": "did:web:api.bsky.app"
}
```
The parser also accepts the camelCase `appView` key.

#### 2. CORS Block (`cors`)
Set CORS headers using JSON arrays and integers. The parser joins array elements:
```json
"cors": {
  "allowed_origins": ["https://witchsky.app", "*"],
  "allowed_methods": ["GET", "POST", "PUT", "DELETE", "OPTIONS", "HEAD"],
  "allowed_headers": ["DPoP", "Authorization", "Content-Type", "*"],
  "max_age": 86400
}
```

#### 3. PLC Replica Nested Configuration (`plc`)
To enable local replica lookup, nest the `replica` block inside the `plc` block:
```json
"plc": {
  "url": "https://plc.directory",
  "replica": {
    "enabled": false,
    "upstream_url": "https://plc.directory",
    "bind_address": "0.0.0.0:2584",
    "data_dir": "/var/lib/plc-replica"
  }
}
```

### AppView Scenario Key Fallbacks
The AppView parser accepts both dotted keys (`plc.url`, `backfill.enabled`) and snake_case fallbacks (`plc_url`, `backfill_enabled`) for local testing configurations.


## Database Backups

SQLite databases are stored in the data directory. Use `sqlite3 .backup` or file-level
snapshots for backups.

```bash
sqlite3 data/actor-store.db ".backup backup/actor-store.db"
```

## Configuration Files

| File | Purpose |
|---|---|
| `config/production.json` | Production PDS config |
| `ops/deploy/Caddyfile` | Caddy reverse proxy |
| `ops/deploy/nginx.conf` | nginx reverse proxy |
| `ops/deploy/pds.service` | systemd unit |
