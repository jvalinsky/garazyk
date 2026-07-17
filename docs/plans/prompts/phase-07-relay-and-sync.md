---
phase: 7
title: Relay product decision and incremental public sync
status: pending
agent: Plan
depends_on: [4]
---

# Phase 7: Relay product decision and incremental public sync

## Mission

Resolve the two scale-shaped Phase 4 items: decide what `kaszlak relay
serve` is (then implement the choice), and make repository export
preparation incremental instead of materializing up to 100k records.

## Read first

- `docs/plans/workstreams/02-core-architecture-and-reliability.md` (A5, A6)
- `docs/plans/workstreams/01-security-and-protocol-correctness.md` (S6 row
  for the Sync 1.1 remainder — check whether spec text has landed)
- https://atproto.com/specs/sync and
  https://atproto.com/specs/event-stream

## Part 1 — Relay decision (Plan agent, then human checkpoint)

Produce a decision brief comparing A5's three options (real Relay with
listener/one retry owner/durable cursor; experimental-marked command;
removal) with cost, operational burden, and protocol obligations for each.
Set `status: blocked` and present the brief — **the choice is the
operator's**. Then implement the chosen option (claude agent):

- Option 1 acceptance: upstream event reaches a downstream subscriber;
  restart resumes from persisted cursor; duplicates tolerated, gaps not;
  exactly one reconnect scheduled.
- Options 2/3: help-text/manifest/config changes plus removal of dead
  promises, with a launcher smoke.

## Part 2 — Incremental public sync (claude agent)

1. Byte-for-byte CAR/STAR fixtures first (golden outputs).
2. Incremental export producer behind a bounded fallback; peak-memory
   tracked in tests.
3. Replace N+1 per-account summary scans with indexed materialized
   metadata only where a measurement justifies it.
4. If the Sync 1.1 remainder (export block ordering, collection subsets)
   has published spec text by now, implement it in this lane; otherwise
   record status in the S6 matrix and move on.

## Acceptance gate

- Decision recorded as an ADR; implementation matches it.
- Export fixtures byte-identical before/after the incremental producer.
- Protocol E2E for Relay/sync green in structured runs; global gates pass.

## On completion

Update workstream 02 A5/A6, mega-plan Phase 4 items 1-2 and 7; set
`status: complete` here.
