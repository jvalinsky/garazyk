---
phase: 4
title: Federation, backpressure, and account lifecycle correctness
status: blocked
agent: claude
depends_on: []
---

# Phase 4: Federation, backpressure, and account lifecycle correctness

## Mission

Close workstream 01 S5: deterministic firehose backpressure, adversarial
data through the real Objective-C ingress boundary, account lifecycle
semantics verified against current specs, and the gated test classes folded
into CI so they are measured instead of silently skipped.

## Read first

- `docs/plans/workstreams/01-security-and-protocol-correctness.md` (S5)
- Specs: https://atproto.com/specs/account,
  https://atproto.com/specs/event-stream, https://atproto.com/specs/sync
- Scenario topology configs under `scripts/scenarios/`

## Scope

1. **Deterministic backpressure**: test-only low pending-send/byte limits in
   the scenario topology so `ConsumerTooSlow` fires independent of OS TCP
   buffering. Production defaults unchanged.
2. **Adversarial ingress**: malformed and oversized payloads through live
   PDS/Relay/AppView boundaries (not just Deno parsers), asserting service
   health afterward. Scenarios 64-66 are prior art for shapes.
3. **Account lifecycle**: downstream services stop redistributing inactive
   accounts; `active` vs `status` semantics; monotonic event sequences with
   gap-free cursor resume; suspension/takedown at write and read boundaries.
4. **Complete (2026-07-17): Gated coverage into CI**. All 11 previously
   failing gated classes are repaired (root causes and fixes recorded in
   workstream 01 S5); a full `AllTests --gated=run` pass is green (3454
   tests, 0 failures). `add_test` in `CMakeLists.txt` now runs
   `AllTests --gated=run` (verified via a fresh `cmake` reconfigure +
   `ctest -R '^AllTests$'`), and `scripts/test/run-tests.sh` /
   `run-asan-tests.sh` both pass `--gated=run` by default again.

Out of scope: Relay assembly (phase 7), incremental sync (phase 7).

## Constraints

- New XCTest suites need cmake reconfigure + registration in `test_main.m`
  or zero tests run (repo-known pitfall).
- Bound AllTests builds at `-j4`; unbounded `--parallel` has crashed this
  16 GB machine.
- Full and `--gated=run` AllTests runs transiently need several GB of free
  disk (SQLite temp/WAL); at low headroom they flake with SQLITE_FULL and
  cascading setup failures. Check `df -h /` before trusting a full-run
  failure. Targeted `-f 'ClassName*'` runs are cheap and reliable.
- `scripts/test/run-tests.sh` requires ripgrep (`brew install ripgrep`);
  its design-system pre-check fails fast without it.

## Acceptance gate

- Backpressure scenario green in structured runs, repeatably.
- Lifecycle tests pass at both boundaries with current spec citations.
- CI runs the previously gated classes; counts recorded.
- Global gates pass.

## Blocked on

Scope item 4 (gated CI) is complete (`9bdf54195`, 2026-07-17). The
remaining three items — deterministic backpressure (1), adversarial
ingress (2), and account lifecycle (3) — all require a Docker-backed
topology with live PDS, Relay, and AppView services:

1. **Start Docker** on this machine (or a remote host with `DOCKER_HOST`).
2. **Build the PDS Docker image** from the current source tree.
3. **Stand up the default scenario topology** (`scripts/scenarios/` compose
   config). At minimum: PDS1, a Relay/AppView pair.
4. **Confirm health** by hitting `/xrpc/_health` on each service.

The backpressure scenarios need tunable `maxPendingSendBytes` /
`maxPendingSendCount` on the firehose handler; adversarial ingress sends
malformed data through the real Objective-C boundary (not Deno parsers);
account lifecycle tests verify downstream propagation of suspension,
takedown, and deletion across service boundaries.

This shares the same Docker prerequisite as phase 2's three-PDS topology.

## On completion

Update workstream 01 S5, mega-plan Phase 2 items 4-5; set
`status: complete` here. Phase 7 unblocks.
