# QueryRunner Deepening — Pilot Plan

**Status:** Steps 1 & 4 **enacted and verified** 2026-07-11 (QueryRunner gains a
self-managing single-write method; `ATProtoMediaSQLiteStore` migrated onto the seam).
Steps 2 & 3 (Transactor reshape of the write-transaction path + updating the Mikrus/Beskid
adopters) remain — deferred because the pilot store has no multi-statement transactions.
**Date:** 2026-07-11
**Lineage:** Successor to `refactor_opportunity_audit_report.md` (May 2026). That audit
extracted `ATProtoDatabaseQueryRunner`; this plan finishes deepening it and proves the
adoption pattern on one stranded store.

---

## Why

The May-2026 audit built three deep modules (`ATProtoDatabaseQueryRunner`,
`GZXrpcRouteSupport`, `ATProtoDIDDocumentFields`) but each was adopted by only the two
pilot services (`mikrus`, `beskid`) — the *extract-then-strand* pattern. This plan takes
the **QueryRunner** seam first, because it is both the highest-leverage of the three and
the one entangled with the `sqlite3 *` handle leakage.

The three seams are independent migrations and are being split. This plan covers **only**
the QueryRunner slice, and within it, **only a single pilot store**, to prove the pattern
before committing to the wider migration.

## Decision trail (from the grilling session)

1. **Split the three seams; do QueryRunner first.** They share only the theme, not the code.
2. **Deepen the write path before migrating.** QueryRunner's read path (`executeQuery:`)
   already hides `sqlite3 *`; the leak is confined to the write path
   (`performWriteTransaction:` hands the block a raw `sqlite3 *db`, threaded back into
   `executeUpdate:…connection:db`). Migrating stores onto a leaky interface then reshaping
   would touch each store twice.
3. **Write-path shape: a Transactor object.** The block receives an
   `id<ATProtoDatabaseTransactor>` — matching the existing `PDSActorStoreReader` /
   `PDSActorStoreTransactor` vocabulary — not a raw handle. Chosen over
   runner-as-transactor (shared mutable per-transaction state) and a declarative
   statement-list (cannot express ObjC-level conditional mid-transaction).
4. **Scope: pilot only.** Migrate one stranded store end-to-end through the new interface,
   then reassess. Pilot = `ATProtoMediaSQLiteStore`.
5. **Single-write shape: add `executeUpdate:params:error:`.** The pilot exposed a genuine
   gap — QueryRunner had no self-managing single-write method (the only write method
   required you to already hold a `sqlite3 *`). Add the write-side mirror of
   `executeQuery:`, and delete the `connection:`-taking variant.

## Why `ATProtoMediaSQLiteStore` is the pilot

- **Already on `ATProtoConnectionManagerSerial`** (`ATProtoMediaSQLiteStore.m:22`) — it did
  the concurrency migration already, so this is *pure mechanics-routing*, zero concurrency
  change. It just does its own prepare/bind/step/finalize inside `execute:` blocks.
- **Uses `execute:` only, never `transact:`** — ~6 single-statement writes, which is exactly
  what surfaced the missing self-managing `executeUpdate:`.
- **Characterization net already exists.** `Tests/Media/ATProtoMediaCoreTests.m` drives the
  full job-queue CRUD through the store's public interface (`createJobWithId:`,
  `getJobById:`, `updateJobState:`, `incrementJobRetry:`, `updateJobResults:`, plus
  duplicate / state-transition / retry-count assertions, `:141-266`). Replace-don't-layer
  is satisfied without writing new store tests.

## Target interface

```objc
// Core/… or Database/Utils/ — NEW protocol, mirrors PDSActorStoreTransactor
@protocol ATProtoDatabaseTransactor <NSObject>
- (nullable NSArray<NSDictionary<NSString *, id> *> *)executeQuery:(NSString *)sql
                                                            params:(nullable NSArray *)params
                                                             error:(NSError **)error;
- (BOOL)executeUpdate:(NSString *)sql params:(nullable NSArray *)params error:(NSError **)error;
@end

@interface ATProtoDatabaseQueryRunner : NSObject
- (instancetype)initWithConnectionManager:(id<ATProtoConnectionManager>)cm
                              errorDomain:(NSString *)errorDomain;
- (instancetype)initWithConnectionManager:(id<ATProtoConnectionManager>)cm
                             errorFactory:(ATProtoDatabaseQueryRunnerErrorFactory)factory
    NS_DESIGNATED_INITIALIZER;

// reads — self-managing connection (unchanged)
- (nullable NSArray<NSDictionary<NSString *, id> *> *)executeQuery:(NSString *)sql
                                                            params:(nullable NSArray *)params
                                                             error:(NSError **)error;

// NEW: single write — self-managing connection (mirror of executeQuery:).
// Returns affected-row count (>= 0), or negative on error — the pilot revealed the store
// needs the changes count to preserve its "no matching row -> 404" contract (JDBC-style).
- (NSInteger)executeUpdate:(NSString *)sql params:(nullable NSArray *)params error:(NSError **)error;

// reshaped: block yields a transactor, not a raw sqlite3 *
- (BOOL)performWriteTransaction:(BOOL (^)(id<ATProtoDatabaseTransactor> tx, NSError **error))block
                          error:(NSError **)error;
@end

// DELETED: - (BOOL)executeUpdate:params:connection:(sqlite3 *)db error:
```

