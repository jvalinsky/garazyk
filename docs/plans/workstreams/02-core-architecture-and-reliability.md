---
title: Core Architecture and Reliability
status: active
last_verified: 2026-07-19
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

- `OAuth2Handler.m` — **DONE (2026-07-23)**: decomposed into 12 categories
  (+Authorization, +ClientValidation, +ClientMetadataFetch, +PAR, +PasskeyAuth,
  +DPoP, +TokenEndpoint, +TokenRevocation, +ConsentStore, +Metadata, +Assets,
  +Helpers) plus _Internal.h; main file reduced from 4197 to 252 lines.
  85 OAuth characterization tests pass.
- `AppViewXRpcRoutePack.m`, `XrpcRepoPack.m`, `XrpcAdminPack.m`, and
  `XrpcServerPack.m` — **DONE (2026-07-23)**: decomposed into route-based
  categories; combined 6885 lines reduced to ~1704 (75% reduction).
- `PDSRecordService.m` — **DONE (2026-07-23)**: decomposed into 6 categories
  (+Validation, +Authorization, +RecordCRUD, +BatchWrites, +CommitPlumbing,
  +Stats) plus _Internal.h; main file reduced from 1982 to 66 lines.
  51 PDS record characterization tests pass.
- `PDSRepositoryService.m` — **DONE (2026-07-23)**: decomposed into 5 categories
  (+MST, +Export, +Commit, +RecordMaterializer, +RepoInit) plus _Internal.h;
  main file reduced from 2123 to 77 lines.
  36 PDS repository + 31 SQLite repository characterization tests pass.
- `UIBackendClient.m` — **DONE (2026-07-23)**: decomposed into 10 service
  categories (+PDS, +AppView, +Relay, +PLC, +Ozone, +Security, +Chat,
  +Video, +MST, +DataExplorer) plus `UIBackendClient_Internal.h`
  (`9f5d4d59c`).
- `UIServerRuntime.m` — **DONE (2026-07-23)**: route registrations moved
  into 11 route categories (+PDSRoutes, +AppViewRoutes, +RelayRoutes,
  +PLCRoutes, +DataExplorerRoutes, +LabRoutes, +OzoneRoutes,
  +SecurityRoutes, +ChatRoutes, +VideoRoutes, +MSTRoutes), core file
  ~1840 → ~900 lines (`ce5c80065`). `garazyk-ui`/`AllTests` build clean
  and `UIServerRuntimeTests` passes 23/23. Codemod scripts removed.
  Browser smoke and Linux GNUstep gate verified clean.
- Migration manager — covered by phase 11 database decomposition.

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

`garazyk-ui` is ported and verified across macOS and GNUstep/Linux (2026-07-19): its seven-case executable suite passes natively, `announceSignals:NO` and `GZCrashReporter` maintain its silent signal and `/tmp/garazyk-ui-crash.log` diagnostic contract, and the `garazyk-gnustep` Docker image confirms clean `--help` / `serve --help` execution inside Linux.

All remaining binaries (`jelcz`, `syrena-chat`, `germ`, `kaszlak`, `campagnola`, `zuk`) are now ported and verified (2026-07-19): each binary has an independent characterization suite (`JelczCommandTests`, `SyrenaChatCommandTests`, `GermCommandTests`, `KaszlakCommandTests`, `CampagnolaCommandTests`, `ZukCommandTests`) verified natively and across Linux/GNUstep, preserving specific option grammars, signal handling, and crash diagnostic logs (`/tmp/<binary>-crash.log`). All ports are committed one binary per commit.

## A5. Relay product decision (decided 2026-07-17 — remove)

Operator chose option 3: `kaszlak relay serve` is removed
(`PDSCLIRelayCommand` and its tests deleted; `zuk` is the canonical relay
binary). The underlying relay components stay — they serve `zuk`,
`PDSRelayService`, and `AppViewIngestEngine`, and now forward account
events end to end (`28641e671`, `a3f8d3c53`; scenario 97). Recorded as
ADR 0006. The removal is committed (`d9fa51a1d`) with ADR 0006 — this
item is closed. Reviving a hosted relay later requires a new command that
meets the old option-1 acceptance (see ADR 0006).

## A6. Incremental public sync

Response streaming is bounded, but export preparation can still materialize up
to 100,000 records plus changed-CID and tombstone sets. Collection listing also
opens actor stores per account.

Build byte-for-byte CAR/STAR fixtures, then introduce an incremental producer
behind a bounded fallback. Track peak memory in tests. Replace N+1 account
summary reads with indexed materialized metadata where measurements justify it.

**Progress (2026-07-18):** the N+1 account-summary fix (`headInfoForDid`
+ updated `listRepos`), the golden-fixture net (structural CAR/STAR
goldens, byte-identical re-export, peak memory/size bounds), and the
materialized `collection_membership` index with its admin stats/prune
endpoint are committed (`6de6ebc64`). Still pending: the incremental
producer itself, and test coverage for `PDSCollectionMembershipPruner` —
phase 7 owns finishing these.

**Closed (2026-07-19).** The Sync 1.1 remainder (export block ordering,
collection-based repository subsets) has not reached published spec text —
refetched https://atproto.com/specs/sync on 2026-07-19 and both remain
under "Future Work" prose, not a version-numbered spec. Workstream 01 S6 G2
tracks the spec status for future revisits.

A forward-compat, feature-flagged streamable-CAR pre-order enumerator
(`+[MST setStreamableCARBlockOrderingEnabled:]`, default off) with
preorder/fixture tests (`sync11-preorder-fixture.car`) is committed
(`ed01c8085`, on the lock-free atomic-root refactor `34e2b94ae`,
2026-07-18). Decision: keep the flag off — turning it on ahead of
finalized spec text risks shipping ordering upstream later changes
incompatibly, and no consumer needs it today.

Collection-based repository subsets were already implemented independently
as a vendor extension, `tools.garazyk.sync.getRepoFiltered`
(`-[PDSRepositoryService filteredRepoContentsChunkProducer:since:collections:error:]`,
registered in `XrpcVendorPack.m`), now with test coverage for inclusion/
exclusion, the no-match case, and the empty-collections error path
(`PDSRepositoryServiceTests.m`, phase 7). This vendor extension serves
Garazyk's own collection-subset need independent of the upstream flag.

## A7. Low-priority interface cleanup

After generator and coverage work:

- ~~generate plain `NSString * const` endpoint NSIDs~~ — done (`f46ab5fb8`);
- ~~delete XrpcHandler pass-through registration methods in stages~~ — done
  in the adoption sweep (`e212288bd`, with a CI drift check);
- ~~lint new raw endpoint literals~~ — done (2026-07-18): Narzedzia scans
  production Objective-C sources for direct `registerMethod:@"..."` calls,
  permits only internal underscore-prefixed handlers, and rejects every other
  literal in favor of generated constants. Six focused Deno tests and the
  read-only scan run in the existing NSID CI job; tests and indirect
  test-control constants are deliberately outside this narrow boundary;
- keep AppView pooling deferred under ADR 0002.
