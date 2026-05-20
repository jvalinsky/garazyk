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
