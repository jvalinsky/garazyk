---
name: garazyk-database
description: "Garazyk PDS SQLite database layer patterns, connection pooling, WAL configuration, actor store, migration systems, schema management, and concurrency primitives. Use when writing or reviewing any database-layer code in this project."
---

# Garazyk PDS Database Patterns

## File Layout

Source root: `Garazyk/Sources/Database/`

```
ActorStore/ActorStore.h/.m            — Core PDSActorStore + Reader/Transactor protocols
ActorStore/PDSActorStoreInternal.h     — Internal @property db, stmtCache (NSMapTable), blobCache
ActorStore/PDSActorStore+Account.h/.m  — Account CRUD category
ActorStore/PDSActorStore+Blob.h/.m     — Blob CRUD category
Cache/PDSRecordCache.h/.m              — LRU record cache
Connection/ATProtoConnectionManagerPooled.h/.m — Pooled connection manager
Migrations/PDSMigration.h              — Migration protocol: up:/down: on sqlite3*
Migrations/PDSMigrationManager.h/.m    — Modern V1-V8 migrations
Monitoring/PDSHealthCheck.h            — Health check interface
Pool/DatabasePool.h/.m                 — Per-DID LRU pool
Pool/ATProtoConnectionPool.h/.m         — Raw sqlite3 connection pool
Schema/PDSSchemaManager.h/.m           — Central CREATE TABLE definitions
Service/PDSServiceDatabases.h/.m       — 3 pool bundles
Utils/PDSSQLiteUtils.h                 — PDS_SQLITE_AUTORELEASE_STMT macro
PDSDatabase.h/.m                       — Legacy monolithic database (~2880 lines)
PDSBlock.h                             — PDSDatabaseBlock model
PDSQueryDatabase.h                     — PDSQueryDatabase protocol
PDSRepositoryFactory.h/.m              — Feature-flag repo factory
Schema.h/.m                            — Legacy schema string constants
```

## Connection Pooling (Two Layers)

### DatabasePool (`Pool/DatabasePool.m`)
- Wraps `PDSActorStore` instances with LRU eviction (300s idle timeout).
- DID-based file sharding: `{method}/{prefix2}/{did}`.
- Per-DID serial dispatch queues for exclusive store access.
- Thread-safe via `dispatch_sync` on per-DID queues.

### ATProtoConnectionManagerPooled (`Connection/ATProtoConnectionManagerPooled.m`)
- Higher-level pooled connection manager built on `ATProtoConnectionPool`.
- Coordinates checkout/checkin for callers that need shared access to SQLite handles.
- Used by the connection layer to keep raw pool management out of feature code.

### ATProtoConnectionPool (`Pool/ATProtoConnectionPool.m`)
- Manages raw `sqlite3*` handles for a single database.
- Semaphore-based max-connection limiting (default min=2, max=10).
- Idle connection pruning (connections older than 30s).
- `checkoutConnection:` / `checkinConnection:` pattern with timeout support.
- Uses `sqlite3_close_v2` (not `sqlite3_close`) for safe virtual table shutdown.

## WAL Configuration

WAL mode set per-connection at open time:

- **Service databases** (Service/PDSServiceDatabases.m): `PRAGMA cache_size=-32000` (32K pages ≈ 128MB)
- **Actor stores** (ActorStore.m): `PRAGMA wal_autocheckpoint=1000, cache_size=-64000`
- **Legacy PDSDatabase** (PDSDatabase.m): `PRAGMA mmap_size=268435456, page_size=65536`

## Migration Systems

### Modern: PDSMigrationManager (`Migrations/PDSMigrationManager.m`)
- Uses `_migrations` table with name + appliedAt columns.
- Protocol `PDSMigration`: `-up:` / `-down:` on raw `sqlite3*`.
- Factory methods register the migration sets for service databases and actor stores.
- Applied via `-[PDSMigrationManager applyPendingMigrations:]`.

