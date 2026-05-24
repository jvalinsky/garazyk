---
name: garazyk-scenario-triage
description: Triage failed Garazyk Deno/TypeScript ATProto scenario runs. Use when analyzing scripts/run_scenarios.ts failures, JSON reports, diagnostics bundles, Docker/service logs, local-network health, cross-PDS federation issues, OAuth/browser-flow failures, flaky timing, or scenario dashboard data.
---

# Garazyk Scenario Triage

Use this skill to diagnose failing scenario runs without drowning the session in logs. The goal is a short, evidence-backed failure theory and the next smallest verification step.

## When to use

Use this skill for requests like:

- "triage scenario 56"
- "why did this e2e run fail?"
- "analyze `/tmp/garazyk-atproto-e2e/<run-id>`"
- "scenario dashboard shows failures"
- "federation/OAuth/firehose scenario is flaky"
- "collect diagnostics and summarize likely root cause"

> [!TIP]
> **Programmatic Agent-First Triage**: You can leverage the programmatic [agent-scenario-testing](file:///.agents/skills/agent-scenario-testing/SKILL.md) skill. Simply run `deno task hamownia agent triage --run-id <run-id>` to get a fully parsed, machine-readable triage analysis mapped directly to subsystem boundaries.


## Core files and locations

- Runner: `scripts/run_scenarios.ts`
- Scenario files: `scripts/scenarios/scenarios/NN_name.ts`
- Scenario docs: `scripts/scenarios/README.md`
- Standards: `scripts/scenarios/SCENARIO_STANDARDS.md`
- Shared helpers: `scripts/lib/deno/`
- Topology compiler: `scripts/scenarios/compile_topology.ts`
- Topology presets: `scripts/scenarios/topologies/*.json`
- Default report root: `/tmp/garazyk-atproto-e2e/<run-id>/`
- In-repo report cache: `scripts/scenarios/reports/`
- Dashboard database: `scripts/scenarios/reports/dashboard.db`

Diagnostics bundles commonly contain:

- `run-metadata.*` — run id, repo state, URLs, compose project
- `http/*.txt` — health/admin endpoint captures, redacted tokens
- `docker/ps.txt` — container status
- `docker/config.txt` — compose config
- `docker/logs/*.log` or `service-logs/*.log` — service logs
- scenario JSON reports under `reports/`

## Context-window rule

Logs and reports can be large. Do not paste raw logs into chat. Use context-mode tools when available:

- `ctx_execute_file` for a single JSON report, log, or dashboard export
- `ctx_execute` for scripted summaries over directories
- `ctx_batch_execute` for multiple shell probes plus targeted search

If context-mode is unavailable, use small filtered commands: `rg`, `tail`, `jq`, `sqlite3`, and report only the relevant lines.

## Triage workflow

### 1. Identify the run and scenario

Ask for the run id or report path if it is not obvious. If the user gives only a scenario number, check the latest run directories and in-repo reports.

Useful probes:

```bash
ls -td /tmp/garazyk-atproto-e2e/* 2>/dev/null | head
find /tmp/garazyk-atproto-e2e -path '*/reports/*.json' -type f | sort | tail
./scripts/run_scenarios.ts --list
```

For a single scenario file:

```bash
ls scripts/scenarios/scenarios/NN_*.ts
```

### 2. Summarize the JSON report first

Start with structured data before logs. Extract:

- scenario name and id
- run id and diagnostics directory
- failed/skipped/passed counts
- first failing step
- all failing steps and error messages
- durations and suspicious slow steps
- artifacts recorded by the scenario

Preferred local analysis pattern:

```bash
python3 - <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
print(data.get('scenario'))
print(data.get('summary'))
for step in data.get('steps', []):
    if step.get('status') != 'passed':
        print(step.get('status'), step.get('name'), step.get('detail') or step.get('error'))
PY path/to/report.json
```

Do not infer root cause from the final summary alone. The first failing step usually matters most.

### 3. Map the failure to service boundaries

Classify the failure before reading code:

| Symptom | Likely boundary |
| --- | --- |
| connection refused, timeout, 502 | service startup, port, reverse proxy, Docker health |
| 401/403 | auth, token, OAuth/DPoP, admin session, scope |
| 400 validation error | scenario payload, lexicon mismatch, input validation |
| 404 XRPC method | route registration, service mismatch, topology URL |
| 409/conflict | account/record pre-exists, idempotency, TID/CID conflict |
| 429 | rate limiter not disabled or scenario load exceeds config |
| DID/handle mismatch | PLC, identity resolver, cache, cross-PDS setup |
| missing feed/profile data | AppView ingest, relay propagation, cursor lag |
| firehose gap/order issue | relay, sequencer, cursor persistence, backpressure |
| browser/OAuth redirect failure | UI service, client metadata, callback URL, HTTPS/local policy |
| intermittent pass/fail | timing, health readiness, eventual consistency, teardown residue |

### 4. Inspect only relevant logs

Use the scenario step to choose logs:

- PDS account, repo, blob, OAuth, auth failures: PDS logs
- identity/DID failures: PLC logs and `http/*plc*`
- AppView feed/profile/search failures: AppView logs and ingest/backfill captures
- federation/firehose failures: Relay logs, PDS repo event logs, AppView ingest logs
- chat failures: chat service logs plus PDS auth logs
- video failures: video service logs plus blob/PDS logs
- browser flow failures: UI/web-client logs, screenshots/traces if present

Search terms:

```bash
rg -n "ERROR|WARN|FAIL|exception|panic|timeout|refused|401|403|404|409|429|did:|xrpc|OAuth|DPoP|firehose|cursor" <diagnostics-dir>
```

Keep a chain of evidence: report step → service response/log line → code path.

### 5. Check topology and health

For local-network failures, verify the expected topology before debugging application logic:

```bash
deno run -A scripts/manage_local_network.ts --collect-diagnostics --run-id <run-id>
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' --filter name=garazyk-e2e
```

Common topology mistakes:

- scenario requires PDS2 but run did not include `--pds2`
- binary mode uses old `build/bin` artifacts
- stale Docker volumes or previous run data caused account/record conflicts
- service URLs in metadata do not match scenario expectations
- health checks passed before AppView/Relay had consumed enough data

### 6. Read the scenario source

Read the failing scenario after the report summary. Locate the failed `timedCall` and note:

- preconditions created by earlier steps
- tokens and DIDs used
- whether the step expects failure
- whether it relies on eventual consistency or sleeps/polls
- artifacts available for debugging
- whether it uses raw XRPC or typed client wrappers

Then inspect only the implementation files needed for the boundary you identified.

### 7. Form a failure theory

Return a concise triage note with:

1. **Failure** — scenario, step, exact error/status.
2. **Evidence** — report fields and 1-3 log/health lines.
3. **Boundary** — service/component likely responsible.
4. **Theory** — one likely root cause, not a list of guesses.
5. **Next verification** — one command or one code inspection step.
6. **Likely fix** — if enough evidence exists; otherwise state what is still unknown.

Prefer this shape:

```md
## Triage

- Scenario: `56_federation_relay_propagation`
- First failing step: `Wait for relay propagation`
- Error: `...`
- Boundary: Relay → AppView ingest

Evidence:
- `reports/56_*.json`: ...
- `diagnostics/docker/logs/relay.log`: ...
- `diagnostics/http/appview-health.txt`: ...

Theory:
...

Next verification:
```bash
...
```
```

## Scenario families and likely root causes

### Federation / migration

Scenarios: `05`, `12`, `35`, `42`, `49`, `50`, `56`.

Check:

- Was PDS2 started? (`--pds2` or metadata)
- Are PDS1/PDS2 service endpoints advertised correctly in PLC?
- Can each service resolve the other's DID through PLC?
- Did relay crawl the right host?
- Is AppView ingest caught up?

Useful probes:

```bash
rg -n "requestCrawl|crawl|resolve|did:plc|repo|commit|firehose" <diagnostics-dir>
```

### OAuth / sessions / browser flows

Scenarios: `08`, `11`, `13`, `23`, `43`, `54`, `62`.

Check:

- client metadata and redirect URI
- auth server metadata
- DPoP nonce/verification
- token refresh/revocation state
- local HTTP/HTTPS assumptions
- browser trace or UI logs

### AppView / feed / search / notifications

Scenarios: `02`, `03`, `15`, `16`, `17`, `20`, `21`, `22`, `26`, `38`, `39`, `40`, `61`.

Check:

- write succeeded at PDS before read from AppView
- relay delivered event
- AppView ingest/backfill workers running
- query endpoint registered and schema-compatible
- timing/polling around eventual consistency

### Firehose / relay / load

Scenarios: `09`, `25`, `27`, `31`, `48`, `63`, `65`.

Check:

- cursor persistence
- WebSocket close codes
- backpressure warnings
- subscriber count and dispatch lag
- sequencer database state

### Blob / video / media

Scenarios: `07`, `36`, `46`, `51`, `67`.

Check:

- blob upload response and CID
- MIME validation
- disk paths/volume mounts
- video worker availability
- FFmpeg/AVFoundation backend selection
- CDN/playback URL assumptions

### Security / negative paths

Scenarios: `04`, `52`, `53`, `54`, `55`, `58`, `64`, `66`.

Check:

- expected-failure steps are marked correctly
- error status matches lexicon expectations
- rate limiter state
- auth middleware ordering
- deletion/takedown enforcement in read paths

## Re-run strategy

Use the smallest rerun that can confirm the theory:

```bash
./scripts/run_scenarios.ts --no-setup NN --verbose
./scripts/run_scenarios.ts --setup --teardown NN --verbose
./scripts/run_scenarios.ts --pds2 NN --verbose
./scripts/run_scenarios.ts --binary NN --verbose
```

If the failure appears environment-dependent, keep the stack running and collect diagnostics before teardown:

```bash
./scripts/run_scenarios.ts --setup-only --keep-running --run-id local-debug
deno run -A scripts/manage_local_network.ts --collect-diagnostics --run-id local-debug
```

## Fix guidance

- If the scenario is wrong, update the scenario and add comments only for non-obvious timing or topology assumptions.
- If the service is wrong, add or update XCTest/unit coverage near the service plus a scenario assertion if the behavior is cross-service.
- If the issue is eventual consistency, prefer polling with a bounded timeout over fixed sleeps.
- If the issue is topology, improve setup validation so the next failure is explicit.
- If the issue is missing diagnostics, add an artifact or health capture to the runner rather than relying on manual log spelunking.

## Related skills

- Use `atproto-scenario-testing` for running scenarios and understanding the scenario framework.
- Use `adding-scenario` when creating or extending scenario coverage.
- Use `testing-atproto-federation` for multi-PDS federation-specific investigations.
- Use `garazyk-testing` when turning a scenario failure into XCTest coverage.
- Use `garazyk-database` for SQLite/WAL/schema issues surfaced by scenarios.
