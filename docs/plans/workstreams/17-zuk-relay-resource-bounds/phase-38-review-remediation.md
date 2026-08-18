---
title: Phase 38 Bounded Ingress — Review Remediation
status: remediation
last_verified: 2026-08-17
---

# Phase 38 bounded ingress — review remediation

Findings from a read-only review on 2026-08-17 of the uncommitted Phase 38
work on `codex/zuk-resource-plan` (16 modified files, 7 new files, ~600 added
lines), measured against
[phase 38](../../prompts/phase-38-zuk-bounded-ingress.md) and the locked
findings in [workstream 17](../17-zuk-relay-resource-bounds.md).

This file is the remediation backlog for that review. It does not restate the
phase mission and it does not replace the phase prompt's acceptance gate.

## What the review found

The admission primitive, shard-by-DID executor, cursor seam, configuration
object, and their tests exist and are largely sound. Same-DID ordering holds,
byte accounting uses the real wire frame length, and the legacy and bounded
paths are correctly mutually exclusive at startup.

The central defect is placement, not construction: **admission sits downstream
of two unbounded asynchronous hops**, so the bound it enforces is not the bound
that matters.

```text
socket read -> handleMessage: -> parse
  -> dispatch_async(main queue)      # unbounded #1, pre-existing, untouched
  -> RelayClient delegate
  -> dispatch_async(callbackQueue)   # unbounded #2, added by this change
  -> RelayUpstreamManager -> admission
  -> shard queue                     # bounded
```

The main-queue hop the phase prompt asks to remove lives in
`ATProtoFirehose.sendEventToSubscriptions:`, not in `RelayClient`. The change
moved the *second* hop off the main queue and left the first in place, which
[workstream 17 locked finding 4](../17-zuk-relay-resource-bounds.md) already
rules out: a bounded queue that moves overflow to an unbounded upstream GCD
queue is not a fix.

`pauseReading` does reach the transport
(`RelayClient` -> `ATProtoFirehose.suspendReading` -> connection), so the
backpressure mechanism is real. It is simply signalled two unbounded queues
downstream of where memory accumulates.

## Findings

Severity: **B** blocks the phase acceptance gate, **C** correctness defect,
**S** unmet slice requirement.

| ID | Sev | Finding | Site |
| --- | --- | --- | --- |
| F1 | C | `lastReceivedSequence` is never reset on connect, so every frame replayed after a reconnect is dropped as non-monotonic. Defeats the Slice 4 cursor seam: events admitted but unprocessed at disconnect are lost permanently. | `RelayClient.m` `noteIncomingSequence:` |
| F2 | B | Unbounded handoff moved rather than removed; a new per-client `callbackQueue` was added behind the untouched main-queue hop. | `Firehose.m`, `RelayClient.m` |
| F3 | B | Byte high watermark can never fire. Admission rejects at `accounted + bytes > max` but marks high at `accounted >= max`; when event size exceeds residual headroom the backlog stalls below the cap, no pause is raised, and events are logged and discarded with no recovery path. | `RelayIngressAdmission.m` |
| F4 | C | Watermark handlers are dispatched to the global *concurrent* queue, so a high->low transition can execute resume-before-pause and strand upstreams paused. | `RelayIngressAdmission.m` |
| F5 | C | `ingressPipelineDidRequestResume:` hits `continue` on a generation mismatch before removing the upstream from `backpressurePausedUpstreams`, so a still-connected client can be permanently stalled. Stress case 6, untested. | `RelayUpstreamManager.m` |
| F6 | C | `upstreamClients` is mutated on `_managerQueue` but read from a shard queue in the ack path; `ingressPipeline` is read and written unsynchronized. | `RelayUpstreamManager.m` |
| F7 | C | `currentSeq` and `lastReceivedSequence` take non-atomic read-modify-write from two threads; the pipeline's three `lastXSequence` properties are written on `_controlQueue` and read from anywhere. | `RelayClient.m`, `RelayIngressPipeline.m` |
| F8 | S | `parsed > UINT64_MAX` is dead for `unsigned long long`, and `errno`/`ERANGE` is unchecked, so `strtoull` saturation silently yields `UINT64_MAX` — the "silently select an unbounded default" Slice 5 forbids. `NSUInteger` casts truncate; input `"0"` reports "overflowed uint64_t". | `RelayIngressConfiguration.m` |
| F9 | S | `shardCount` has no upper bound; only zero is rejected. | `RelayIngressConfiguration.m` |
| F10 | S | `noteUpstreamDisconnected:` is a no-op, so in-flight tokens are never released with `Disconnect`. Stress case 4. | `RelayIngressPipeline.m` |
| F11 | S | Slice 3 fairness unimplemented: `acceptedBytesByUpstream` is accumulated and never read; pause hits every upstream, with no tradeoff note and no Phase 42 hook. | `RelayUpstreamManager.m` |
| F12 | S | Slice 5 gaps: no per-shard counters, no oldest-age metric, no queue-delay histogram. `recordIngressUpstreamPause:` discards the URL, so no per-upstream totals or cumulative durations. `recordIngressReleasedProcessed` is defined and never called. | `RelayMetrics.{h,m}` |
| F13 | S | No decoded-cost benchmark and no multiplier; encoded length is treated as the whole heap cost. | `RelayIngressPipeline.m` |
| F14 | S | `shutdownWithCompletion:` calls `waitForDrainForTesting` (5s spin plus run loop) on the production path and fires completion even on timeout. | `RelayIngressPipeline.m` |
| F15 | S | Stress cases 1, 2, 4, 6 and 7 untested; nothing covers the manager pause/resume path where F5 lives. | `RelayIngressAdmissionTests.m` |

