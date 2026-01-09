# ATProtoPDS Database Implementation Review

**Date**: 2026-01-09
**Scope**: Schema, Data Access, Concurrency, Performance, Migration

## 1. Executive Summary

The ATProtoPDS codebase is currently supporting a transition from a monolithic SQLite database (`PDSDatabase`) to a sharded, multi-tenant architecture (`ServiceDatabases` + `ActorStore`). This is a positive architectural shift for scalability.

However, critical performance bottlenecks exist in the migration logic and the new `ActorStore` implementation that must be addressed before production use at scale. Specifically, the migration manager commits a transaction for every single record, and the `ActorStore` fails to cache prepared statements.

## 2. Architecture & Schema Design

### 2.1. Dual Architecture
- **Legacy/Monolithic**: `PDSDatabase` contains all tables (`accounts`, `repos`, `records`, `blocks`) in a single SQLite file.
- **Sharded (New)**: `ServiceDatabases` manages global state (`accounts`, `invite_codes`), while `PDSDatabasePool` manages per-user `ActorStore` instances.

### 2.2. Schema Observations
- **Redundancy**: The `ActorStore` schema includes an `accounts` table. Since `ServiceDatabases` already maintains a global `accounts` table, this appears redundant unless it serves as a local cache. If it is a cache, synchronization logic needs to be verified.
- **Data Model Differences**:
  - `PDSDatabase.records`: Metadata only. Content is likely reconstructed from blocks.
  - `ActorStore.records`: Includes a `value` BLOB column. This suggests the new architecture optimizes for record retrieval without traversing IPLD blocks for every read.
- **Directory Structure**: `DatabasePool` implements a sharded directory structure (`db/{prefix}/{did}`), which is excellent for file system performance with large user counts.

## 3. Data Access & Performance

### 3.1. Statement Caching (Critical)
- **PDSDatabase**: Correctly implements statement caching (`statementCache`).
- **ActorStore**: **Missing optimization.** While the class has a `stmtCache` property, `prepareStatement` creates a new statement every time and `finalizeStatement` destroys it immediately.
  - **Impact**: High CPU overhead and latency for read/write operations in the new architecture.
  - **Recommendation**: Implement proper statement caching in `ActorStore` similar to `PDSDatabase`.

### 3.2. SQLite Configuration
- Both implementations correctly use WAL mode (`PRAGMA journal_mode=WAL`) and `synchronous=NORMAL`, which are optimal settings for SQLite performance and durability.
- Memory mapping (`mmap_size`) is configured in `PDSDatabase` but should also be verified for `ActorStore`.

## 4. Concurrency

### 4.1. Thread Safety
- **PDSDatabase**: Relies on SQLite's default "Serialized" threading mode. It uses a single connection without explicit locking in the ObjC layer (except for the statement cache).
- **ActorStore**: Uses a `transactionQueue` (Serial Dispatch Queue) to serialize write transactions. Reads run on the caller's thread.
  - **Analysis**: This is a robust pattern (Single Writer, Multiple Readers) supported by WAL mode.
- **DatabasePool**: Uses a serial queue to protect the pool dictionary. This is thread-safe.

## 5. Migration (Critical Bottleneck)

The `PDSMigrationManager` contains a severe performance flaw in `migrateFromMonolithicDatabase:...`.

### 5.1. The Issue
For every record and block found in the source database, the migration manager:
1. Opens a transaction (`transactWithDid`).
2. Prepares a statement.
3. Inserts **one** item.
4. Commits the transaction.

```objc
// PDSMigrationManager.m
while (sqlite3_step(recordStmt) == SQLITE_ROW) {
    // ...
    [destinationPool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor) {
        // Creates a transaction for ONE insert
        [store putRecord:record forDid:did error:&recordError];
    } error:&recordError];
}
```

### 5.2. Impact
- SQLite can typically handle tens of thousands of inserts per second *within* a transaction.
- With separate transactions (fsync per commit), performance drops to ~10-100 inserts per second (disk dependent).
- For a database with 100k records, migration could take hours instead of seconds.

### 5.3. Recommendation
- Rewrite migration to batch inserts (e.g., 1000 items per transaction) or use a single transaction per user/repo migration.

## 6. Recommendations

1.  **Fix Migration Performance**: Refactor `PDSMigrationManager` to batch inserts.
2.  **Enable Statement Caching**: Fix `ActorStore` to actually use its `stmtCache`.
3.  **Schema Cleanup**: Clarify the role of `accounts` table in `ActorStore`. Remove if unnecessary.
4.  **Verification**: Add concurrency tests for `ActorStore` to ensure `readWithBlock` is safe while `transactionQueue` is active (WAL mode usually handles this, but verification is good).

