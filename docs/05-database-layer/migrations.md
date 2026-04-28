---
title: Database Migrations
---

# Database Migrations

## Overview

Database migrations manage schema changes and data transformations as the PDS evolves. The migration system ensures databases can be upgraded safely without data loss or corruption.

## Migration Strategy

The PDS uses a version-based migration system:

```

Current Schema Version: 1
├── Migration 1: Initial schema
├── Migration 2: Add new table
├── Migration 3: Add column to existing table
└── Migration 4: Rename column
```

## Migration Files

Migrations are organized by database type:

```

Garazyk/Sources/Database/Migration/
├── ServiceDatabaseMigrations/
│   ├── Migration_001_InitialSchema.m
│   ├── Migration_002_AddInviteCodes.m
│   └── Migration_003_AddSessions.m
├── ActorDatabaseMigrations/
│   ├── Migration_001_InitialSchema.m
│   ├── Migration_002_AddRecordsTable.m
│   └── Migration_003_AddBlocksTable.m
└── MigrationManager.m
```

## Migration Execution

### Service Database Migrations

```sql
-- Migration_001_InitialSchema.sql
CREATE TABLE accounts (
    did TEXT PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    handle TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    status TEXT DEFAULT 'active'
);

CREATE TABLE invite_codes (
    code TEXT PRIMARY KEY,
    created_by TEXT NOT NULL,
    created_at DATETIME NOT NULL,
    used_by TEXT,
    used_at DATETIME,
    expires_at DATETIME
);

-- Migration_002_AddSessions.sql
CREATE TABLE sessions (
    session_id TEXT PRIMARY KEY,
    did TEXT NOT NULL,
    created_at DATETIME NOT NULL,
    expires_at DATETIME NOT NULL,
    last_activity DATETIME,
    FOREIGN KEY (did) REFERENCES accounts(did)
);

CREATE INDEX idx_sessions_did ON sessions(did);
CREATE INDEX idx_sessions_expires_at ON sessions(expires_at);
```

### Actor Database Migrations

```sql
-- Migration_001_InitialSchema.sql
CREATE TABLE repo_root (
    cid BLOB PRIMARY KEY,
    updated_at DATETIME NOT NULL
);

CREATE TABLE records (
    uri TEXT PRIMARY KEY,
    collection TEXT NOT NULL,
    rkey TEXT NOT NULL,
    cid BLOB NOT NULL,
    value BLOB,
    indexed_at DATETIME NOT NULL
);

CREATE INDEX idx_records_collection_rkey ON records(collection, rkey);

-- Migration_002_AddBlocksTable.sql
CREATE TABLE ipld_blocks (
    cid BLOB PRIMARY KEY,
    block BLOB NOT NULL,
    size INTEGER NOT NULL
);

CREATE INDEX idx_ipld_blocks_cid ON ipld_blocks(cid);
```

## Migration Manager

The `PDSMigrationManager` orchestrates database migrations and handles data transformation.

**Source:** `Garazyk/Sources/Database/Migration/PDSMigrationManager.m`

### Migration Execution Flow

```objc
// Lines 30-50: Main migration entry point
- (BOOL)migrateFromMonolithicDatabase:(NSString *)sourcePath 
                    toSingleTenantDirectory:(NSString *)destinationDirectory
                                  error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if (![fm fileExistsAtPath:sourcePath]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                        code:PDSMigrationErrorSourceNotFound
                                    userInfo:@{NSLocalizedDescriptionKey: @"Source database not found"}];
        }
        return NO;
    }
    
    [self updateProgress:0 status:@"Opening source database"];
    
    sqlite3 *sourceDb;
    int result = sqlite3_open(sourcePath.UTF8String, &sourceDb);
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to open source database"}];
        }
        return NO;
    }
    // ... migration continues
}
```

### Counting Records for Progress

