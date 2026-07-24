---
title: Deployment Guide
---

# Deployment Guide

## Local Development

To start the full local ATProto services stack (PLC, PDS, Relay, AppView) inside Docker for local testing or scenario runs, use the provided setup script:

```bash
./scripts/scenarios/setup_local_network.sh
```

Alternatively, you can run the Compose file directly:

```bash
docker compose -f docker/local-network/docker-compose.yml up
```

## Standalone PDS Self-Hosting

If you only want to deploy a standalone, self-hosted PDS instance, you can use the Compose configuration under `docker/pds/`:

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

Garazyk supports strict operator policies and spoofing protection for AT Protocol OAuth clients. By default, standard dynamic client registration behaves as defined in the ATProto spec (`dynamic`).

Under the `oauth` configuration map in JSON configuration:

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
> Dynamic untrusted client metadata will automatically have their display names (`client_name`) sanitized to their raw client ID HTTPS URLs to protect against phishing/spoofing attacks.

## JSON Configuration

Garazyk services are configured via JSON files (such as `config/production.json`). The system parses these configs strictly with strong-type verification while providing convenient compatibility fallbacks.

### Key Blocks

#### 1. Remote AppView Block (`appview`)
The remote AppView query and validation block is defined using lowercase keys:
```json
"appview": {
  "url": "https://api.bsky.app",
  "did": "did:web:api.bsky.app"
}
```
* **Fallback compatibility**: The PDS config parser supports lookup compatibility with camelCase `"appView"` should downstream environments define it.

#### 2. CORS Block (`cors`)
Configure CORS headers using native JSON arrays and integers. The type-safe parser extracts arrays and joins elements properly under the hood:
```json
"cors": {
  "allowed_origins": ["https://witchsky.app", "*"],
  "allowed_methods": ["GET", "POST", "PUT", "DELETE", "OPTIONS", "HEAD"],
  "allowed_headers": ["DPoP", "Authorization", "Content-Type", "*"],
  "max_age": 86400
}
```

#### 3. PLC Replica Nested Configuration (`plc`)
To enable local replica lookup, nest the replica configuration block directly inside the `"plc"` block under the `"replica"` key:
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
In scenario and test configurations, the AppView configuration parser supports both standard **dotted namespace** keys (`plc.url`, `backfill.enabled`, etc.) and flat **snake_case fallbacks** (`plc_url`, `backfill_enabled`, etc.) for seamless configuration of local end-to-end testing topologies.


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
