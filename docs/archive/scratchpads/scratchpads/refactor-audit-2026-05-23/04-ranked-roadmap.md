# Refactoring Ranked Roadmap: Mikrus, Beskid, and Syrena

This roadmap stages the recommended refactors so each phase has a small blast
radius and a clear test gate.

## Phase 0: Baseline and Characterization

Before changing implementation code:

```bash
cmake --build build --target AllTests --parallel
./build/tests/AllTests --filter 'Beskid*'
./build/tests/AllTests --filter 'Mikrus*'
./build/tests/AllTests --filter 'AppViewDatabaseTests*'
```

Keep AppView in the baseline even though it is deferred, because later
documentation should not claim AppView is covered by the first extraction.

## Phase 1: SQLite Query Runner Extraction

**Goal**: centralize Mikrus/Beskid SQLite statement execution behind
`ATProtoDatabaseQueryRunner`.

Steps:

1. Add `ATProtoDatabaseQueryRunner.[hm]` under
   `Garazyk/Sources/Database/Utils/`.
2. Use `ATProtoConnectionManager`, `ATProtoDBBindParams`,
   `ATProtoDBColumnValue`, and `PDS_SQLITE_AUTORELEASE_STMT`.
3. Add direct tests under `Garazyk/Tests/Database/`.
4. Port `BeskidDatabase.m` first.
5. Run `./build/tests/AllTests --filter 'Beskid*'` and the new query-runner
   tests.
6. Port `MikrusDatabase.m`.
7. Run `./build/tests/AllTests --filter 'Mikrus*'` and the query-runner tests.
8. Remove only the duplicated local helpers that the runner fully replaces.

Rollback:

- Revert only the database class and runner changes for this phase. No schema
  migration is involved.

## Phase 2: XRPC Route Support and DID Field Extraction

**Goal**: remove duplicated route helper code while building on existing
network/identity helpers.

Steps:

1. Add `GZXrpcRouteSupport.[hm]` or equivalent under `Garazyk/Sources/Network/`.
2. Delegate invalid request and internal error JSON to `XrpcErrorHelper`.
3. Delegate rate-limit header generation to `RateLimiter` where current behavior
   allows it.
4. Add `ATProtoDIDDocumentFields.[hm]` or public `DIDDocument` helpers for
   normalized handle, PDS endpoint, and signing key extraction.
5. Add tests for modern and legacy DID document shapes.
6. Port Beskid route helpers.
7. Port Mikrus route helpers.
8. Run `./build/tests/AllTests --filter 'Beskid*'` and
   `./build/tests/AllTests --filter 'Mikrus*'`.

Rollback:

- Revert route-pack call-site changes while keeping helper tests if they expose
  existing parsing behavior.

## Phase 3: CLI Parser Standardization

**Goal**: replace hand-written service option loops with a schema-driven parser.

Steps:

1. Add a small parser primitive for long/short options, repeatable values,
   booleans, and command validation.
2. Add direct tests for missing values, unknown options, repeated `--relay`, and
   command-specific flags.
3. Port Beskid first.
4. Port Mikrus.
5. Port Syrena only after the parser supports `serve` and `status` command
   differences.

Rollback:

- Each binary can return to its local `parse_options` function independently.

## Phase 4: Configuration Parsing Utilities

**Goal**: share low-level parsing helpers without forcing a shared base class.

Steps:

1. Add `GZConfigurationParsing.[hm]` under `Garazyk/Sources/Shared/` or
   `Garazyk/Sources/Core/`.
2. Add tests for CSV, bounded integer, boolean, and time interval parsing.
3. Port `BeskidConfiguration`.
4. Port `MikrusConfiguration`.
5. Port only the AppView parser pieces that match exactly.

Rollback:

- Keep service-specific properties and load order intact so each service can
  revert independently.

## Phase 5: Entrypoint Lifecycle Helper

**Goal**: reduce boilerplate in `main.m` while preserving service-specific
hooks.

Steps:

1. Add a lifecycle helper that handles common signal/crash/curl/category-link
   setup.
2. Expose pre-start and post-start hook points.
3. Preserve Syrena's exception handler, SIGABRT handler, and Linux category
   selector assertion.
4. Port Beskid first, then Mikrus, then Syrena.

## Deferred: AppView Connection Manager Migration

Do not combine this with the query-runner phase.

Required pre-work:

- Characterize AppView's serialized queue assumptions.
- Add tests around ingestion, backfill, write proxy, and concurrent reads.
- Consider `ATProtoConnectionManagerSerial` before introducing a pool.
- Only evaluate pooling after the serial manager path is behaviorally identical.