### Latent hazard, not a live defect

`RelayIngressProcessBlock` accepts a completion, implying asynchronous
processing, but the shard queue does not wait for it. Ordering holds today only
because `processUpstreamEvent:` happens to be synchronous. Any future
asynchronous process block breaks same-DID order silently. Add an assertion or
state the synchronous contract in the header.

## The decision that gates the rest

**Where does admission run?** It must execute before the first
`dispatch_async`, synchronously on the socket read path inside
`handleMessage:`. Blocking or rejecting there is what makes the byte bound
real; everything downstream is bookkeeping.

The constraint is that `ATProtoFirehose` is shared with the AppView ingest
path, so its delivery threading cannot change unconditionally. Proposed shape:
an opt-in gate block on `ATProtoFirehose`, consulted synchronously in
`handleMessage:` before dispatch. Zuk installs the admission gate; AppView
leaves it nil and retains today's behavior — the same opt-in pattern already
used for `reconnectUsesProcessedCursor`.

This changes a shared component's threading contract and is therefore recorded
as [ADR 0039](../../../adr/0039-firehose-ingress-admission-seam.md). Settle it
before any code moves in R4.

## Remediation slices

| ID | Slice | Fixes | Size | Depends on |
| --- | --- | --- | --- | --- |
| R1 | Reset `lastReceivedSequence` to `currentSeq` on each connect | F1 | ~5 lines | — |
| R2 | Watermark handlers onto a serial queue | F4 | ~5 lines | — |
| R3 | ADR 0039: firehose ingress admission seam | — | doc | — |
| R4 | Gated delivery in `handleMessage:`; retire `callbackQueue` for events | F2 | large | R3 |
| R5 | High watermark distinct from the hard cap; rejection becomes exceptional | F3 | medium | R4 |
| R6 | Queue-confine `upstreamClients`, `ingressPipeline`, sequence properties | F6, F7 | medium | — |
| R7 | Generation and pause bookkeeping; implement `noteUpstreamDisconnected:` | F5, F10 | medium | R6 |
| R8 | Config hardening: `errno`/`ERANGE`, cast width, shard ceiling | F8, F9 | small | — |
| R9 | Deterministic shutdown drain; retire `waitForDrainForTesting` from production | F14 | small | — |
| R10 | Metrics completion: per-shard, oldest age, queue delay, per-upstream pause | F12 | medium | R5 |
| R11 | Fairness, or a documented pause-all tradeoff plus Phase 42 measurement | F11 | small–large | R7 |
| R12 | Decoded-cost benchmark, then a multiplier or a written justification | F13 | small | — |
| R13 | Stress cases 1, 2, 4, 6, 7 plus manager pause/resume coverage | F15 | large | R7 |

### Ordering notes

**Land R1 and R2 first.** Both are a handful of lines, both are independent of
the architecture decision, and F1 is live data loss on every reconnect.

**R4 is the phase.** Until admission precedes the main-queue hop, the
acceptance gate cannot honestly be claimed: a 60-minute stalled-resolver load
run will show main-queue growth that the ingress metrics do not account for,
because the backlog is not admitted yet.

