# Debugging Federation Failures

## Table of Contents

- [Log Locations](#log-locations)
- [XRPC Tracing](#xrpc-tracing)
- [Common Failure Patterns](#common-failure-patterns)
- [Diagnostic Collection](#diagnostic-collection)

## Log Locations

### Binary Mode

Logs are written to the run directory under `/tmp/garazyk-atproto-e2e/`:

```
/tmp/garazyk-atproto-e2e/{run-id}/
├── logs/
│   ├── plc.log
│   ├── pds.log
│   ├── pds2.log
│   ├── relay.log
│   ├── appview.log
│   ├── video.log
│   └── ui.log
├── data/          # disposable data root
└── pids           # process ID file
```

The run directory path is printed at startup: `Run: /tmp/garazyk-atproto-e2e/...`

### Docker Mode

```bash
# Per-container logs
docker compose -p garazyk-e2e-{run-id} logs local-pds
docker compose -p garazyk-e2e-{run-id} logs local-pds2
docker compose -p garazyk-e2e-{run-id} logs local-relay
docker compose -p garazyk-e2e-{run-id} logs local-appview

# Follow live
docker compose -p garazyk-e2e-{run-id} logs -f local-pds2
```

### Key Log Patterns

Search for these in PDS logs:

```
# Identity resolution
grep -i "resolveHandle\|resolveIdentity\|DID" pds2.log

# Cross-PDS repo fetch
grep -i "getRepo\|fetchRepo\|sync.getRepo" pds2.log

# Relay crawl
grep -i "requestCrawl\|subscribeRepos" pds.log pds2.log

# AppView indexing
grep -i "ingest\|index\|backfill" appview.log
```

## XRPC Tracing

### Trace a Single XRPC Call

```bash
# Verbose curl to see request/response headers
curl -v "http://127.0.0.1:2587/xrpc/com.atproto.identity.resolveHandle?handle=alice.test"

# Check response timing
curl -o /dev/null -s -w "HTTP %{http_code} in %{time_total}s\n" \
  "http://127.0.0.1:2587/xrpc/com.atproto.repo.getRecord?repo={DID}&collection=app.bsky.feed.post&rkey={RKEY}"
```

### Trace Relay Firehose

```bash
# Subscribe and capture first 10 events
curl -s -N "http://127.0.0.1:2584/xrpc/com.atproto.sync.subscribeRepos" | head -c 100000 > /tmp/firehose.bin

# Check relay upstream list
curl -s http://127.0.0.1:2584/api/relay/upstreams | python3 -m json.tool
```

### Trace AppView Ingest

```bash
# Check backfill status
curl -s -H "Authorization: Bearer localdevadmin" \
  http://127.0.0.1:3200/admin/backfill/status | python3 -m json.tool

# Check if AppView has the record
curl -s "http://127.0.0.1:3200/xrpc/app.bsky.feed.getAuthorFeed?actor={DID}" \
  -H "Authorization: Bearer {JWT}" | python3 -m json.tool
```

## Common Failure Patterns

### Handle Resolution Returns Wrong DID or Fails

**Symptoms**: `com.atproto.identity.resolveHandle` returns empty, wrong DID, or 400.

**Causes**:
1. PLC not updated — PDS2 can't reach `http://localhost:2582`
2. DNS/HTTP handle verification fails — PDS2 can't reach PDS1's HTTP endpoint
3. Stale DID document in PLC cache

**Debug**:
```bash
# Check PLC directly
curl -s http://127.0.0.1:2582/{DID} | python3 -m json.tool

# Check PDS2's PLC config
grep -A3 plc scripts/scenarios/config/pds2-config.json
# Should show: "url": "http://localhost:2582"

# Test from PDS2's perspective
curl -s "http://127.0.0.1:2587/xrpc/com.atproto.identity.resolveHandle?handle=alice.test"
```

### Cross-PDS Follow Returns 400

**Symptoms**: `com.atproto.repo.createRecord` for `app.bsky.graph.follow` fails with 400 or "subject not found".

**Causes**:
1. PDS2 cannot resolve the subject's DID to fetch their DID document
2. The subject's DID document doesn't point back to PDS1
3. PDS2's PLC URL is misconfigured

**Debug**:
```bash
# Verify PDS2 can resolve the DID
curl -s "http://127.0.0.1:2587/xrpc/com.atproto.identity.resolveHandle?handle=alice.test"

# Check DID document has correct service endpoint
curl -s http://127.0.0.1:2582/{ALICE_DID} | python3 -m json.tool
# Look for "service" array with "atproto_pds" endpoint pointing to PDS1
```

### Record Retrieval Returns 404

**Symptoms**: `com.atproto.repo.getRecord` for a cross-PDS record returns 404.

**Causes**:
1. PDS2 can't fetch the repo from PDS1 (network or auth issue)
2. The record hasn't been committed yet (race condition)
3. PDS2 doesn't implement repo fetching for remote DIDs

**Debug**:
```bash
# Try fetching directly from PDS1
curl -s "http://127.0.0.1:2583/xrpc/com.atproto.repo.getRecord?repo={ALICE_DID}&collection=app.bsky.feed.post&rkey={RKEY}"

# Try from PDS2 (should proxy or fetch from PDS1)
curl -s "http://127.0.0.1:2587/xrpc/com.atproto.repo.getRecord?repo={ALICE_DID}&collection=app.bsky.feed.post&rkey={RKEY}"

# Check PDS2 logs for repo fetch attempts
grep -i "getRepo\|fetchRepo\|sync" /tmp/garazyk-atproto-e2e/*/logs/pds2.log
```

### Relay Shows 0 Upstreams

**Symptoms**: `GET /api/relay/upstreams` returns empty list.

**Causes**:
1. PDS didn't send `requestCrawl` on startup
2. Relay can't reach PDS WebSocket endpoint
3. PDS hostname in `requestCrawl` doesn't match relay's expected format

**Debug**:
```bash
# Check relay upstreams
curl -s http://127.0.0.1:2584/api/relay/upstreams

# Manually request crawl
curl -s -X POST "http://127.0.0.1:2584/xrpc/com.atproto.sync.requestCrawl" \
  -H "Content-Type: application/json" \
  -d '{"hostname":"127.0.0.1:2583"}'

# Wait and recheck
sleep 5
curl -s http://127.0.0.1:2584/api/relay/upstreams

# Check relay logs
grep -i "crawl\|upstream\|subscribe" /tmp/garazyk-atproto-e2e/*/logs/relay.log
```

### AppView Returns Empty Profile or Feed

**Symptoms**: `app.bsky.actor.getProfile` returns empty or 404 for cross-PDS actors.

**Causes**:
1. AppView not subscribed to relay firehose
2. AppView backfill hasn't completed
3. AppView can't resolve the DID through PLC

**Debug**:
```bash
# Check AppView backfill status
curl -s -H "Authorization: Bearer localdevadmin" \
  http://127.0.0.1:3200/admin/backfill/status | python3 -m json.tool

# Check AppView PLC config
echo $APPVIEW_PLC_URL  # Should be http://127.0.0.1:2582

# Check AppView logs for ingest errors
grep -i "ingest\|error\|fail" /tmp/garazyk-atproto-e2e/*/logs/appview.log
```

### requestCrawl Returns 200 But Nothing Happens

**Symptoms**: Relay accepts crawl request but doesn't start crawling.

**Causes**:
1. PDSRelayService enforces 20-minute minimum interval between notifications for the same hostname
2. Hostname in request doesn't match PDS's actual hostname
3. Relay WebSocket connection already established but PDS isn't sending events

**Debug**:
```bash
# Check relay logs for crawl processing
grep -i "crawl\|request" /tmp/garazyk-atproto-e2e/*/logs/relay.log

# Try with explicit hostname matching PDS config
curl -s -X POST "http://127.0.0.1:2584/xrpc/com.atproto.sync.requestCrawl" \
  -H "Content-Type: application/json" \
  -d '{"hostname":"localhost:2583"}'
```

## Diagnostic Collection

The setup script has built-in diagnostic collection:

```bash
# Collect diagnostics before teardown
./scripts/scenarios/setup_local_network.sh --collect-diagnostics

# Or via teardown
./scripts/scenarios/teardown_local_network.sh --collect-diagnostics
```

Diagnostics include:
- Health endpoint responses for all services
- Relay upstream list
- AppView backfill status
- Docker compose state (if Docker mode)
- Service logs

Output goes to `/tmp/garazyk-atproto-e2e/{run-id}/diagnostics/`.

### Manual Diagnostics

```bash
# Quick health sweep
for svc in "2582/_health" "2583/xrpc/com.atproto.server.describeServer" "2587/xrpc/com.atproto.server.describeServer" "2584/api/relay/health"; do
  port=$(echo "$svc" | cut -d/ -f1)
  path=$(echo "$svc" | cut -d/ -f2-)
  status=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$port/$path")
  echo "Port $port: $status"
done
```
