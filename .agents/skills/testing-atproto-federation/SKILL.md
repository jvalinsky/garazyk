---
name: testing-atproto-federation
description: "Operational workflow for spinning up, verifying, and debugging multi-PDS AT Protocol federation in Garazyk. Covers Docker and binary environment setup, step-by-step cross-PDS verification (identity resolution, follow graphs, record retrieval, relay propagation), log-based debugging of sync failures, and curl-based comparison against the Bluesky PDS reference. Use when setting up federation test environments, diagnosing cross-PDS issues, or verifying relay/crawl behavior."
---

# Testing AT Protocol Federation

End-to-end workflow for setting up a multi-PDS environment, verifying cross-PDS interactions, and debugging federation failures in Garazyk.

Complementary to `atproto-scenario-testing` — that skill runs pre-written Deno scenarios; this skill guides manual setup, verification, and debugging.

## Quick Start

```bash
# Docker mode (recommended for first-time)
./scripts/scenarios/setup_local_network.sh --pds2

# Binary mode (for testing uncommitted changes)
./scripts/scenarios/setup_local_network.sh --binary --pds2

# Teardown
./scripts/scenarios/setup_local_network.sh --teardown
./scripts/scenarios/teardown_local_network.sh --wipe   # also removes volumes
```

## Environment Topology

| Service | Port | URL | Binary |
|---------|------|-----|--------|
| PLC | 2582 | `http://127.0.0.1:2582` | `campagnola` |
| PDS 1 | 2583 | `http://127.0.0.1:2583` | `kaszlak` |
| Relay | 2584 | `http://127.0.0.1:2584` | `zuk` |
| Chat | 2585 | `http://127.0.0.1:2585` | `syrena-chat` |
| Video | 2586 | `http://127.0.0.1:2586` | `jelcz` |
| **PDS 2** | **2587** | `http://127.0.0.1:2587` | `kaszlak` |
| AppView | 3200 | `http://127.0.0.1:3200` | `syrena` |
| UI | 2590 | `http://127.0.0.1:2590` | `garazyk-ui` |

Ports are overridable via env vars: `PLC_PORT`, `PDS_PORT`, `PDS2_PORT`, `RELAY_PORT`, `APPVIEW_PORT`.

### Config Files

- PDS 1: `scripts/scenarios/config/pds-config.json`
- PDS 2: `scripts/scenarios/config/pds2-config.json`
- AppView: `scripts/scenarios/config/appview-config.json`

PDS 2 uses `available_user_domains: ["second.test", "test"]` and a separate `master_secret` (`test-master-secret-456`).

### Docker vs Binary

- **Docker**: builds Linux binaries via `scripts/stage-docker-binaries.sh`, runs in containers. Matches production topology. Use `docker compose -f docker/local-network/docker-compose.yml -f docker/local-network/docker-compose.scenarios.yml up -d`.
- **Binary**: runs `build/bin/kaszlak` etc. directly on host. Disposes data on each start. Set `PDS_RUNNING_TESTS=true` to disable secure storage. Use for testing uncommitted code.

### Health Checks

```bash
# All services
curl -s http://127.0.0.1:2582/_health              # PLC
curl -s http://127.0.0.1:2583/xrpc/com.atproto.server.describeServer  # PDS 1
curl -s http://127.0.0.1:2587/xrpc/com.atproto.server.describeServer  # PDS 2
curl -s http://127.0.0.1:2584/api/relay/health     # Relay
curl -s -H "Authorization: Bearer localdevadmin" http://127.0.0.1:3200/admin/backfill/status  # AppView
```

## Federation Verification Checklist

Follow these steps in order after the environment is up.

### 1. Create Accounts on Both PDS

```bash
# PDS 1 account (handle domain: .test)
curl -s -X POST http://127.0.0.1:2583/xrpc/com.atproto.account.create \
  -H "Content-Type: application/json" \
  -d '{"handle":"alice.test","email":"alice@test.com","password":"test1234"}'

# PDS 2 account (handle domain: .second.test or .test)
curl -s -X POST http://127.0.0.1:2587/xrpc/com.atproto.account.create \
  -H "Content-Type: application/json" \
  -d '{"handle":"bob.second.test","email":"bob@test.com","password":"test1234"}'
```

Record the `did` and `accessJwt` from each response.

