---
title: Security and Protocol Correctness
status: active
last_verified: 2026-07-14
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

The current report checks only whether an endpoint NSID string is registered. It
does not compare verbs, parameters, input/output schemas, encoding, or errors.
Dynamic AppView routes are also invisible to the static registry scan.

Publish separate metrics:

- registered endpoints;
- schema-covered endpoints;
- behavior-verified endpoints;
- static dispatcher routes;
- dynamic AppView routes;
- explicit Garazyk compatibility extensions.

Start schema validation in report-only mode. Enforce after the baseline
mismatches are classified.

Required semantic fixes:

- `chat.bsky.actor.declaration` is a record, not a query. Remove the phantom
  query or assign a Garazyk-owned extension NSID.
- `app.bsky.labeler.getServices` must validate required `dids` and return
  indexed services instead of constant empty views.
- `com.atproto.admin.getRecord` needs an explicit compatibility policy and local
  schema under a namespace Garazyk owns, or removal.

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

Primary sources:

- [Account lifecycle](https://atproto.com/specs/account)
- [Event streams](https://atproto.com/specs/event-stream)
- [Synchronization](https://atproto.com/specs/sync)
- [OAuth profile](https://atproto.com/specs/oauth)
- [did:plc v0.3](https://web.plc.directory/spec/v0.1/did-plc)
