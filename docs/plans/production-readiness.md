# Production Readiness Roadmap — ATProto PDS (NSPds)

This document covers the strategic roadmap for transitioning NSPds from a spec-compliant development server to an operationally hardened production service.

## Current State

Phase 10: Spec-Compliant. The server passes 910+ unit/integration tests, implements the core ATProto protocol (repository, sync, identity, auth), and includes SSRF protection, rate limiting, and commit chain signing.

## Operational Critical Path

> The HTTP server is built for correctness and speed but does not include native TLS/SSL for incoming traffic. **A reverse proxy is mandatory for production.**

### 1. External Infrastructure

- **Reverse Proxy**: Use Nginx or Caddy for TLS termination (HTTPS). See `deploy/nginx.conf` and `deploy/Caddyfile`.
- **Public URL**: Configure `server.host` in `config.json` to match your public domain (e.g., `pds.example.com`).
- **DNS/Identity**: Ensure your domain hosts a `did:web` document at `/.well-known/did.json`, or provision PLC records for `did:plc`.

### 2. Persistence and Data Durability

- **Automated Backups**: Use `scripts/backup_pds.sh` for SQLite Online Backup API-based backups.
  - Snapshots `service.sqlite` and individual user `data.sqlite` files.
- **WAL Checkpointing**: The server uses WAL mode. Monitor `.wal` file sizes during high volume.

### 3. Security Hardening

- **Master JWT Key**: Store in Secure Enclave or hardware-backed Keychain. Enabled via `useKeychain` and `useBiometricProtection` in `PDSConfiguration`.
- **Rate Limiting**: Enable the built-in `RateLimiter`. Configure production-appropriate limits for DID-based and IP-based traffic.
- **OAuth Discovery**: Update the issuer URL in the server builder to use your production HTTPS URL.

### 4. Protocol Essentials (Remaining Spec Work)

- **Sequencer Completion**: Finish `sequencer.sqlite` (Phase 11/12). Without a robust sequencer, `subscribeRepos` (Firehose) won't be reliable for relay aggregators.
- **Relay Integration**: Register your PDS with the Bluesky Relay or your chosen relay service.

## Deployment Files

| File | Purpose |
|------|---------|
| `deploy/production.json` | Production configuration template |
| `deploy/nginx.conf` | Nginx reverse proxy with TLS |
| `deploy/Caddyfile` | Caddy reverse proxy (auto-TLS) |
| `deploy/com.atproto.pds.plist` | macOS launchd service |
| `deploy/pds.service` | Linux systemd service |
| `scripts/backup_pds.sh` | Automated SQLite backup script |

## Monitoring and Observability

- **Prometheus**: Scrape the `/metrics` endpoint to monitor active connections, blob storage growth, HTTP 5xx rates.
- **Log Rotation**: Configure `maxLogFileSize` and `maxLogFiles` to prevent disk exhaustion.

## Verification Plan

### Automated

```bash
./scripts/run_conformance.sh
./scripts/run_e2e.sh
```

### Manual

1. **Public Identity**: Verify `https://your-domain/.well-known/did.json` returns a valid DID document.
2. **Bluesky Client**: Log into the PDS using the official Bluesky web or iOS client via OAuth.
3. **Firehose Tail**: Monitor the firehose for correct sequences:
   ```bash
   ./build/bin/atprotopds-cli repo list-events
   ```