### 2. Verify PLC DID Resolution

```bash
# Check PLC has the DID document
curl -s http://127.0.0.1:2582/{DID}

# Verify handle resolution from the other PDS
curl -s "http://127.0.0.1:2587/xrpc/com.atproto.identity.resolveHandle?handle=alice.test"
# Should return {"did":"did:plc:..."}
```

### 3. Cross-PDS Follow

```bash
# Bob (PDS 2) follows Alice (PDS 1)
curl -s -X POST "http://127.0.0.1:2587/xrpc/com.atproto.repo.createRecord" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer {BOB_ACCESS_JWT}" \
  -d '{
    "repo": "{BOB_DID}",
    "collection": "app.bsky.graph.follow",
    "record": {
      "$type": "app.bsky.graph.follow",
      "subject": "{ALICE_DID}",
      "createdAt": "2026-01-01T00:00:00.000Z"
    }
  }'
```

### 4. Cross-PDS Record Retrieval

```bash
# Alice posts on PDS 1
curl -s -X POST "http://127.0.0.1:2583/xrpc/com.atproto.repo.createRecord" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer {ALICE_ACCESS_JWT}" \
  -d '{
    "repo": "{ALICE_DID}",
    "collection": "app.bsky.feed.post",
    "record": {
      "$type": "app.bsky.feed.post",
      "text": "Hello from PDS 1!",
      "createdAt": "2026-01-01T00:00:00.000Z"
    }
  }'

# Bob retrieves Alice's post from PDS 2 (goes through PDS 1 via repo fetch)
curl -s "http://127.0.0.1:2587/xrpc/com.atproto.repo.getRecord?repo={ALICE_DID}&collection=app.bsky.feed.post&rkey={RKEY}"
```

### 5. Verify Relay Propagation

```bash
# Check relay has both PDS as upstreams
curl -s http://127.0.0.1:2584/api/relay/upstreams

# Subscribe to firehose (should see events from both PDS)
curl -s -N "http://127.0.0.1:2584/xrpc/com.atproto.sync.subscribeRepos"
```

### 6. Verify AppView Indexing

```bash
# Bob views Alice's profile via AppView
curl -s "http://127.0.0.1:3200/xrpc/app.bsky.actor.getProfile?actor={ALICE_DID}" \
  -H "Authorization: Bearer {BOB_ACCESS_JWT}"

# Bob views Alice's feed via AppView
curl -s "http://127.0.0.1:3200/xrpc/app.bsky.feed.getAuthorFeed?actor={ALICE_DID}" \
  -H "Authorization: Bearer {BOB_ACCESS_JWT}"
```

### 7. Request Crawl (if relay missed PDS 2)

```bash
# Trigger relay to crawl PDS 2
curl -s -X POST "http://127.0.0.1:2584/xrpc/com.atproto.sync.requestCrawl" \
  -H "Content-Type: application/json" \
  -d '{"hostname":"127.0.0.1:2587"}'
```

## Common Failure Patterns

| Symptom | Likely Cause | See |
|---------|-------------|-----|
| Handle resolution returns wrong DID | PLC not updated, or PDS2 can't reach PLC | [debugging.md](references/debugging.md) |
| Cross-PDS follow returns 400 | DID not resolvable from other PDS | [debugging.md](references/debugging.md) |
| Record retrieval returns 404 | PDS2 can't fetch repo from PDS1, or relay hasn't crawled | [debugging.md](references/debugging.md) |
| Relay shows 0 upstreams | PDS didn't send `requestCrawl` on startup | [debugging.md](references/debugging.md) |
| AppView returns empty profile | AppView not subscribed to relay, or backfill incomplete | [debugging.md](references/debugging.md) |
| `requestCrawl` returns 200 but nothing happens | Relay debounce (20-min min interval) or PDS hostname mismatch | [debugging.md](references/debugging.md) |

## Reference Comparison

For comparing Garazyk behavior against the Bluesky PDS reference implementation, see [reference-comparison.md](references/reference-comparison.md). Contains curl commands for each verification step against `bsky.social` and expected response shapes from the AT Protocol specification.

## Running the Automated Federation Scenario

The automated Deno scenario (05_federation) exercises the same steps with named characters:

```bash
./scripts/run_scenarios.ts 05
```

See `atproto-scenario-testing` skill for full scenario runner documentation.