```objc
// Lines 60-85: Count records to migrate for progress tracking
[self updateProgress:0.05 status:@"Counting records to migrate"];

{
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *countStmt = NULL;
    sqlite3_prepare_v2(sourceDb, "SELECT COUNT(*) FROM accounts", -1, &countStmt, NULL);
    if (sqlite3_step(countStmt) == SQLITE_ROW) {
        totalAccounts = sqlite3_column_int64(countStmt, 0);
    }
}

{
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *countStmt = NULL;
    sqlite3_prepare_v2(sourceDb, "SELECT COUNT(*) FROM repos", -1, &countStmt, NULL);
    if (sqlite3_step(countStmt) == SQLITE_ROW) {
        totalRepos = sqlite3_column_int64(countStmt, 0);
    }
}

{
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *countStmt = NULL;
    sqlite3_prepare_v2(sourceDb, "SELECT COUNT(*) FROM records", -1, &countStmt, NULL);
    if (sqlite3_step(countStmt) == SQLITE_ROW) {
        totalRecords = sqlite3_column_int64(countStmt, 0);
    }
}

{
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *countStmt = NULL;
    sqlite3_prepare_v2(sourceDb, "SELECT COUNT(*) FROM blocks", -1, &countStmt, NULL);
    if (sqlite3_step(countStmt) == SQLITE_ROW) {
        totalBlocks = sqlite3_column_int64(countStmt, 0);
    }
}
```

### Batch Account Migration

```objc
// Lines 100-130: Migrate accounts in batches for performance
NSMutableArray<PDSDatabaseAccount *> *allAccounts = [NSMutableArray array];
PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *accountStmt;
sqlite3_prepare_v2(sourceDb,
    "SELECT did, handle, email, password_hash, password_salt, access_jwt, refresh_jwt, created_at, updated_at "
    "FROM accounts", -1, &accountStmt, NULL);

while (sqlite3_step(accountStmt) == SQLITE_ROW) {
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(accountStmt, 0)];
    account.handle = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(accountStmt, 1)];

    int col = 2;
    if (sqlite3_column_type(accountStmt, col) != SQLITE_NULL) {
        account.email = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(accountStmt, col)];
    }
    col++;

    if (sqlite3_column_type(accountStmt, col) != SQLITE_NULL) {
        account.passwordHash = [NSData dataWithBytes:sqlite3_column_blob(accountStmt, col)
                                              length:sqlite3_column_bytes(accountStmt, col)];
    }
    col++;

    if (sqlite3_column_type(accountStmt, col) != SQLITE_NULL) {
        account.passwordSalt = [NSData dataWithBytes:sqlite3_column_blob(accountStmt, col)
                                              length:sqlite3_column_bytes(accountStmt, col)];
    }
    col++;

    if (sqlite3_column_type(accountStmt, col) != SQLITE_NULL) {
        account.accessJwt = [NSData dataWithBytes:sqlite3_column_blob(accountStmt, col)
                                           length:sqlite3_column_bytes(accountStmt, col)];
    }
    col++;

    if (sqlite3_column_type(accountStmt, col) != SQLITE_NULL) {
        account.refreshJwt = [NSData dataWithBytes:sqlite3_column_blob(accountStmt, col)
                                            length:sqlite3_column_bytes(accountStmt, col)];
    }
    col++;

    account.createdAt = sqlite3_column_double(accountStmt, col);
    col++;
    account.updatedAt = sqlite3_column_double(accountStmt, col);

    [allAccounts addObject:account];
    [accountDids addObject:account.did];
}

// Create accounts in batches for better performance
const NSUInteger batchSize = 100;
for (NSUInteger i = 0; i < allAccounts.count; i += batchSize) {
    if (self.cancelBlock && self.cancelBlock()) {
        sqlite3_close(sourceDb);
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                        code:PDSMigrationErrorCancelled
                                    userInfo:@{NSLocalizedDescriptionKey: @"Migration cancelled"}];
        }
        return NO;
    }

    NSUInteger endIndex = MIN(i + batchSize, allAccounts.count);
    NSArray<PDSDatabaseAccount *> *batch = [allAccounts subarrayWithRange:NSMakeRange(i, endIndex - i)];

    NSError *createError = nil;
    BOOL batchSuccess = [serviceDb createAccounts:batch error:&createError];
    if (!batchSuccess) {
        PDS_LOG_DB_ERROR(@"Migration failed to create account batch starting at index %lu: %@",
                         (unsigned long)i, createError);
    }

    migratedItems += batch.count;
    [self updateProgress:(0.1 + 0.3 * ((double)migratedItems / totalItems))
                  status:[NSString stringWithFormat:@"Migrating accounts (%ld/%ld)", (long)migratedItems, (long)totalAccounts]];
}
```

### Repository and Record Migration

