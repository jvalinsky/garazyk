---
phase: 39
title: Zuk durable segmented replay and sequence recovery
status: pending
agent: worker
depends_on: [38]
last_updated: 2026-08-13
---

# Phase 39: Zuk durable segmented replay and sequence recovery

## Mission

Move Relay replay history and output sequence allocation from a
traffic-history-sized Objective-C array to a crash-recoverable, byte-bounded
segmented disk log with streaming replay and bounded live crossover.

## Read first

- [`workstream 17`](../workstreams/17-zuk-relay-resource-bounds.md), Phase 39
  and persistence success criteria
- [incident evidence](../workstreams/17-zuk-relay-resource-bounds/incident-evidence.md)
- `Garazyk/Sources/Sync/Relay/RelayEventBuffer.{h,m}`
- `Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m`
- Relay output sequence allocation and Zuk startup composition
- PDS migration and durable-queue patterns, for failure semantics only
- pinned Indigo disk persistence implementation from the evidence file
- ATProto event-stream persistence and sequence requirements
- `.agents/skills/garazyk-database/SKILL.md` and
  `.agents/skills/sqlite-sql-best-practices/SKILL.md` if SQLite remains a
  candidate after the format decision

## Slice 1 — ADR and format contract

Before production code, accept an ADR covering:

- why segmented append files are selected over in-memory retention and any
  evaluated SQLite BLOB design;
- directory layout and ownership;
- file/header magic and version;
- per-record length, output sequence, event kind, checksum, and payload;
- maximum record/segment sizes and integer-overflow checks;
- rotation rule by bytes and event count;
- durable sequence metadata and fsync policy;
- startup scan/index rebuild;
- torn final record and corrupt closed-segment policy;
- time and disk-byte retention;
- active-reader/GC coordination;
- downgrade and format-version behavior.

The event payload remains the existing encoded stream message. Do not invent a
new public wire format.

## Slice 2 — Append-before-publish

Allocate an output sequence exactly once, append the complete record, complete
the configured durability boundary, then make the event visible to live
subscribers. A persistence failure must not broadcast an event under a sequence
that could be reused after restart.

Record separate metrics for append latency, sync latency, bytes, rotation,
failure, and last durable sequence. Do not log payloads.

## Slice 3 — Recovery and sequence metadata

On startup:

1. validate configured directory and permissions;
2. read durable sequence metadata;
3. scan only the active/tail segment as required;
4. truncate an incomplete final record safely;
5. reject or quarantine a corrupt closed segment according to the ADR;
6. reconstruct oldest/newest replayable sequence and byte totals;
7. choose the next sequence without reuse.

Tests must inject a crash at each record-write boundary and between record
durability and metadata update.

## Slice 4 — Streaming replay and crossover

Replay readers yield one event at a time from segments. They must obey the
Phase 37 subscriber admission result and stop reading on cancellation. Use a
bounded crossover buffer while disk playback approaches the live frontier.

Prove exactly-once handoff at the relay output-sequence level for events
published during replay. If public semantics permit retry duplicates, state
that separately; internal handoff must not create an accidental gap or
duplicate.

## Slice 5 — Retention and garbage collection

- Enforce both replay-window time and total disk bytes.
- Delete only closed segments that no active reader needs.
- Run GC at a bounded interval and on startup after recovery.
- Surface oldest available cursor so outdated-cursor responses are truthful.
- Treat disk full, read-only filesystem, and permission loss as health failures.
- Never fall back to unbounded RAM when persistence is unavailable.

## Slice 6 — Hot cache and migration

Replace `RelayEventBuffer` with a hot cache bounded by both count and bytes.
Use a deque/ring structure without `removeObjectAtIndex:0` shifts. The cache is
an optimization; correctness must hold with it disabled or empty.

Existing deployments have no durable relay replay state to migrate. On first
start, create an empty log at a non-reused sequence chosen by the ADR/startup
contract. Preserve the directory on rollback.

## Required failure tests

- zero-length/truncated header and record;
- oversized length field and integer overflow;
- checksum mismatch in active and closed segments;
- crash before/after append, sync, rotation, and metadata update;
- disk full during record and rotation;
- concurrent append, replay, cancellation, and GC;
- retention pressure while a reader holds the oldest eligible segment;
- restart with hot cache empty;
- unknown future format version;
- replay request older than retained data.

## Acceptance gate

```bash
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests -f 'RelayEventLogTests' --gated=run
./build/tests/AllTests -f 'SubscribeReposHandlerTests' --gated=run
./build/tests/AllTests -f 'RelayEventBufferTests' --gated=run
./build/tests/AllTests --gated=run
./scripts/dev/check_module_boundaries.sh .
./scripts/check_module_boundaries.sh build
./scripts/check_namespace.sh build
./scripts/check-recursive-setters.sh
# Run Linux/GNUstep restart and disk-full coverage.
```

Run a replay data set at least four times larger than the configured hot-cache
budget and record peak RSS, replay throughput, disk bytes, and crossover
sequence assertions.

## Stop conditions

Stop if the design publishes before durable sequence assignment, loads an
entire requested window into memory, deletes a segment visible to a reader, or
silently continues from RAM after disk persistence failure.

## On completion

Land the ADR, code, tests, configuration, and plan-state update together.
Record the format version, commit, and evidence in workstream 17 and under
deciduous goal 416.

Rollback disables the new reader/writer and restores the prior binary without
deleting segment files. Restrict downstream replay promises until forward
recovery; do not manufacture cursors from discarded data.
