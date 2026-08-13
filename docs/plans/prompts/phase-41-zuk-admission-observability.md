---
phase: 41
title: Zuk crawl admission observability and service guardrails
status: pending
agent: worker
depends_on: [38]
last_updated: 2026-08-13
---

# Phase 41: Zuk crawl admission, observability, and service guardrails

## Mission

Bound public upstream-fleet growth, replace misleading Relay health counters
with authoritative state, expose every resource budget to operators, and add
validated NixOS/systemd guardrails suitable for the 8 GiB `bingus` host.

## Read first

- [`workstream 17`](../workstreams/17-zuk-relay-resource-bounds.md), resource
  envelope, operational criteria, and Phase 41
- [incident evidence](../workstreams/17-zuk-relay-resource-bounds/incident-evidence.md)
- `Garazyk/Sources/Network/RelayXrpcRoutePack.m`
- `RelayUpstreamManager`, `RelayMetrics`, `GZRelayAdminSnapshot`, and
  `GZRelayAdminUIPack`
- [Relay Admin UI brief](../workstreams/service-admin-uis/relay.md)
- `nixos/modules/zuk.nix` and `scripts/test/nixos_zuk_module_smoke.sh`
- Garazyk deployment/operations guides and existing credential wiring
- pinned Indigo relay flags for comparison, not default copying

## Slice 1 — Crawl admission policy

Apply checks before allocating a persistent client, queue, or socket:

1. validate and canonicalize the host using the existing SSRF/reachability
   policy;
2. deduplicate aliases/canonical endpoints;
3. enforce per-client request rate and concurrent-request limits;
4. enforce a rolling global new-host/day limit;
5. enforce maximum configured and connected dynamic upstreams;
6. enforce the configured accounts-per-upstream policy;
7. return a typed XRPC error and increment one reason metric.

Add a startup flag that disables public `requestCrawl` while leaving explicit
operator-configured upstreams available. Define whether rejected hosts may be
retried after the rolling window; do not persist client identifiers or raw
request metadata beyond the rate limiter's bounded need.

## Slice 2 — Authoritative connection state

Derive current gauges from synchronized sets owned by
`RelayUpstreamManager`:

- configured explicit, dynamic, connecting, connected, paused, backing off,
  and terminal counts;
- per-upstream generation, last event, last acknowledged cursor, pause state,
  retry count, and bounded events-by-kind;
- cumulative connection attempts/successes/disconnects as separate counters.

Remove health dependence on increment/decrement counters. Add an invariant
metric/log if the lifecycle totals and authoritative set cannot be reconciled,
but do not overwrite one with the other silently.

## Slice 3 — Resource and persistence observability

Extend Relay metrics/Admin snapshot with:

- ingress count/bytes/peak/oldest age and watermark state;
- validation queue delay/service time, active shards, resolver/cache metrics;
- replay oldest/newest cursor, segment count, disk bytes, GC and append/sync
  latency/failures;
- subscriber count, queued frames/bytes, replay/live mode, and drop reasons;
- crawl admission/rejection by reason;
- process or cgroup current/peak memory and swap when available.

All snapshots must be bounded, synchronized, and cheap enough for existing
polling. Never enumerate unbounded repository lists to render health.

## Slice 4 — Health policy

Define `healthy`, `degraded`, and `unhealthy` from observable conditions:

- persistence unavailable or unsafe sequence state: unhealthy;
- sustained ingress above high watermark, all workers stalled, or repeated
  output drops: degraded, escalating to unhealthy after a configured duration;
- zero upstreams: reflect configuration intent (healthy for intentionally empty
  test mode, degraded/unhealthy for a required production fleet);
- metric callback divergence alone: degraded diagnostic, not a false upstream
  count.

Tests use a fake monotonic clock. Avoid wall-clock sleeps.

## Slice 5 — Configuration and NixOS options

Expose validated options for every workstream budget, persistence directory,
replay window/disk cap, validation mode, crawl policy, and log level. Secret
values stay in systemd credentials or the existing secret source.

After internal bounds pass stress tests, add conservative service properties
for the 8 GiB profile:

```text
MemoryHigh = 1.5–2.0 GiB starting range
MemoryMax = 2.5 GiB starting ceiling
MemorySwapMax = 512 MiB after canary confirmation
TasksMax and LimitNOFILE derived from the upstream/subscriber caps
```

The final values must come from Phase 42 preflight evidence. Nix defaults must
not unexpectedly constrain larger existing installations; provide an explicit
small-host profile or nullable options where appropriate.

## Slice 6 — Operator runbook

Document:

- symptoms and metric interpretation;
- safe commands for status, logs, cgroup memory, sockets, disk, and health;
- emergency crawl restriction/log containment;
- backup of durable replay metadata;
- configuration validation and dry run;
- incremental deploy order;
- 30-minute/six-hour/24-hour verification;
- rollback binary/config and conditions;
- why deleting replay files or killing an unidentified loopback client is not
  an acceptable first response.

## Acceptance gate

```bash
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests -f 'RelayXrpcRoutePackTests' --gated=run
./build/tests/AllTests -f 'RelayUpstreamManagerTests' --gated=run
./build/tests/AllTests -f 'RelayMetricsTests' --gated=run
./build/tests/AllTests -f 'RelayAdminUIPackTests' --gated=run
./build/tests/AllTests -f 'ZukCommandTests' --gated=run
./scripts/test/nixos_zuk_module_smoke.sh
./scripts/test/relay_admin_loopback_smoke.ts
./scripts/admin_ui_browser_smoke_test.ts
./scripts/admin_ui_visual_smoke_test.ts
./scripts/dev/check_module_boundaries.sh .
./scripts/check_module_boundaries.sh build
./scripts/check_namespace.sh build
deno run -A scripts/docs/repo_docs.ts validate --internal-strict --orphans
# Run the Linux/GNUstep zuk binary gate.
```

Quota tests must prove rejection occurs before client/socket allocation.
Snapshot tests must prove collection sizes and string fields are capped.

## Stop conditions

Stop if a quota relies only on attacker-controlled host spelling, Admin polling
allocates proportional to all repositories/events, service limits precede
internal queue bounds, or secrets/user data enter metrics and logs.

## On completion

Update workstreams 11 and 17, the Relay brief, NixOS documentation, mega-plan,
and phase state in the same change. Record the action/outcome under deciduous
goal 416.

Rollback order: remove `MemoryMax` first if it causes a false-positive restart
loop; retain internal bounds, authoritative metrics, and crawl disablement.