Result: **no raw `sqlite3 *` in the data-access interface** — candidate 2's leak is closed
on this seam.

## Work unit (in order)

1. **Add `executeUpdate:params:error:`** to `ATProtoDatabaseQueryRunner` (self-managing
   connection, mirror of `executeQuery:`). New QueryRunner tests, red → green.
2. **Reshape `performWriteTransaction:`** to yield `id<ATProtoDatabaseTransactor>`; implement
   the transactor (thin wrapper binding the in-transaction connection); **delete** the
   `connection:`-taking `executeUpdate:`. Update `ATProtoDatabaseQueryRunnerTests`.
3. **Update the only two current callers** — `Mikrus/MikrusDatabase.m` (write transactions at
   `:218-244`, `:262-269`, `:592-…`) and `Beskid/BeskidDatabase.m` — from
   `^(sqlite3 *db, …){ [self executeUpdate:… connection:db …]; }` to
   `^(id<ATProtoDatabaseTransactor> tx, …){ [tx executeUpdate:… ]; }`. Both are tested;
   green confirms the reshape.
4. **Migrate `ATProtoMediaSQLiteStore`.** Replace the six inline
   `[self.connectionManager execute:^(sqlite3 *db){ prepare/bind/step/finalize }]` blocks
   with `executeQuery:` / `executeUpdate:`. Delete the bespoke sqlite mechanics
   (~77 `sqlite3_` calls collapse into QueryRunner calls). `ATProtoMediaCoreTests` stays
   green.

**Deletion-test payoff:** the pilot store's prepare/bind/step/finalize concentrates into the
one deep module; the store keeps only its SQL and job-domain logic.

## Verification

- `ATProtoMediaCoreTests` (existing) — regression net for the pilot store's behaviour.
- New QueryRunner unit tests — `executeUpdate:params:error:`, transactor read+write inside a
  transaction, rollback on error.
- `Mikrus*` / `Beskid*` suites — confirm the adopter reshape preserved behaviour.
- Build both platforms (`xcodebuild -scheme AllTests` / `cmake --build build`).

## Residual (known, deferred micro-decision)

`ATProtoDatabaseQueryRunnerErrorFactory` still takes `sqlite3 *db` (an error-message
formatting hook behind the `errorDomain:` convenience initializer). Recommendation: keep it —
it is not a data-access path — accepting that the header still imports `<sqlite3.h>`. Purging
it fully is a separate step.

## Deferred / excluded stores (the "then decide" set)

Post-pilot, reassess. Not part of this pilot:

| Store | Disposition | Reason |
|---|---|---|
| `JelczDatabase` | Defer (Tier 1) | already on ConnectionManagerSerial, but **0 tests** — characterization first (also closes report candidate 10) |
| `Session` | Defer (Tier 2) | owns hand-rolled queue → full concurrency migration; auth-critical (53 test refs) |
| `PDSReplayCache` | Defer (Tier 2) | owns hand-rolled queue |
| `PLCReplicaStore` | Defer (Tier 2) | owns hand-rolled queue; 0 tests |
| `PLCPersistentStore` | Defer (Tier 3) | prepared-statement cache — QueryRunner prepares per call; migration regresses perf unless QueryRunner grows a cache |
| `RateLimiter` | Defer (Tier 3) | shared singleton with lazy `initWithDatabasePath:nil` lifecycle |
| `AppViewDatabase` | Defer (Tier 3) | concurrency/pooling migration — see ADR 0002 |
| `SecItemLinuxStore` | **Exclude (permanent)** | `Compat/` shim depending on `Database/` is a layering inversion — see ADR 0001 |

## Not migratable into `ATProtoDIDDocumentFields` (report correction)

The report's DID slice over-counted. `PLC/PLCServer.m` and `PLC/PLCAuditor.m` parse
`verificationMethods` (plural — the PLC **operation** genesis/rotation format, a keyed dict),
not a resolved `DIDDocument`'s `verificationMethod` (singular array). They are a different
concept and must not be folded into `ATProtoDIDDocumentFields`. Only `VideoJWTAuthProvider`,
`XrpcIdentityHelper`, and `XrpcLexiconResolver` are genuine DID-doc adopters (a separate
future slice).

## Related records

- `docs/adr/0001-compat-shims-must-not-depend-on-database.md`
- `docs/adr/0002-defer-appview-database-queryrunner-migration.md`
- `CONTEXT.md` — `QueryRunner`, `Transactor` domain terms.