```objc
// Lines 135-180: Migrate repos and records per user
[self updateProgress:0.4 status:@"Migrating repos and records"];

for (NSInteger i = 0; i < accountDids.count; i++) {
    NSString *did = accountDids[i];
    
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *repoStmt;
    sqlite3_prepare_v2(sourceDb, 
        "SELECT owner_did, root_cid, collection_data, created_at, updated_at FROM repos WHERE owner_did = ?",
        -1, &repoStmt, NULL);
    sqlite3_bind_text(repoStmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
    
    PDSDatabaseRepo *repo = nil;
    if (sqlite3_step(repoStmt) == SQLITE_ROW) {
        repo = [[PDSDatabaseRepo alloc] init];
        repo.ownerDid = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(repoStmt, 0)];
        
        if (sqlite3_column_type(repoStmt, 1) != SQLITE_NULL) {
            repo.rootCid = [NSData dataWithBytes:sqlite3_column_blob(repoStmt, 1) 
                                          length:sqlite3_column_bytes(repoStmt, 1)];
        }
        
        if (sqlite3_column_type(repoStmt, 2) != SQLITE_NULL) {
            repo.collectionData = [NSData dataWithBytes:sqlite3_column_blob(repoStmt, 2) 
                                                 length:sqlite3_column_bytes(repoStmt, 2)];
        }
        
        repo.createdAt = [NSDate dateWithTimeIntervalSince1970:sqlite3_column_double(repoStmt, 3)];
        repo.updatedAt = [NSDate dateWithTimeIntervalSince1970:sqlite3_column_double(repoStmt, 4)];
    }
    
    __block NSError *repoError = nil;
    if (repo) {
        [destinationPool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
            PDSActorStore *store = (PDSActorStore *)transactor;
            [store createRepo:repo error:blockError];
        } error:&repoError];
    }
    
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *recordStmt;
    sqlite3_prepare_v2(sourceDb, 
        "SELECT uri, did, collection, rkey, cid, created_at FROM records WHERE did = ?",
        -1, &recordStmt, NULL);
    sqlite3_bind_text(recordStmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
    
    while (sqlite3_step(recordStmt) == SQLITE_ROW) {
        PDSDatabaseRecord *record = [[PDSDatabaseRecord alloc] init];
        record.uri = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(recordStmt, 0)];
        record.did = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(recordStmt, 1)];
        record.collection = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(recordStmt, 2)];
        record.rkey = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(recordStmt, 3)];
        record.cid = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(recordStmt, 4)];
        record.createdAt = [NSDate dateWithTimeIntervalSince1970:sqlite3_column_double(recordStmt, 5)];
        
        __block NSError *recordError = nil;
        [destinationPool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
            PDSActorStore *store = (PDSActorStore *)transactor;
            [store putRecord:record forDid:did error:blockError];
        } error:&recordError];
    }
}
```

### Block Migration

```objc
// Lines 185-220: Migrate IPLD blocks
[self updateProgress:0.7 status:@"Migrating blocks"];

PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *blockStmt;
sqlite3_prepare_v2(sourceDb, 
    "SELECT cid, repo_did, block_data, content_type, size, created_at FROM blocks",
    -1, &blockStmt, NULL);

NSInteger blockIndex = 0;
while (sqlite3_step(blockStmt) == SQLITE_ROW) {
    if (self.cancelBlock && self.cancelBlock()) {
        sqlite3_close(sourceDb);
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                        code:PDSMigrationErrorCancelled
                                    userInfo:@{NSLocalizedDescriptionKey: @"Migration cancelled"}];
        }
        return NO;
    }
    
    NSData *cid = [NSData dataWithBytes:sqlite3_column_blob(blockStmt, 0) 
                                 length:sqlite3_column_bytes(blockStmt, 0)];
    NSString *repoDid = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(blockStmt, 1)];
    
    PDSDatabaseBlock *block = [[PDSDatabaseBlock alloc] init];
    block.cid = cid;
    block.repoDid = repoDid;
    
    if (sqlite3_column_type(blockStmt, 2) != SQLITE_NULL) {
        block.blockData = [NSData dataWithBytes:sqlite3_column_blob(blockStmt, 2) 
                                         length:sqlite3_column_bytes(blockStmt, 2)];
    }
    
    if (sqlite3_column_type(blockStmt, 3) != SQLITE_NULL) {
        block.contentType = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(blockStmt, 3)];
    }
    
    block.size = sqlite3_column_int64(blockStmt, 4);
    block.createdAt = [NSDate dateWithTimeIntervalSince1970:sqlite3_column_double(blockStmt, 5)];
    
    __block NSError *blockError = nil;
    [destinationPool transactWithDid:repoDid block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        [store putBlock:block forDid:repoDid error:innerError];
    } error:&blockError];
    
    blockIndex++;
    if (blockIndex % 100 == 0) {
        double progress = 0.7 + 0.3 * ((double)blockIndex / totalBlocks);
        [self updateProgress:progress 
                      status:[NSString stringWithFormat:@"Migrating blocks (%ld/%ld)", (long)blockIndex, (long)totalBlocks]];
    }
}
```

