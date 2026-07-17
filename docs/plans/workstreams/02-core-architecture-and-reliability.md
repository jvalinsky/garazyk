---
title: Core Architecture and Reliability
status: active
last_verified: 2026-07-16
---

# Core Architecture and Reliability

## A1. AppView migrations before pooling

`AppViewDatabase` creates a schema-version table but does not read or advance
it. Schema, ALTER, and index statements run without one transaction, some errors
are matched by text, and one table-creation failure is ignored. Existing tests
migrate only fresh in-memory databases.

1. Define ordered migration identifiers and record the applied version.
2. Run each migration in a transaction.
3. Add file-backed fixtures for supported legacy versions.
4. Inject failure after each statement and prove rollback plus unchanged
   version.
5. Reopen the migrated file and verify indexes and data.

Back up the database before a production schema bump. Binary rollback requires
restoring that backup. ADR 0002 continues to defer QueryRunner/pooling until
this migration work is safe and contention is measured.

## A2. PLC schema closeout (complete)

`PLCPersistentStore` and its `PLCReplicaStore` subclass are migrated onto
`ATProtoConnectionManagerSerial` + `ATProtoDatabaseQueryRunner` (hand-rolled queue,
raw `sqlite3 *`, and statement cache gone; tuned pragma config preserved). Schema
creation and the legacy ALTER upgrades now run inside a single `transact:` that
rolls back on any failed statement, so a partial database is no longer possible
(`4b3324a09`).

Covered by a legacy-schema upgrade fixture (columns added, `seq` backfilled, row
readable, reopen converges) and an injected index-collision rollback test
(`plc_operations` rolled back, the colliding table untouched). The 61-test PLC
regression net stays green. No remaining work on this item.

## A3. Objective-C modernization recovery

Recover the useful July plan without merging its stale branch base.

1. Re-evaluate and cherry-pick the H1, H2, and H5 hygiene commits.
2. Use the existing API-contract and concurrency findings as audit input.
3. Fix contracts per module, with no simultaneous god-file decomposition in the
   same module.
4. Decompose only after characterization tests and seam maps.

Priority decomposition targets:

- `OAuth2Handler.m`;
- `UIServerRuntime.m` and `UIBackendClient.m`;
- `AppViewXRpcRoutePack.m`, `XrpcRepoPack.m`, `XrpcAdminPack.m`, and
  `XrpcServerPack.m`;
- `PDSRecordService.m`, `PDSRepositoryService.m`, and the migration manager.

Keep MST and STAR cohesive unless a measured seam appears. GNUstep category
loading must be proven before splitting implementations into categories.

## A4. Shared CLI and lifecycle adoption

The July plan says these primitives are absent, but they now exist and are used
by Beskid, Mikrus, and Syrena. Continue adoption for the remaining binaries.

For each binary:

- characterize valid options, invalid input, exit code, and stderr;
- port option parsing to `GZCommandLineOptions`;
- port startup/shutdown to `GZServiceLifecycle`;
- preserve service-specific signals, crash diagnostics, and Linux category
  checks;
- smoke `--help` plus one real invocation on macOS and Linux.

One binary per commit gives each port an independent rollback.

## A5. Relay product decision

`kaszlak relay serve` currently constructs upstream components and sleeps. It
does not assemble a listener, downstream handler, delegate chain, or durable
cursor. Retry ownership is split across client and manager.

Choose one option before refactoring:

1. Build a real Relay with a listening server, one retry owner, persisted global
   cursor, and restart E2E.
2. Mark the command experimental, narrow its help text, and keep it out of
   production manifests.
3. Remove the command until the service is funded.

Acceptance for option 1: an upstream event reaches a downstream subscriber,
restart resumes from persisted state, duplicates are tolerated, gaps are not,
and exactly one reconnect is scheduled.

## A6. Incremental public sync

Response streaming is bounded, but export preparation can still materialize up
to 100,000 records plus changed-CID and tombstone sets. Collection listing also
opens actor stores per account.

Build byte-for-byte CAR/STAR fixtures, then introduce an incremental producer
behind a bounded fallback. Track peak memory in tests. Replace N+1 account
summary reads with indexed materialized metadata where measurements justify it.

When the Sync 1.1 remainder (export block ordering, collection-based
repository subsets) reaches published spec text, implement it in this lane;
workstream 01 S6 tracks the spec status.

## A7. Low-priority interface cleanup

After generator and coverage work:

- generate plain `NSString * const` endpoint NSIDs;
- delete XrpcHandler pass-through registration methods in stages;
- lint new raw endpoint literals;
- keep AppView pooling deferred under ADR 0002.
