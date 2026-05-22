---
name: garazyk-release-ops
description: Plan, execute, or review Garazyk production deployment and release operations. Covers ops/deploy, backups, config validation, nginx/Caddy/TLS, rollback, service health checks, secrets, and post-deploy verification.
---

# Garazyk Release Ops

Use this skill for production deployment, release checklists, rollback plans, backup/restore, reverse-proxy setup, and operational verification.

## Key files

- Deployment scripts: `ops/deploy/`, `scripts/ops/`
- Config examples: `config/examples/*.json`, `config/production.json`
- Service config: `config/pds.service`, `config/nginx-pds.conf`
- Docker deployment: `docker/pds/docker-compose.yml`, `docker/pds/config.json`, `docker/Dockerfile.gnustep`
- Validation: `scripts/validate_pds_config.ts`
- Backup tools: `scripts/ops/backup_pds.sh`, `scripts/ops/verify_backup.sh`, `scripts/ops/db_dump.sh`
- Production helpers: `scripts/ops/production/*.sh`
- Deployment docs: `docs/20-explanation/guides/DEPLOYMENT.md`

## Operating principles

- Treat production secrets, tokens, keys, phone/email credentials, and database files as sensitive.
- Never paste secrets into chat or commit them.
- Prefer dry-run, validation, and explicit health checks before restart/cutover.
- Production ATProto/OAuth requires HTTPS behind a reverse proxy.
- Keep rollback and backup verification in the same plan as deployment.

## Release workflow

### 1. Establish target and change scope

Before touching production, identify:

- host and service name
- binary/Docker deployment mode
- git revision to deploy
- config file path and secrets source
- databases and blob storage paths
- reverse proxy (Nginx/Caddy/other)
- expected public issuer/hostnames
- rollback target

Record a deciduous goal/action for operational work.

### 2. Preflight validation

Run local/project checks first:

```bash
deno run -A scripts/validate_pds_config.ts config/production.json
./scripts/ops/security_audit.sh
```

For code changes, run the relevant build/test gate before deployment:

```bash
garazyk_build_test
```

Check for obvious production blockers:

- `PDS_ISSUER` uses HTTPS public host, not localhost/test placeholder
- admin password is set and hashed as expected
- OAuth issuer and reverse-proxy URLs align
- email/phone providers have required secrets only in environment/secret store
- service user owns data directories
- backup location has space and permissions

### 3. Backup before cutover

Use project backup scripts rather than ad-hoc copies:

```bash
scripts/ops/backup_pds.sh
scripts/ops/verify_backup.sh <backup-path>
```

Confirm:

- SQLite files captured consistently
- WAL/shm handling is correct
- blob storage is included or separately backed up
- restore path is documented
- backup artifact is not stored in the repo

### 4. Deploy

Use the repository's deployment scripts if present. If manual:

1. stage binaries or images
2. stop or reload service according to the deployment mode
3. apply config/environment changes
4. restart service
5. tail logs during startup
6. run health checks before declaring success

Systemd pattern:

```bash
sudo systemctl daemon-reload
sudo systemctl restart pds
sudo systemctl status pds --no-pager
journalctl -u pds -n 200 --no-pager
```

Docker pattern:

```bash
docker compose pull || true
docker compose up -d --build
docker compose ps
docker compose logs --tail=200
```

### 5. Reverse proxy and TLS

Production must terminate TLS. Verify:

- public `https://<host>/.well-known/atproto-did` if applicable
- `https://<host>/xrpc/com.atproto.server.describeServer`
- OAuth metadata endpoints
- WebSocket/firehose proxy settings if relay/appview endpoints are exposed
- body size limits for blobs/video
- forwarding headers preserve scheme/host

Nginx config starts at `config/nginx-pds.conf`; Caddy configs should preserve equivalent behavior.

### 6. Post-deploy health verification

Minimum checks:

```bash
curl -fsS https://<host>/xrpc/com.atproto.server.describeServer
curl -fsS https://<host>/xrpc/_health || true
```

Then verify the service-specific contract:

- create/login test account only if safe for environment
- resolve known DID/handle
- upload/read small blob if blob changes were involved
- OAuth metadata and authorization flow if auth changed
- relay crawl/firehose checks if federation changed
- admin UI login and account listing if UI changed

### 7. Rollback

Rollback plan must name:

- previous git revision/image/binary
- config rollback file
- database rollback/restore decision
- commands to restart service
- health check that confirms rollback

Do not restore a database backup unless schema/data changes require it. If migrations are not reversible, document the forward-fix path.

## Triage after failed deploy

Classify first:

| Symptom | Check |
| --- | --- |
| service will not start | config validation, env vars, missing secrets, database path permissions |
| 502 from proxy | service port/listen host, systemd status, Docker port mapping |
| OAuth/federation rejected | HTTPS issuer, forwarded proto/host, public metadata |
| database locked/corrupt | WAL files, process ownership, backup restore, concurrent writers |
| blob upload fails | body size, storage path, permissions, content-type validation |

Return an ops note with: failure, evidence, command output path/log line, rollback decision, next command.

## Definition of done

- Config validated.
- Backup created and verified.
- Deployment command/path recorded.
- TLS/reverse proxy verified.
- Service health checks pass.
- Rollback path documented.
- Deciduous outcome logged with commit/revision.
