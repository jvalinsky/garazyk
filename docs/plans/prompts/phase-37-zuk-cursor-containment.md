---
phase: 37
title: Zuk cursor correctness and replay-loop containment
status: pending
agent: worker
depends_on: []
last_updated: 2026-08-13
---

# Phase 37: Zuk cursor correctness and replay-loop containment

## Mission

End the production replay/reconnect loop with the smallest protocol-correct
change: omitted cursor means live-only, replay stops when its subscriber can no
longer accept output, and pressure diagnostics are bounded. Do not redesign
relay ingress or persistence in this phase.

This is a P0 incident phase. It is independent of phases 35–36 but must run in
a separate clean worktree. Workstream 17 is authoritative.

## Read first

- [`workstream 17`](../workstreams/17-zuk-relay-resource-bounds.md), especially
  locked decisions, Phase 37, and success criteria
- [incident evidence](../workstreams/17-zuk-relay-resource-bounds/incident-evidence.md)
- `docs/adr/0012-relay-future-cursor-returns-outdated-cursor.md`
- `Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m`
- outbound WebSocket queue/send implementation and its tests
- `Garazyk/Sources/Sync/Relay/RelayMetrics.{h,m}`
- `Garazyk/Sources/Sync/Relay/RelayEventValidator.m`
- ATProto event-stream specification, especially cursor and persistence rules
- pinned Indigo `eventmgr/event_manager.go` reference from the evidence file

## Preconditions

1. `git status` is clean in the phase worktree.
2. Record the commit, binary identity, active Zuk configuration, and a bounded
   non-sensitive baseline. If `bingus` is unavailable, record that explicitly;
   local implementation can proceed, but production completion cannot.
3. Identify all call sites of `SubscribeReposHandler` and every implementation
   of the connection `sendMessage:` contract before changing its return shape.
4. Preserve current ADR 0012 future-cursor behavior.

## Slice 1 — Cursor behavior matrix

Add characterization tests for:

- no cursor;
- cursor zero;
- cursor inside the retained window;
- cursor equal to the current sequence;
- outdated cursor;
- future cursor under ADR 0012;
- replay-to-live crossover while a new event is published.

Tests must assert event sequences and control frames, not only connection
success. Pin the current defect with a failing omitted-cursor assertion before
changing production behavior.

## Slice 2 — Live-only omitted cursor

Attach a no-cursor subscriber atomically to the live broadcaster and return
without reading retained history. Ensure the handoff cannot miss an event
between reading the current sequence and subscriber registration. Do not map
the absent value to `0`.

Keep explicit cursor zero distinct: it requests the server's available replay
window according to the event-stream contract.

## Slice 3 — Producer-visible replay cancellation

Make replay observe one of these explicit outcomes for each send:

```text
accepted
temporarily backpressured (only if the transport can drain without another enqueue)
closed/cancelled
hard-limit rejected
```

Stop reading/encoding replay events immediately on closed, cancelled, or hard
rejection. Cancellation must propagate when the socket closes, the subscriber
is removed, shutdown starts, or the output limit fires. Tests must assert that
the replay enumerator does not visit the remaining retained events.

Do not sleep or poll the socket from the replay producer. Do not increase the
existing output limits as the fix.

## Slice 4 — Log and metric containment

- Emit one backpressure-entered record and one recovered/closed record per
  subscriber state transition.
- Aggregate repeated pressure counts in metrics rather than logging every
  rejected frame.
- Categorize signature failures at the granularity currently available and
  sample/rate-limit identical diagnostics. Phase 40 adds the full reason model.
- Preserve totals needed to compare the incident baseline.

No raw event body, authorization value, key material, or complete DID document
may appear in a log.

## Slice 5 — Deterministic regression scenario

Add a Hamownia scenario that:

1. seeds more events than a tiny test replay window;
2. opens a downstream subscription without a cursor;
3. publishes a sentinel event after attachment;
4. proves only the sentinel/newer events arrive;
5. reconnects at least 25 times without a cursor;
6. exercises a slow consumer with deliberately tiny output limits;
7. proves the replay enumerator and queue remain bounded and the service stays
   healthy.

Use structured output. Fixed sleeps are not acceptance evidence; poll a named
state or metric with a deadline.

## Slice 6 — Emergency operator profile

Document reversible containment until all phases ship:

- restrict or block public `requestCrawl` at the existing proxy;
- lower log level enough to prevent the journal storm;
- lower replay exposure only through existing validated settings;
- restart only after the client loop is contained or the cursor fix is
  deployed;
- identify the loopback client before changing or stopping it.

Do not introduce systemd `MemoryMax` in this phase; Phase 41 owns cgroup
guardrails after internal bounds exist.

## Acceptance gate

```bash
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests -f 'SubscribeReposHandlerTests' --gated=run
./build/tests/AllTests -f 'FirehoseTests' --gated=run
./build/tests/AllTests -f 'RelayClientTests' --gated=run
./build/tests/AllTests -f 'RelayMetricsTests' --gated=run
deno task check
deno task lint
deno task test
./scripts/dev/check_module_boundaries.sh .
./scripts/check-recursive-setters.sh
./scripts/check_no_host_process_exit.sh
# Run the new structured scenario through `hamownia agent`.
# Run the Linux/GNUstep Sync + zuk binary gate.
```

Record exact test names and scenario run ID in workstream 17. Do not describe
an unrun full gate as passing.

## Stop conditions

Stop and record a blocker if the only proposed solution changes ADR 0012,
requires killing an unidentified production process, weakens slow-consumer
limits, or makes no-cursor delivery depend on reading the retained buffer.

## On completion

- Update workstream 17 Phase 37 with commit and dated evidence.
- Update mega-plan item 17 and this frontmatter in the same change as code.
- Record the action/outcome under deciduous goal 416.
- Leave Phase 38 pending unless Phase 37 rollback and production containment
  are documented.

Rollback reverts the source/config slice together. Until a corrected binary is
restored, block the looping downstream at the proxy rather than increasing
queues.
