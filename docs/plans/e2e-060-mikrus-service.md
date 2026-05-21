# Sub-plan: 60 — Mikrus Service in Docker Compose

## Problem
Scenario 60 connects to `http://localhost:3210/xrpc/blue.microcosm.repo.getRecordByUri` but gets "Connection refused". The Mikrus service (port 3210) is not running in Docker Compose.

## Task
Add Mikrus service to `docker/local-network/docker-compose.yml`.

## Investigation Needed
1. Find what Mikrus is — search for its binary or Docker image reference in the project (`blue.microcosm.*` lexicons)
2. Check if there's a Dockerfile or image for it already (`docker/`)
3. Find its startup command, port config, and env vars
4. Check how it connects to other services (PDS, AppView, PLC)

## Implementation
1. Add service definition to `docker-compose.yml`
2. Add health check endpoint
3. Add network config (should join `local_net`)
4. Update topology config if needed (`packages/schemat/topology_presets.ts`)
5. Verify with health check before scenario run

## Verification
```bash
curl localhost:3210/xrpc/_health
nix develop -c bash -c "cd scripts/scenarios && deno run -A e2e_runner.ts --scenario 60"
```
