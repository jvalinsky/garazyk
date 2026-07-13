---
title: Core Architecture and Reliability
status: active
last_verified: 2026-07-12
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

## A2. PLC schema closeout

`PLCPersistentStore` and its `PLCReplicaStore` subclass are now migrated onto
`ATProtoConnectionManagerSerial` + `ATProtoDatabaseQueryRunner` (hand-rolled queue,
raw `sqlite3 *`, and statement cache gone; tuned pragma config preserved; 59 PLC
tests green). Schema creation and the legacy ALTER upgrades still run as independent
statements that can leave a partial database — closing that out on the migrated base
is the remaining work.

Tests need a legacy schema file, duplicate/null sequence fixtures, injected
index failure, and either full rollback or deterministic rerun convergence. Keep
the existing 61-test PLC regression net.

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

## A7. Low-priority interface cleanup

After generator and coverage work:

- generate plain `NSString * const` endpoint NSIDs;
- delete XrpcHandler pass-through registration methods in stages;
- lint new raw endpoint literals;
- keep AppView pooling deferred under ADR 0002.
