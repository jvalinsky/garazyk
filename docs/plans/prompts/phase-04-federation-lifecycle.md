---
phase: 4
title: Federation, backpressure, and account lifecycle correctness
status: in-progress
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

1. **Complete (2026-07-17): Deterministic backpressure**. The mechanism
   (`PDS_FIREHOSE_MAX_PENDING_SENDS`/`_BYTES` env overrides on
   `SubscribeReposHandler`) already existed; the gap was that `--binary`
   mode and the topology-compiler JSON preset didn't set them low the way
   `docker-compose.yml` already did, and scenario 33 slept a blind 90s
   instead of checking early. Both fixed; scenario 33 now passes
   deterministically in ~1-2s. Details and verification commands in
   workstream 01 S5.
2. **Complete (2026-07-17): Adversarial ingress**. New scenario 95 sends
   malformed/oversized/junk payloads at the live PDS repo/blob endpoints
   (closing the gap where scenarios 65/66 only ever exercised the Deno-side
   parser) and asserts rejection plus continued health. Details in
   workstream 01 S5.
3. **Partial (2026-07-17): Account lifecycle**. The write/read enforcement
   boundary already works and is already tested (scenario 55). Fixed one
   concrete bug (`getRepoStatus` hardcoded `active: true`) with a new test.
   Found, but did not implement, two real gaps: downstream
   propagation of account status to Relay/AppView is simply not wired
   (dead code in `RelayRepoStateManager`, no account-event path in
   `RelayClientDelegate`/`AppViewIngestEngine`, admin takedown never posts
   a notification), and gap-free cursor resume across a live
   disconnect/reconnect is untested. The propagation gap is a multi-file,
   moderation-relevant feature change — filed as a follow-up rather than
   rushed into this slice (see workstream 01 S5 for the full audit and
   exact call sites). The cursor-resume test is smaller and is the
   suggested next slice here.
4. **Complete (2026-07-17): Gated coverage into CI**. All 11 previously
   failing gated classes are repaired (root causes and fixes recorded in
   workstream 01 S5); a full `AllTests --gated=run` pass is green (3455
   tests, 0 failures — re-confirmed 2026-07-17 in isolation after an
   earlier concurrent run hit disk-pressure/SQLITE_FULL cascading
   failures unrelated to any code change here). `add_test` in
   `CMakeLists.txt` now runs `AllTests --gated=run` (verified via a fresh
   `cmake` reconfigure + `ctest -R '^AllTests$'`), and
   `scripts/test/run-tests.sh` / `run-asan-tests.sh` both pass
   `--gated=run` by default again.

Out of scope: Relay assembly (phase 7), incremental sync (phase 7),
implementing the account-status downstream-propagation feature (filed as
its own follow-up, not this phase's scope — see workstream 01 S5).

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

- Backpressure scenario green in structured runs, repeatably. **Met** —
  scenario 33, verified over multiple `--binary` runs.
- Lifecycle tests pass at both boundaries with current spec citations.
  **Met for write/read** (scenario 55, pre-existing; `getRepoStatus` fix
  covered by a new test). **Not met for downstream propagation** — not
  implemented, filed as a follow-up (see workstream 01 S5); a lifecycle
  test asserting Relay/AppView react to account status would fail today
  because the product code doesn't do it yet.
- CI runs the previously gated classes; counts recorded. **Met** — 3455
  tests, 0 failures, `ctest`-verified.
- Global gates pass. **Met**: `deno task check/lint/test` and
  `AllTests --gated=run` all green as of 2026-07-17 (this phase's own
  changes only touch `.m`/`.ts` files already covered above; no unrelated
  regressions found).

## Status note (2026-07-17)

Docker is confirmed available on this machine (`docker info` succeeds,
Docker version 29.4.0) — the earlier `blocked` status pending Docker no
longer applies. In practice this slice used `--binary` mode throughout
(via `scripts/manage_local_network.ts`/`packages/hamownia`), which stood
up PLC+PDS+Relay+AppView+chat+video+beskid without needing a Docker image
build — a research pass (recorded in this session, not separately filed)
found nothing in scope items 1-3 that specifically required Docker over
`--binary`; that requirement was conflated with phase 2's three-PDS need
(binary mode has no `"pds3"` case).

Remaining work for this phase, in priority order:

1. **Gap-free cursor resume test** (part of scope item 3): write a
   Deno scenario or ObjC integration test that disconnects and reconnects
   a live `subscribeRepos` consumer with `?cursor=N` and asserts no gap/no
   duplicate sequence numbers. `09_firehose_streaming.ts` is the natural
   home, or a new scenario. This is self-contained — no new product code
   needed, since `FirehoseProtocolSession`/`RelayUpstreamManager` already
   track sequence/cursor state correctly per the workstream 01 S5 audit.
2. **Account-status downstream propagation** (part of scope item 3): a
   real, multi-file feature (admin takedown → notification → firehose
   event; `RelayClientDelegate` account-event method;
   `AppViewIngestEngine`/`RelayRepoStateManager` wiring) — filed as its
   own follow-up task rather than folded in here. Exact call sites are in
   workstream 01 S5's account-lifecycle section.

## On completion

Update workstream 01 S5, mega-plan Phase 2 items 4-5; set
`status: complete` here. Phase 7 unblocks.
