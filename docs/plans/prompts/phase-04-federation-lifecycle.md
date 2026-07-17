---
phase: 4
title: Federation, backpressure, and account lifecycle correctness
status: pending
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
4. **Gated coverage into CI**: repair the gated classes, then enable them.
   The gate mechanism is now the test binary's `--gated=run` flag (29
   classes; the old `PDS_RUN_INTEGRATION_TESTS`/`PDS_RUN_SOCKET_TESTS` env
   vars are gone). A measured baseline exists (2026-07-16, workstream 01 S5
   has the per-class table): 76 assertion failures across 11 gated classes,
   each reproducible in isolation — suite rot, not interference. A premature
   enablement (`54869a1c6`) was reverted (`8174747ec`); once the classes are
   green, flip `add_test` in `CMakeLists.txt` to `AllTests --gated=run` and
   restore the flag in `scripts/test/run-tests.sh` / `run-asan-tests.sh`
   (comments mark all three spots). Suggested start:
   `ATProtoMediaServiceRuntimeTests` — all 7 failures share one root cause
   ("Duplicate XRPC handler registration for app.bsky.video.getJobStatus").
   `E2EDockerTests` self-skips without a reachable docker stack; the other
   failures need no external services to reproduce.

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

## On completion

Update workstream 01 S5, mega-plan Phase 2 items 4-5; set
`status: complete` here. Phase 7 unblocks.
