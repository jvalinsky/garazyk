# ADR 0008: AppView Durable Ingest/Index Queue

## Status

Accepted — 2026-07-22

## Context

`AppViewIngestEngine` currently parses a commit CAR, decodes records, writes
records and blocks, advances per-repo state, and only then notifies indexers.
Those writes are synchronous on the relay-event path. `AppViewDatabase` does
already retain an idempotent raw event log and durable relay cursor, but it
does not represent a separately acknowledged indexing queue. Consequently a
slow materializer or database operation limits firehose consumption, and an
operator cannot distinguish “durably received” from “fully indexed.”

The queue must preserve AT Protocol cursor ordering, be safe to replay after a
crash, and put a finite bound on disk growth. It must not acknowledge an event
to the relay before the raw envelope and its cursor are durable.

## Proposed decision

Introduce a versioned AppView database table, `appview_pending_index_events`,
as the only handoff between relay ingestion and materialization. Do not change
XRPC read semantics in the first rollout.

| Plane | Responsibility | Acknowledgement point |
| --- | --- | --- |
| Ingest | Validate envelope framing, append raw event + relay cursor + queue row in one transaction | Transaction commits |
| Index worker | Decode CAR, apply record/block/index mutations, mark queue row indexed in the same transaction | Indexed transaction commits |
| Queries | Continue to read materialized tables | May lag the durable ingest cursor |

The queue row contains: `relay_url`, `seq`, event type, DID, revision, CID,
raw envelope, `received_at`, attempts, lease owner/until, and terminal error.
`UNIQUE(relay_url, seq)` makes enqueue idempotent. The worker claims rows in
ascending `(relay_url, seq)` order with a lease, and retries a row only after
the lease expires. A poison event is retained with its error and exposed to
operators; it never silently advances the indexed cursor.

### Invariants

1. A durable relay cursor implies a queue row or an already-indexed record for
   that `(relay_url, seq)`.
2. An index mutation and the queue row's indexed acknowledgement commit
   together.
3. A restart can replay every non-indexed row without changing the final
   materialized state.
4. Indexed cursor is at most durable cursor; lag is observable per relay.
5. At the high-water mark ingestion pauses before accepting more relay events;
   it resumes only below a lower watermark to avoid oscillation.

### Capacity and operations

Approved defaults:

- high watermark: 100,000 events or 2 GiB of raw envelopes;
- low watermark: 75% of the selected high watermark;
- worker batch: 100 rows;
- lease: 60 seconds;
- retry limit: 10 before dead-lettering and pausing that relay.

Metrics: queue depth and bytes, oldest queued age, durable/indexed cursor,
lease count, retries, dead letters, and relay pause duration. Alert on any
dead letter, queue age above five minutes, or sustained high-water pause.

### Rollout and rollback

1. Add the table and migration with the worker disabled; observe queue metrics.
2. Shadow-enqueue while retaining the current inline materialization, verifying
   cursor and record parity.
3. Enable worker materialization behind an operator flag for one relay.
4. Enable pause/resume backpressure after recovery and replay scenarios pass.

Rollback disables the worker and resumes inline materialization. Queue rows
are retained for forensic replay; they are not dropped automatically.

## Alternatives considered

- **Keep inline indexing.** Lowest implementation cost, but no explicit lag or
  backpressure boundary and an indexer outage stops ingest.
- **In-memory queue.** Loses accepted events on crash and cannot prove cursor
  recovery.
- **External broker.** Adds an operational dependency and split-brain cursor
  failure modes before the single-node SQLite boundary is exhausted.

## Consequences

This creates bounded eventual consistency for AppView queries and requires new
operator dashboards/alerts. In return, ingestion is independently durable,
recoverable, observable, and protected from slow downstream indexers.

The operator approved the eventual-consistency contract, capacity defaults,
dead-letter policy, and production budget on 2026-07-22.