### Async Migration with Progress

```objc
// Lines 235-245: Async migration with completion handler
- (void)migrateFromMonolithicDatabaseAsync:(NSString *)sourcePath 
                        toSingleTenantDirectory:(NSString *)destinationDirectory
                                completion:(void (^)(NSError * _Nullable error))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        [self migrateFromMonolithicDatabase:sourcePath 
                        toSingleTenantDirectory:destinationDirectory 
                                      error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(error);
        });
    });
}
```

### Progress Reporting

```objc
// Lines 255-265: Update progress on main thread
- (void)updateProgress:(double)progress status:(NSString *)status {
    if (self.progressBlock) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressBlock(progress, status);
        });
    }
}
```

## Schema Versioning

Each database tracks its schema version:

```sql
CREATE TABLE schema_version (
    version INTEGER PRIMARY KEY,
    applied_at DATETIME NOT NULL,
    description TEXT
);

INSERT INTO schema_version (version, applied_at, description)
VALUES (1, datetime('now'), 'Initial schema');
```

## Migration Patterns

### Adding a New Table

```sql
-- Migration_004_AddLabelsTable.sql
CREATE TABLE labels (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    target TEXT NOT NULL,
    label TEXT NOT NULL,
    created_at DATETIME NOT NULL,
    created_by TEXT NOT NULL,
    UNIQUE(target, label)
);

CREATE INDEX idx_labels_target ON labels(target);
CREATE INDEX idx_labels_label ON labels(label);

-- Update schema version
INSERT INTO schema_version (version, applied_at, description)
VALUES (4, datetime('now'), 'Add labels table');
```

### Adding a Column

```sql
-- Migration_005_AddAccountStatus.sql
ALTER TABLE accounts ADD COLUMN status TEXT DEFAULT 'active';

-- Update schema version
INSERT INTO schema_version (version, applied_at, description)
VALUES (5, datetime('now'), 'Add account status column');
```

### Renaming a Column

```sql
-- Migration_006_RenameColumn.sql
-- SQLite doesn't support direct column rename, use workaround:

-- 1. Create new table with correct schema
CREATE TABLE accounts_new (
    did TEXT PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    handle TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    account_status TEXT DEFAULT 'active'  -- renamed from 'status'
);

-- 2. Copy data
INSERT INTO accounts_new SELECT * FROM accounts;

-- 3. Drop old table
DROP TABLE accounts;

-- 4. Rename new table
ALTER TABLE accounts_new RENAME TO accounts;

-- 5. Recreate indexes
CREATE INDEX idx_accounts_email ON accounts(email);
CREATE INDEX idx_accounts_handle ON accounts(handle);

-- Update schema version
INSERT INTO schema_version (version, applied_at, description)
VALUES (6, datetime('now'), 'Rename status column to account_status');
```

### Data Transformation

```sql
-- Migration_007_NormalizeHandles.sql
-- Convert handles to lowercase

UPDATE accounts SET handle = LOWER(handle);

-- Update schema version
INSERT INTO schema_version (version, applied_at, description)
VALUES (7, datetime('now'), 'Normalize handles to lowercase');
```

## Migration Execution Flow

```

1. Check current schema version
   ↓
2. Determine target schema version
   ↓
3. For each migration from current to target:
   a. Begin transaction
   b. Execute migration SQL
   c. Update schema_version table
   d. Commit transaction
   ↓
4. Verify schema integrity
   ↓
5. Report success/failure
```

## Rollback Strategy

Migrations are designed to be forward-only. Rollback is not supported:

