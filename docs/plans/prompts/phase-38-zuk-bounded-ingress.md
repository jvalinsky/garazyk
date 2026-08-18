---
phase: 38
title: Zuk bounded ingress and ordered processing
status: in-progress
agent: worker
depends_on: [37]
last_updated: 2026-08-13
---

# Phase 38: Zuk bounded ingress and ordered processing

## Mission

Remove every unbounded asynchronous handoff between upstream WebSocket receipt
and accepted relay processing. Enforce global byte/count budgets, preserve
per-repository order, and propagate high-watermark pressure back to upstream
socket reads.

## Read first

- [review remediation](../workstreams/17-zuk-relay-resource-bounds/phase-38-review-remediation.md),
  the 2026-08-17 findings against the in-flight implementation and the ordered
  slices that close them
- [ADR 0039](../../adr/0039-firehose-ingress-admission-seam.md) (proposed),
  where ingress admission runs relative to firehose delivery
- [`workstream 17`](../workstreams/17-zuk-relay-resource-bounds.md), target
  architecture, resource envelope, and Phase 38
- [incident evidence](../workstreams/17-zuk-relay-resource-bounds/incident-evidence.md)
- `Garazyk/Sources/Sync/Relay/RelayClient.{h,m}`
- `Garazyk/Sources/Sync/Relay/RelayUpstreamManager.{h,m}`
- `Garazyk/Sources/Sync/Relay/RelayDownstreamHandler.{h,m}`
- `Garazyk/Sources/Sync/Relay/RelayMetrics.{h,m}`
- `Garazyk/Sources/AppView/Server/Ingest/AppViewIngestEngine.m` watermark and
  durable-queue behavior
- Objective-C concurrency conventions in `CLAUDE.md`

## Required inventory

Before design, draw the actual ownership sequence from network buffer through
decoded event, validation, repo-state update, replay retention, and broadcast.
For each transition record:

- dispatch queue/thread;
- owner of the encoded and decoded payload;
- cancellation behavior;
- current cursor advancement point;
- whether count and bytes are observable;
- whether the producer can pause.

The implementation plan in the commit message must name the old unbounded
edges it removes. Do not add a bounded queue beside an old unbounded path.

## Slice 1 — Admission primitive

Create one relay-ingress admission primitive with:

- validated positive count and byte limits;
- high/low watermarks;
- atomic or queue-confined accounting;
- an ownership token released exactly once on success, rejection,
  cancellation, disconnect, decode failure, and shutdown;
- current/peak event count and bytes;
- oldest accepted age;
- transition callbacks that cannot re-enter while internal state is locked.

Account encoded bytes before dispatch. If decoded objects materially exceed
wire size in a benchmark, add a documented conservative multiplier or measured
decoded-cost estimate; do not pretend encoded length is the complete heap cost.

## Slice 2 — Remove the two-hop unbounded queue

Replace the main-queue hop and serial `handlerQueue` accumulation with a
bounded processing executor. Preferred design: four shards selected by stable
hash of repository DID, each serial internally. An equivalent design is
acceptable only if tests prove:

- same-DID order;
- cross-DID concurrency;
- bounded global and per-shard backlog;
- no task can bypass admission;
- shutdown drains or cancels tokens deterministically.

Do not use one new unbounded GCD queue per upstream or DID.

## Slice 3 — Socket backpressure

At the high watermark, pause reads from contributing `RelayClient` instances.
At the low watermark, resume only clients that are still connected and owned by
the same manager generation. Coalesce pause/resume transitions so a burst does
not thrash the transport.

Define fairness: a single noisy upstream cannot permanently starve all others.
At minimum, track accepted bytes per upstream and prefer pausing the largest
contributors. If the initial implementation pauses all clients, document the
tradeoff and add a Phase 42 measurement proving it does not cause synchronized
reconnects.

## Slice 4 — Cursor acknowledgement

Separate:

```text
last received sequence
last admitted sequence
last durably processed sequence
```

Reconnect must use the last sequence whose chosen processing contract is
complete, not the last frame merely decoded. Phase 39 will make relay output
durable; this phase must establish the input acknowledgement seam without
claiming output persistence.

## Slice 5 — Metrics and configuration

Expose and test:

- configured limits and low/high watermarks;
- current/peak count and bytes globally and per shard;
- oldest item age;
- pause/resume totals and cumulative duration per upstream;
- admitted/rejected/cancelled totals by reason;
- worker service time and queue delay histograms;
- accounting underflow/double-release invariant failures.

Use one configuration namespace and hardened integer parsing. Invalid
watermark relationships or overflow must fail startup, not silently select an
unbounded/default value.

## Stress cases

1. Resolver blocks all workers for longer than the high-watermark interval.
2. One upstream floods maximum-sized legal events while others send small
   events.
3. Decode failure after admission.
4. Disconnect while paused.
5. Shutdown with every shard occupied and queued.
6. Reconnect generation changes before a scheduled resume callback.
7. Same DID alternates across two upstreams.

Every case asserts queue/count/byte bounds and ends at zero outstanding
accounting after cleanup.

## Acceptance gate

```bash
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests -f 'RelayClientTests' --gated=run
./build/tests/AllTests -f 'RelayUpstreamManagerTests' --gated=run
./build/tests/AllTests -f 'RelayDownstreamHandlerTests' --gated=run
./build/tests/AllTests -f 'RelayMetricsTests' --gated=run
./build/tests/AllTests --gated=run
./scripts/dev/check_module_boundaries.sh .
./scripts/check_module_boundaries.sh build
./scripts/check-recursive-setters.sh
./scripts/check_no_host_process_exit.sh
# Run the Linux/GNUstep relay gate.
```

Also run a bounded 60-minute synthetic load with a stalled resolver and retain
RSS, queue bytes, pause state, throughput, and cleanup measurements. This is
lab evidence, not the production canary.

## Stop conditions

Stop if per-repository order cannot be stated precisely, cursor advancement
still occurs on decode, any asynchronous path bypasses admission, or the design
requires disabling validation to remain within memory bounds.

## On completion

Update the workstream, mega-plan, and phase state with commit/test/load
evidence. Record the action/outcome under deciduous goal 416. Keep the bounded
path behind one release-scoped fallback flag; document the removal condition.

Rollback selects exactly one ingress implementation at startup. Never run old
and new paths concurrently for the same upstream.
