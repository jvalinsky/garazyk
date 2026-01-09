# ATProtoPDS Storage Layer Improvement Plan

**Date:** January 8, 2026
**Status:** Research Complete

---

## Executive Summary

After researching storage options for the ATProto PDS implementation, **SQLite is the recommended path forward** with optimizations. Core Data migration is not advised due to the graph-based nature of ATProto data (MST repositories, CAR files) and significant refactoring costs.

---

## Research Findings

### SQLite Performance Capabilities
- Properly tuned SQLite can achieve **~8,300 writes/second** and **~168,000 reads/second** ([Sylvain Kerkour](https://kerkour.com/sqlite-for-servers))
- WAL mode provides **2x or more write performance** improvement over rollback journal
- Concurrent reads during writes are possible with WAL mode

### Bluesky's Official PDS
The official Bluesky PDS uses SQLite as its primary database:
- See PR [#1705: "Pds sqlite refactor"](https://github.com/bluesky-social/atproto/pull/1705)
- ATProto's data model (repos, records, DIDs) maps naturally to relational tables
- PDS scales to thousands of users with SQLite

### Core Data Assessment
**Not Recommended for this project:**
- Adds significant overhead and complexity
- ATProto's graph-based data (MST repositories, CAR files) doesn't map well to Core Data entities
- Would require complete rewrite of repository/sync logic
- Performance can suffer with large object graphs (see [stress-testing Core Data](https://aplus.rs/2024/core-data-performance-test/))

---

## Recommended Improvements

### Phase 1: SQLite Optimizations (Immediate)

#### 1.1 Optimize PRAGMAs
```objc
// Add to PDSDatabase.m openWithError:
sqlite3_exec(_db, "PRAGMA journal_mode = WAL", NULL, NULL, NULL);
sqlite3_exec(_db, "PRAGMA synchronous = NORMAL", NULL, NULL, NULL);
sqlite3_exec(_db, "PRAGMA cache_size = 65536", NULL, NULL, NULL);  // 64MB cache
sqlite3_exec(_db, "PRAGMA temp_store = MEMORY", NULL, NULL, NULL);
sqlite3_exec(_db, "PRAGMA mmap_size = 268435456", NULL, NULL, NULL);  // 256MB mmap
sqlite3_exec(_db, "PRAGMA page_size = 65536", NULL, NULL, NULL);  // 64KB pages
```

#### 1.2 Connection Pooling
Create a `DatabasePool` class to manage multiple SQLite connections for concurrent access.

#### 1.3 Prepared Statements Cache
Cache frequently-used SQL statements to reduce parse overhead.

#### 1.4 Index Optimization
Add indexes on:
- `repo_did` column in records table
- `collection` column for faster filtering
- `createdAt` for time-based queries

### Phase 2: Repository Architecture Improvements

#### 2.1 MST Persistence Layer
```objc
@interface MSTPersistence : NSObject
- (instancetype)initWithDatabase:(PDSDatabase *)db;
- (BOOL)saveMST:(MST *)mst forDID:(NSString *)did error:(NSError **)error;
- (nullable MST *)loadMSTForDID:(NSString *)did error:(NSError **)error;
- (NSArray<MSTEntry *> *)entriesWithPrefix:(NSString *)prefix forDID:(NSString *)did;
@end
```

#### 2.2 CAR File Import/Export
Implement  CAR file serialization for repo migration and sync.

#### 2.3 Blob Storage Improvements
- Add blob deduplication using CID hashes
- Implement blob compression for large files
- Add blob checksum verification

### Phase 3: Data Safety & Reliability

#### 3.1 Backup & Recovery
```objc
@interface DatabaseBackup : NSObject
- (BOOL)createBackupToURL:(NSURL *)url error:(NSError **)error;
- (BOOL)restoreFromBackupURL:(NSURL *)url error:(NSError **)error;
- (NSDate * _Nullable)lastBackupDate;
@end
```

#### 3.2 WAL Checkpoint Management
Implement periodic WAL checkpoints to prevent excessive WAL file growth:
```objc
// Checkpoint every 1000 pages or when WAL exceeds 100MB
sqlite3_exec(_db, "PRAGMA wal_checkpoint(TRUNCATE)", NULL, NULL, NULL);
```

#### 3.3 Corruption Detection
Add integrity checks:
```objc
sqlite3_exec(_db, "PRAGMA integrity_check", callback, NULL, NULL);
```

### Phase 4: macOS Sandbox Compatibility

#### 4.1 File Locations
| Data Type | Location |
|-----------|----------|
| Database | `~/Library/Application Support/ATProtoPDS/` |
| Blobs | `~/Library/Application Support/ATProtoPDS/blobs/` |
| Cache | `~/Library/Caches/com.atproto.pds/` |

#### 4.2 App Group Sharing
If needed for extensions, use App Groups:
```objc
NSURL *groupURL = [[NSFileManager defaultManager] 
    containerURLForSecurityApplicationGroupIdentifier:@"group.com.atproto.pds"]];
```

---

## Files to Create/Modify

### New Files
```
Database/
├── DatabasePool.h/.m          # Connection pooling
├── DatabasePool.h
├── DatabasePool.m
├── MSTPersistence.h/.m        # MST <-> SQLite mapping
├── DatabaseBackup.h/.m        # Backup/restore utilities
├── DatabaseMigrator.h/.m      # Schema migrations
└── PerformanceMonitor.h/.m    # Query performance tracking
```

### Modifications
```
Database/
├── PDSDatabase.m              # Add PRAGMA optimizations, connection pooling
└── Schema.m                   # Add indexes, improve schema

Blob/
└── BlobStorage.m              # Add deduplication, compression
```

---

## Migration Checklist

- [ ] Add WAL mode and performance PRAGMAs to PDSDatabase
- [ ] Create DatabasePool for connection management
- [ ] Implement prepared statement caching
- [ ] Add indexes on frequently queried columns
- [ ] Create MSTPersistence layer for repo storage
- [ ] Implement CAR file import/export
- [ ] Add blob deduplication using CID
- [ ] Implement WAL checkpoint management
- [ ] Add backup/restore utilities
- [ ] Add integrity check utilities
- [ ] Update blob storage location for sandbox
- [ ] Add performance monitoring/metrics
- [ ] Write unit tests for new database layer

---

## Estimated Effort

| Phase | Effort | Risk |
|-------|--------|------|
| Phase 1: SQLite Optimizations | 2-3 days | Low |
| Phase 2: Repository Architecture | 1 week | Medium |
| Phase 3: Data Safety | 3-4 days | Low |
| Phase 4: Sandbox Compatibility | 1-2 days | Low |

**Total Estimate:** 2-3 weeks

---

## References

- [SQLite Performance for Servers](https://kerkour.com/sqlite-for-servers)
- [SQLite WAL Mode Best Practices](https://learnsqlite.dev/posts/sqlite-write-ahead-logging/)
- [Bluesky PDS SQLite Refactor](https://github.com/bluesky-social/atproto/pull/1705)
- [Core Data Performance Testing](https://aplus.rs/2024/core-data-performance-test/)
- [SQLite Recommended PRAGMAs](https://highperformancesqlite.com/articles/sqlite-recommended-pragmas)
- [ATProto Going to Production](https://atproto.com/guides/going-to-production)
- [SQLite Production Gotchas](https://blog.pecar.me/sqlite-prod)

---

## Decision: SQLite with Optimizations

**Core Data migration is NOT recommended** because:

1. ATProto's data model (repos, MSTs, CAR files) is fundamentally graph-based and doesn't map well to Core Data's object graph
2. Bluesky's official implementation uses SQLite
3. The refactoring cost would be significant with marginal benefit
4. SQLite performance is more than sufficient for a personal/small-scale PDS

**Recommended: Optimize existing SQLite implementation** with the improvements outlined in this plan.
