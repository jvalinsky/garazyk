---
title: Deployment Guide
---

# Deployment Guide

## Local Development

```bash
docker compose up
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
