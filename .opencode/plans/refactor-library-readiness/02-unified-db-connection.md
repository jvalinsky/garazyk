# Refactor 2: Unified Database Connection Protocol

## Evidence

**6 separate sqlite3\* handle management implementations** with duplicated patterns:

| # | File | Lines | Own Handle? | Strategy |
|---|---|---|---|---|
| 1 | `Garazyk/Sources/Database/PDSDatabase.m` | 3804 | `sqlite3 *_db` | 1 handle + LRU stmt cache |
| 2 | `Garazyk/Sources/AppView/Server/AppViewDatabase.m` | 1520 | `sqlite3 *_db` | 1 handle, manual |
| 3 | `Garazyk/Sources/Video/JelczDatabase.m` | ~350 | `sqlite3 *_db` | 1 handle, no cache |
| 4 | `Garazyk/Sources/Constellation/ConstellationDatabase.m` | ~200 | Via `PDSConnectionPool` | Acquire/release |
| 5 | `Garazyk/Sources/Database/Pool/PDSConnectionPool.m` | ~350 | `NSMutableArray<NSNumber*>` | Semaphore pool |
| 6 | `Garazyk/Sources/Database/ActorStore/PDSActorStore.m` | ~500 | Delegates to `PDSDatabase` | Wraps PDSDatabase |

**Duplicated patterns across implementations:**

- `safeExecuteSync:` reentrancy guard — 3 copies (PDSDatabase.m:66, AppViewDatabase.m:411, ActorStore.m:186)
- `dispatch_queue_set_specific` + static key — 4 different key declaration styles
- `valueFromStatement:` / `_valueFromStatement:` / `ConstellationColumnValue` / `rowFromStatement:` — 4 implementations of the same column reader
- Parameter binding — `bindData:toStatement:index:` (PDSDatabase), `_bindParams:toStatement:` (AppViewDatabase), `ConstellationBind` (ConstellationDatabase)
- `errorWithMessage:code:` — PDSDatabase, JelczDatabase, ConstellationDatabase all define their own
- `parameterPlaceholdersForCount:` — identical code in PDSDatabase.m:2587 and AppViewDatabase.m:1468
- PRAGMA setup — each independently sets WAL, synchronous, busy timeout

## Why It Matters

Every new service binary has to reimplement its own database connection layer. This is the single largest source of friction when creating a new AT Protocol service with this library. A unified connection protocol means:

- New services = one line to pick a connection strategy, not 500 lines of boilerplate
- Statement lifecycle bugs (leaked `sqlite3_stmt`, imbalanced transactions) are fixed once
- SQL injection vulnerabilities are prevented once (parameter binding wrapper)
- Cross-service database monitoring and health checks become possible

## Proposed Solution

### Core: `PDSConnectionManager` protocol + concrete implementations

```
PDSConnectionManager.h  ← protocol
PDSConnectionManager_Serial.sql  ← single-handle serial queue
PDSConnectionManager_Pooled.sql  ← connection pool adapter
PDSConnectionManager_Reentrant.sql  ← reentrancy-safe wrapper
```

### Shared: `PDSDatabaseUtilities`

Extract into a shared utility class or C functions:

```
PDSDatabaseUtilities.h/.m
├── PDSDBPlaceholderList(NSUInteger count)        → @"?, ?, ?"
├── PDSDBBindValue(sqlite3_stmt *, int idx, id)    → type-dispatching bind
├── PDSDBColumnValue(sqlite3_stmt *, int col)      → type-dispatching column read
├── PDSDBError(NSString *msg, NSInteger code)      → standard NSError
├── PDSDBConfigurePragmas(sqlite3 *, PDSDBConfig)  → one-call PRAGMA setup
├── PDSDBAutoFinalize cleanup macro                → already exists in PDSSQLiteUtils.h
```

### Standard PRAGMA Configuration

Define a `PDSDBConfig` struct that captures all PRAGMA settings:

```objc
typedef struct {
    bool wal;
    bool foreignKeys;
    int busyTimeout;     // ms
    int cacheSizePages;  // negative = KB
    int walAutocheckpoint;
    int journalSizeLimit;
    int mmapSize;
    int pageSize;
} PDSDBConfig;

extern const PDSDBConfig PDSDBConfigDefault;
extern const PDSDBConfig PDSDBConfigActorStore;
extern const PDSDBConfig PDSDBConfigServiceDatabase;
extern const PDSDBConfig PDSDBConfigBulkRead;
```

## Staging

| Step | Description | Rollback |
|------|-------------|----------|
| 1 | Extract `PDSDatabaseUtilities` — placeholder list, column readers, bind helpers | Revert file addition |
| 2 | Extract `PDSDBConfigurePragmas(config)` — one-call pragma setup | Revert file addition |
| 3 | Define `PDSConnectionManager` protocol | Revert protocol addition |
| 4 | Implement `PDSConnectionManager_Serial` | Revert implementation |
| 5 | Implement `PDSConnectionManager_Pooled` (wraps PDSConnectionPool) | Revert implementation |
| 6 | Migrate ConstellationDatabase to use shared utilities + PDSConnectionManager | Revert single file |
| 7 | Migrate JelczDatabase to use shared utilities | Revert single file |
| 8 | Migrate AppViewDatabase to use shared utilities | Revert single file |
| 9 | Migrate PDSDatabase to delegate to shared utilities | Revert single file |
| 10 | Remove duplicated code from originals | Revert cleanup commits |

## High-Level WAL Configuration Reference

| Database | WAL | Autockpt | Cache | mmap | BusyTO |
|----------|-----|----------|-------|------|--------|
| Service databases | ON | 1000 | -32000 (32K pages) | default | 5000 |
| Actor stores | ON | 1000 | -64000 (64K pages) | default | 5000 |
| Legacy PDSDatabase | ON | default | 65536 (64K pages) | 268435456 | default |
| AppView | ON | default | default | default | 5000 |
| Jelcz (video) | ON | default | default | default | default |
| PLCPersistentStore | ON | default | default | default | default |

These should become named `PDSDBConfig` constants.

## Dependencies

- After PDSDatabase decomposition (Refactor 1) — cleaner boundaries make extraction easier
- Requires cross-team agreement on the protocol shape
- Characterization tests needed before migrating each consumer

## Confidence: High

The patterns are well-understood. Each duplicated implementation is self-contained. The PDSAutoReleaseStatement macro (`PDSSQLiteUtils.h`) already proves this extraction style works.