```objc
// Rollback is NOT supported
// To revert a migration, create a new migration that undoes the changes
```

If a migration fails:

1. Transaction is rolled back automatically
2. Database remains at previous schema version
3. Error is reported with details
4. Administrator must fix the issue and retry

## Migration Testing

### Test Migration Execution

```objc
// Create test database
PDSDatabase *testDb = [[PDSDatabase alloc] initWithPath:@"/tmp/test.db"];

// Run migrations
NSError *error = nil;
BOOL success = [[PDSMigrationManager sharedManager] migrateServiceDatabase:testDb
                                                                     error:&error];

// Verify schema
NSInteger version = [[PDSMigrationManager sharedManager] currentSchemaVersion:testDb
                                                                        error:&error];
XCTAssertEqual(version, 7);
```

### Test Data Preservation

```objc
// Insert test data
[testDb executeUpdate:@"INSERT INTO accounts (did, email, handle, password_hash, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)"
         withParameters:@[@"did:plc:test", @"test@example.com", @"test", @"hash", @"2025-01-01", @"2025-01-01"]];

// Run migrations
NSError *error = nil;
[[PDSMigrationManager sharedManager] migrateServiceDatabase:testDb error:&error];

// Verify data is preserved
NSArray *results = [testDb executeQuery:@"SELECT * FROM accounts WHERE did = ?", @"did:plc:test"];
XCTAssertEqual(results.count, 1);
```

## Best Practices

1. **Migration Design**
   - Keep migrations small and focused
   - One logical change per migration
   - Include descriptive comments
   - Test thoroughly before deployment

2. **Schema Changes**
   - Always add new columns with DEFAULT values
   - Use NOT NULL only when necessary
   - Create indexes for frequently queried columns
   - Document schema changes

3. **Data Transformation**
   - Validate data before transformation
   - Preserve data integrity
   - Test with production-like data volumes
   - Include rollback plan (new migration)

4. **Deployment**
   - Run migrations before deploying new code
   - Monitor migration execution time
   - Have rollback plan ready
   - Test on staging environment first

5. **Monitoring**
   - Log all migration executions
   - Track migration duration
   - Alert on migration failures
   - Verify schema after migration

## Common Patterns

### Adding a New Feature

```sql
-- Migration_008_AddModeration.sql

-- 1. Add moderation table
CREATE TABLE moderation_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    target TEXT NOT NULL,
    action TEXT NOT NULL,
    reason TEXT,
    created_at DATETIME NOT NULL,
    created_by TEXT NOT NULL
);

CREATE INDEX idx_moderation_target ON moderation_events(target);
CREATE INDEX idx_moderation_created_at ON moderation_events(created_at);

-- 2. Add moderation status to accounts
ALTER TABLE accounts ADD COLUMN moderation_status TEXT DEFAULT 'none';

-- 3. Update schema version
INSERT INTO schema_version (version, applied_at, description)
VALUES (8, datetime('now'), 'Add moderation support');
```

### Optimizing Performance

```sql
-- Migration_009_OptimizeIndexes.sql

-- 1. Add missing indexes
CREATE INDEX idx_records_indexed_at ON records(indexed_at);
CREATE INDEX idx_ipld_blocks_size ON ipld_blocks(size);

-- 2. Analyze table statistics
ANALYZE;

-- 3. Update schema version
INSERT INTO schema_version (version, applied_at, description)
VALUES (9, datetime('now'), 'Add performance indexes');
```

## Migration Checklist

Before deploying a migration:

- [ ] Migration is tested on staging database
- [ ] Data is backed up
- [ ] Rollback plan is documented
- [ ] Migration duration is acceptable
- [ ] Schema integrity is verified
- [ ] Indexes are created
- [ ] Statistics are updated
- [ ] Monitoring is in place

## See Also

**Basic Topics:**
- [Service Databases](service-databases) — Shared database
- [Actor Databases](actor-databases) — Per-user databases
- [WAL Mode](wal-mode) — Write-Ahead Logging
- [SQLite Architecture](sqlite-architecture) — Database design

**Advanced Topics:**
- [Migration Strategy](migration-strategy) — Planning migrations
- [Migration Rollback](migration-rollback) — Rollback procedures
- [Data Integrity](data-integrity) — Consistency checks
- [Zero-Downtime Migrations](zero-downtime-migrations) — Online migrations

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)

