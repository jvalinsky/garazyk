---
title: Security and Protocol Correctness
status: active
last_verified: 2026-07-17
---

# Security and Protocol Correctness

## S1. Duplicate XRPC ownership

Current strict coverage finds:

- `app.bsky.graph.getListMutes` registered twice in `XrpcAppBskyGraphPack.m`,
  with different validation;
- `app.bsky.graph.getListBlocks` registered twice in the same pack;
- `app.bsky.labeler.getServices` owned by both the main and unspecced packs.

`XrpcHandler` silently uses the last registration. Delete duplicate ownership in
isolated commits and add a registry test that fails on same-file and cross-pack
duplicates. Preserve one route-level characterization per endpoint.

Rollback: revert one ownership commit. Do not restore silent duplicate
registration in tests or debug builds.

## S2. Canonical lexicon generation

Two generators disagree about the source root. The package generator defaults to
the empty top-level `lexicons/` path and can overwrite its catalog with zero
entries. The root generator reads `Garazyk/Resources/lexicons`.

1. Choose one generator core and one canonical lexicon root.
2. Fail when zero lexicons or zero endpoints are found.
3. Classify record, query, procedure, and subscription definitions separately.
4. Generate TypeScript and Objective-C artifacts deterministically.
5. Add a CI drift check after generation.

Generated NSID constants depend on this task. Do not start that migration first.

## S3. Truthful XRPC coverage

**Status: complete (report-only).** Split metrics report built at
`reports/xrpc_split_metrics.md` (2026-07-17). Six separate metrics published:
registered (213), schema-covered (207), behavior-verified (124), static routes
(213), dynamic AppView routes (0), Garazyk extensions (0). 89 endpoints
without behavior verification identified. Script:
`scripts/docs/generate_xrpc_split_metrics.cjs`.

Semantic fixes applied (2026-07-17):

- `chat.bsky.actor.declaration` phantom query removed from
  `XrpcChatBskyActorPack.m` — lexicon declares type "record", not "query".
- `app.bsky.labeler.getServices` now validates required `dids` parameter and
  returns 400 on missing/empty; spurious `cursor` field removed from response.
  Both registration sites fixed (`XrpcAppBskyPack.m`, `AppViewXRpcRoutePack.m`).
  Tests updated.
- `com.atproto.admin.getRecord` uses `ATURI` class for proper AT-URI parsing
  instead of naive string splitting; explicit compatibility policy documented
  in code comment.

## S4. Absolute HTTP deadlines

`HttpConnectionIOCoordinator` checks time before scheduling a receive, has no
timer to cancel a receive that never completes, and resets the header start time
after each chunk. A client can retain a connection by trickling header bytes.

Add configurable idle and aggregate header deadlines. The aggregate deadline
starts with the first byte and never resets. On expiry, emit one error and
cancel the transport.

Characterization:

- fake receive never completes;
- one byte arrives repeatedly beyond the aggregate deadline;
- a valid slow request inside both limits succeeds;
- timeout emits one terminal result and releases the connection.

Rollback: coordinator-only revert with the previous timeout available behind a
short-lived loopback/test flag.

## S5. Functional federation and lifecycle checks

The May adversarial scenarios exist, but some exercise only Deno parsers. Add
tests that send malformed or oversized data through the live Objective-C ingress
boundary and assert PDS, Relay, and AppView health afterward.

Firehose tests must set low pending-send and byte limits in the scenario
topology so `ConsumerTooSlow` is deterministic and independent of OS TCP
buffering. Production defaults stay unchanged.

Account lifecycle tests must follow the current specifications:

- downstream services stop redistributing inactive accounts;
- `active` controls visibility while `status` refines the state;
- event sequences increase monotonically and persisted cursors resume without
  gaps;
- suspension and takedown behavior is tested at both write and read boundaries.

### Gated Objective-C coverage into CI

Twenty-eight `AllTests` classes are gated behind `PDS_RUN_INTEGRATION_TESTS=1`
and `PDS_RUN_SOCKET_TESTS=1` and are silently skipped in the default run. They
are not failures, but a coverage blind spot. Before merge, run both with
services available, then fold both invocations into the quality-gate workflow
and CI so the gated classes are measured, not skipped. (Folded here from the
retired 2026-07-13 remediation plan, WS5.)

## S6. Published-spec conformance matrix

**Status: complete (report-only).** Matrix built at
`docs/reports/spec-conformance-matrix.md` (commit `703723c4c`,
2026-07-17). 20 spec rows + Proposal 0016 = 21 rows total. 16 supported,
4 partial, 0 gap. Every "supported" row names at least one executable
proof (unit test, scenario, or CI gate).

Known gaps verified against codebase and seeded as backlog leads:

- **G1: Permissions — granular scope evaluation.** `PDSSpaceScope.h/.m`
  implements `space:` scope parsing; no `repo:`/`rpc:`/`blob:`/`account:`/
  `include:` resource-type scope evaluation found. Required for production
  readiness. Own lane.
- **G2: Sync 1.1 remainder.** Export block ordering and collection-based
  repo subsets still in-progress upstream. Track alongside workstream 02 A6.
- **G3: Account management surfaces.** S5 covers propagation; confirm
  deactivation/deletion/export UX endpoints against accounts spec.
- **G4: Labels — self-signing key.** Label distribution and query endpoints
  implemented (`XrpcLabelPack.m`, 671 lines); no `#atproto_label` key
  generation or label signature verification found.

The matrix builds on S3's truthful XRPC metrics but is broader: spec pages,
not endpoints, are the unit. Report-only; a red row is a lead, not a release
blocker, until triaged into a workstream.

Rollback: documentation-only until a gap lane starts; each gap lane carries
its own rollback notes.

Primary sources:

- [Specification index](https://atproto.com/specs/atp)
- [Account lifecycle](https://atproto.com/specs/account)
- [Event streams](https://atproto.com/specs/event-stream)
- [Synchronization](https://atproto.com/specs/sync)
- [OAuth profile](https://atproto.com/specs/oauth)
- [Permissions](https://atproto.com/specs/permissions)
- [did:plc v0.3](https://web.plc.directory/spec/v0.1/did-plc)
