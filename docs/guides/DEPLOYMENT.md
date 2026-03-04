---
title: Deployment Guide
---

# Deployment Guide

## HTTPS Requirement

**The PDS speaks plain HTTP.** It does not terminate TLS itself. You must place it behind a reverse proxy that handles HTTPS. Without TLS, the AT Protocol OAuth flow will not work and Bluesky/relay connections will be refused.

The recommended port for the PDS process is **2583** (default) or **8080** (as used in `deploy/production.json`). Your reverse proxy listens on 443 and forwards to that port.

---

## Quick Start with Caddy (Recommended)

[Caddy](https://caddyserver.com) provisions and renews Let's Encrypt certificates automatically.

**Minimal config** — create `/etc/caddy/Caddyfile`:

```

pds.example.com {
    reverse_proxy :2583
}
```

A production-ready config with connection pooling, security headers, and structured logging is in [`deploy/Caddyfile`](# Deploy file: Caddyfile). Replace `pds.example.com` and the backend port, then:

```sh
sudo systemctl reload caddy
```

---

## Nginx

A full nginx config including WebSocket support for `subscribeRepos` and TLS hardening is in [`deploy/nginx.conf`](# Deploy file: nginx.conf).

```sh
sudo ln -s /etc/nginx/sites-available/atprotopds.conf /etc/nginx/sites-enabled/
sudo certbot --nginx -d pds.example.com
sudo systemctl reload nginx
```

---

## Required Environment Variables

These must be set before starting the server. The process will **refuse to start** if `PDS_ENV=production` is set but `PDS_ISSUER` is missing or contains `pds.local`.

| Variable | Required | Example | Notes |
|---|---|---|---|
| `PDS_ISSUER` | Yes (production) | `https://pds.example.com` | Must match your public domain exactly, with `https://` |
| `PDS_ENV` | Recommended | `production` | Enables startup safety checks |
| `PDS_ADMIN_PASSWORD` | Yes | `pbkdf2:600000:<salt>:<hash>` | Use `pbkdf2:` prefix; plain text triggers a warning |
| `PDS_DISABLE_X_ADMIN_TOKEN_HEADER` | Recommended | `1` | Disable legacy header in production |
| `PDS_EMAIL_PROVIDER_TYPE` | Recommended | `resend` or `smtp` | Email required for account confirmation |

For Resend email:

| Variable | Notes |
|---|---|
| `RESEND_API_KEY` | API key from resend.com |
| `PDS_EMAIL_RESEND_FROM` | Sender address, e.g. `noreply@pds.example.com` |

---

## macOS launchd Service

A ready-to-use launchd plist is at [`deploy/com.atproto.pds.plist`](# Deploy file: com.atproto.pds.plist). Edit it to set your domain and admin password, then:

```sh
sudo cp deploy/com.atproto.pds.plist /Library/LaunchDaemons/
sudo launchctl load /Library/LaunchDaemons/com.atproto.pds.plist
```

The plist pre-sets `PDS_ENV=production` and `PDS_DISABLE_X_ADMIN_TOKEN_HEADER=1`. You must replace the placeholder values for `PDS_ISSUER` and `PDS_ADMIN_PASSWORD`.

---

## Data Directory and Backups

By default, all data lives under `data/` (or whatever `--data-dir` points to):

```

data/
  service/          # Accounts, sessions, invite codes (SQLite, WAL mode)
  did_cache/        # DID document cache
  sequencer/        # Event sequencer
  blobs/            # Uploaded files
  *.key             # JWT signing key (keep this secret)
  .admin_min_iat    # Token invalidation state (survives restarts)
```

**Backup strategy:** Copy the entire `data/` directory while the server is stopped, or use SQLite's online backup API. Because WAL mode is enabled, a simple `cp` of `.db` and `.db-wal` files while the server is running is unsafe — use `sqlite3 data/service/__service__.db ".backup /backup/service.db"` instead.

---

## Verifying the Deployment

```sh
# Health check
curl https://pds.example.com/xrpc/_health

# WAL mode sanity check (run on the server)
sqlite3 data/service/__service__.db 'PRAGMA journal_mode;'
# Should print: wal
```

---

## Related Documentation

- **[Setup Guide](# Setup guide)** - Initial build and configuration
- **[Security Plan](../security/SECURITY_PLAN)** - Security validation strategy
- **[Admin Auth Configuration](../security/ADMIN_AUTH_CONFIGURATION)** - Admin password setup
- **[SSRF Protection](../security/SSRF_PROTECTION)** - Network security hardening
- **[OAuth 2.0 Overview](../oauth2/README)** - Authentication endpoints
- **[Architecture Analysis](../architecture/ARCHITECTURE_ANALYSIS)** - System components
- **[Script Development](SCRIPT_DEVELOPMENT)** - Production script standards
- **[macOS Network Guide](macOS_Network_Server_Guide)** - Platform-specific networking