### Legacy monolithic database (`PDSDatabase.m`)
- Uses `Schema.h/.m` string constants for its CREATE TABLE statements.
- Keeps its own initialization path separate from the modern migration manager.

## ActorStore Reader/Transactor Pattern

### Protocols (`ActorStore/ActorStore.h`)
```objc
@protocol PDSActorStoreReader <NSObject>
- (BOOL)readWithBlock:(void(^)(sqlite3 *db))block error:(NSError **)error;
@end

@protocol PDSActorStoreTransactor <NSObject>
- (BOOL)transactWithBlock:(void(^)(sqlite3 *db, BOOL *rollback))block error:(NSError **)error;
@end
```

### Reentrancy-Safe Dispatch (`ActorStore.m`)
- `safeExecuteSync:` checks `dispatch_get_specific` to avoid deadlock on re-entrant calls.
- SAVEPOINT-aware nested transactions via `sqlite3_get_autocommit()`.
- `NSMapTable` with `NSPointerFunctionsOpaqueMemory` for statement caching (keyed by `@(sqlite3_sql(stmt))`).

### addColumnIfNeeded: (`ActorStore.m:1819-1876`)
- Whitelist validation for table/column/type names before any SQL.
- `PRAGMA table_info()` to check column existence before ALTER TABLE.
- Pattern: validate -> PRAGMA -> check result -> ALTER TABLE (if missing).

## Schema Management

### PDSSchemaManager (`Schema/PDSSchemaManager.m`)
- Central location for all CREATE TABLE definitions.
- Schema version enumeration (V1-V8).
- Creates tables conditionally (`CREATE TABLE IF NOT EXISTS`).

### Legacy Schema.h
- String constants for all CREATE TABLE statements.
- Used by both PDSDatabase.m and PDSSchemaManager.m.

## LRU Record Cache

### PDSRecordCache (`Cache/PDSRecordCache.m`)
- `NSDictionary` + ordered `NSMutableArray` for LRU ordering.
- Configurable max entries (default 10000), TTL, memory limit.
- Per-URI / per-DID / per-collection invalidation methods.
- Stats tracking (hits, misses, evictions).

## SQLite Utilities

### PDS_SQLITE_AUTORELEASE_STMT (`Utils/PDSSQLiteUtils.h`)
```objc
#define PDS_SQLITE_AUTORELEASE_STMT __attribute__((cleanup(PDSAutoReleaseStatement)))
```
- Automatic `sqlite3_finalize` via cleanup attribute.
- `sqlite3_close_v2` used everywhere for safe FTS5 shutdown.
- App passwords: PBKDF2-SHA256 (600000 iterations), base32 `XXXX-XXXX-XXXX-XXXX`.

## Concurrency Contracts

- **Per-DID serial queue** — all access to a given actor's store is serialized.
- **ATProtoConnectionPool semaphore** — bounds concurrent raw connections.
- **safeExecuteSync reentrancy** — same-thread calls execute directly without deadlock.
- **SAVEPOINT nested transactions** — only outermost transaction writes to WAL.

## Quick Reference

| Operation | Location | Pattern |
|---|---|---|
| Open actor store | ActorStore.m | `sqlite3_open_v2` + WAL pragmas + migrate |
| Open service DB | Service/PDSServiceDatabases.m | `ATProtoConnectionPool` checkout |
| Transaction | ActorStore.m | `safeExecuteSync` + SAVEPOINT check |
| Add column | ActorStore.m:1819 | validate -> PRAGMA -> ALTER TABLE |
| Pool checkout | Pool/ATProtoConnectionPool.m | semaphore_wait -> pop idle -> open |
| Migrate | Migrations/PDSMigrationManager.m | factory methods -> applyPending |
| LRU get | PDSRecordCache.m | array remove/insert + dict lookup |
| SQLite cleanup | PDSSQLiteUtils.h | `__attribute__((cleanup))` macro |