**R5 falls out of R4.** Once the read path is gated, rejection stops being the
common case. Doing R5 first means designing a drop policy that R4 deletes.

**R11 resolution.** `acceptedBytesByUpstream` was a lifetime-since-connect
cumulative counter — incremented on every admitted event, never read. It was
also the wrong signal for fairness even if it had been read: an upstream that
burst early in a long-lived connection and has been quiet since would show
the highest cumulative total forever, while an upstream currently flooding
the pipe right now (the one actually causing the present high-watermark trip)
could show a low cumulative total if it only recently connected. It has been
removed entirely (property, ivar init, both increment call sites, the
disconnect-cleanup call site).

In its place, `ingressPipelineDidRequestPause:` (`RelayUpstreamManager.m`)
now queries a new `ATProtoRelayIngressPipeline` method,
`-inFlightByteCountByUpstream`, backed by the same admitted-but-not-yet-
released token tracking R7 (F10) already built for
`-noteUpstreamDisconnected:` — summing each in-flight token's `encodedBytes`
per upstream. That is *current* outstanding backlog, not lifetime traffic,
which is the quantity fairness actually needs. Pause selects the single
connected, not-already-paused upstream with the highest in-flight byte count
("top-1") rather than every upstream. Top-1 is deliberately the simplest
defensible policy, not the ceiling of what's possible: it is small, it is
correct in the common case, and it stops the trivial pathology (pausing a
quiet upstream while the actual flooder keeps going). If `inFlightByteCountByUpstream`
is empty or every candidate shows zero in-flight bytes, the handler falls
back to pausing every connected upstream, so a watermark trip is never left
with zero backpressure applied.

Phase 42 hook: if top-1 alone proves insufficient to bring the backlog back
under the low watermark under real load, the next step is a measured (not
guessed) move to proportional/weighted selective pausing — e.g. pausing
enough contributors to cover some percentage of total in-flight bytes, or
weighting by upstream-configured priority.

## Execution plan

Wave boundaries are set by file ownership: two agents must never hold the same
`.m` file. Within a wave, every task is independent and may run in parallel.

| Wave | Task | Model | Owns | Parallel with |
| --- | --- | --- | --- | --- |
| A | R1 | haiku | `RelayClient.m` | A2, A3, A4 |
| A | R2 | haiku | `RelayIngressAdmission.m` | A1, A3, A4 |
| A | R8 | haiku | `RelayIngressConfiguration.m` | A1, A2, A4 |
| A | R3 | sonnet | `docs/adr/0039-*.md` | A1, A2, A3 |
| B | R4 | sonnet | `Firehose.{h,m}`, `RelayClient.m`, AppView subscription path | *(alone)* |
| C | R5 | sonnet | `RelayIngressAdmission.m` | C2 |
| C | R6 + R9 | sonnet | `RelayUpstreamManager.m`, `RelayIngressPipeline.m`, `RelayClient.m` | C1 |
| D | R7 | sonnet | `RelayUpstreamManager.m`, `RelayIngressPipeline.m` | D2 |
| D | R12 | haiku | benchmark harness, docs | D1 |
| E | R10 | haiku | `RelayMetrics.{h,m}` | E2 |
| E | R11 | sonnet | `RelayUpstreamManager.m`, docs | E1 |
| F | R13 | sonnet | `Garazyk/Tests/Sync/*` | *(alone)* |

**Model rationale.** Haiku takes slices whose diff is fully specified in
advance and whose acceptance is "compiles, filtered suite green": a cursor
reset, a queue-type change, integer parsing hardening, metric plumbing that
follows an existing pattern, a benchmark harness. Sonnet takes everything
requiring judgment about threading, blast radius across a shared component, or
a design fork with more than one defensible answer.

**R4 should not run unattended.** It changes a component the AppView depends
on. Review ADR 0039 before dispatching it, and extend the phase acceptance gate
to include the AppView ingest suites, not only the four relay suites the phase
prompt lists.

Per-slice verification is filtered rather than full-suite:

```bash
./build/tests/AllTests --filter 'RelayIngressAdmissionTests|RelayClientTests|RelayUpstreamManagerTests' --gated=run
```

The full `--gated=run` sweep and the 60-minute stalled-resolver load run belong
to the phase acceptance gate, after wave F.
