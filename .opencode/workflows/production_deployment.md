# Production Deployment Workflow (pds.garazyk.xyz)

This workflow defines the secure and mandatory steps for deploying to the production environment.

## Critical Mandates
- **Out-of-source builds**: NEVER run `cmake` in the repo root.
- **Docker Context**: ALWAYS run `docker compose` from `docker/pds/`, NEVER from repo root.

## Secure Defaults - MANDATORY
Do not proceed if any of these are weakened:
- `session.invite_code_required`: `true`
- `plc.url`: `"https://plc.directory"`
- All `debug.*` flags: `false`
- `rate_limit.enabled`: `true`
- `server.issuer`: `"https://pds.garazyk.xyz"`

## Deployment Procedure
1. **Prepare VM**: Connect to `DEPLOY_HOST`.
2. **Execute Deployment**:
   ```bash
   cd DEPLOY_DIR/objpds/docker/pds
   docker compose up -d
   docker compose logs -f pds
   docker exec nspds kaszlak invite create
   ```
3. **Verify Configuration**:
   ```bash
   curl -s http://localhost:2583/xrpc/com.atproto.server.describeServer
   ```
   Must show: `"did":"did:web:pds.garazyk.xyz"`

## Volume Backup Procedure
```bash
mkdir -p DEPLOY_DIR/backup
TS=$(date +%Y%m%d-%H%M%S)
docker run --rm \
  -v pds_pds_data:/data \
  -v DEPLOY_DIR/backup:/backup \
  busybox sh -c "cd /data && tar -czf /backup/pds_pds_data-$TS.tar.gz ."
```
