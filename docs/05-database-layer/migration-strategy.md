# Database Migration Strategy

## Overview

The PDS uses a structured migration strategy to evolve database schemas safely over time. This document covers versioning approaches, compatibility considerations, and migration planning strategies.

## Schema Versioning

### Version Tracking

Each database maintains its schema version in a dedicated table:

```sql
CREATE TABLE schema_version (
    version INTEGER PRIMARY KEY,
    applied_at DATETIME NOT NULL,
    description TEXT
);
```

**Source:** `ATProtoPDS/Sources/Database/Schema/PDSSchemaManager.m`

### Version Numbering

Migrations use sequential integer versioning:

```
Version 1: Initial schema
Version 2: Add invite codes table
Version 3: Add refresh tokens table
Version 4: Add JWT signing keys table
Version 5: Add DID cache table
...
```

Each migration increments the version number by 1, ensuring a clear upgrade path.

### Checking Current Version

```objc
// Query current schema version
- (NSInteger)currentSchemaVersion:(PDSDatabase *)database error:(NSError **)error {
    NSString *query = @"SELECT MAX(version) FROM schema_version";
    NSArray *results = [database executeQuery:query error:error];
    
    if (results.count > 0) {
        return [results[0][@"version"] integerValue];
    }
    
    return 0; // No schema version found
}
```

## Migration Types

### Additive Migrations

Additive migrations add new tables, columns, or indexes without modifying existing structures. These are the safest type of migration.

#### Adding a New Table

```sql
-- Migration 004: Add labels table
CREATE TABLE IF NOT EXISTS labels (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    target TEXT NOT NULL,
    label TEXT NOT NULL,
    created_at DATETIME NOT NULL,
    created_by TEXT NOT NULL,
    UNIQUE(target, label)
);

CREATE INDEX idx_labels_target ON labels(target);
CREATE INDEX idx_labels_label ON labels(label);

INSERT INTO schema_version (version, applied_at, description)
VALUES (4, datetime('now'), 'Add labels table');
```

#### Adding a Column

```sql
-- Migration 005: Add account status column
ALTER TABLE accounts ADD COLUMN status TEXT DEFAULT 'active';

INSERT INTO schema_version (version, applied_at, description)
VALUES (5, datetime('now'), 'Add account status column');
```

**Key Points:**
- Always use `DEFAULT` values for new columns
- Ensures existing rows have valid data
- No data transformation required

### Transformative Migrations

Transformative migrations modify existing data structures or content. These require careful planning and testing.

#### Data Normalization

```sql
-- Migration 006: Normalize handles to lowercase
UPDATE accounts SET handle = LOWER(handle);

INSERT INTO schema_version (version, applied_at, description)
VALUES (6, datetime('now'), 'Normalize handles to lowercase');
```

#### Column Renaming (SQLite Workaround)

SQLite doesn't support direct column renaming. Use the table recreation pattern:

```sql
-- Migration 007: Rename status to account_status

-- 1. Create new table with correct schema
CREATE TABLE accounts_new (
    did TEXT PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    handle TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    account_status TEXT DEFAULT 'active'  -- renamed column
);

-- 2. Copy data from old table
INSERT INTO accounts_new 
SELECT did, email, handle, password_hash, created_at, updated_at, status
FROM accounts;

-- 3. Drop old table
DROP TABLE accounts;

-- 4. Rename new table
ALTER TABLE accounts_new RENAME TO accounts;

-- 5. Recreate indexes
CREATE INDEX idx_accounts_email ON accounts(email);
CREATE INDEX idx_accounts_handle ON accounts(handle);

-- 6. Update version
INSERT INTO schema_version (version, applied_at, description)
VALUES (7, datetime('now'), 'Rename status column to account_status');
```

### Destructive Migrations

Destructive migrations remove tables, columns, or data. These are high-risk and should be avoided when possible.

#### Dropping a Column

```sql
-- Migration 008: Remove deprecated column

-- SQLite requires table recreation to drop columns
CREATE TABLE accounts_new (
    did TEXT PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    handle TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL
    -- deprecated_field removed
);

INSERT INTO accounts_new 
SELECT did, email, handle, password_hash, created_at, updated_at
FROM accounts;

DROP TABLE accounts;
ALTER TABLE accounts_new RENAME TO accounts;

-- Recreate indexes
CREATE INDEX idx_accounts_email ON accounts(email);
CREATE INDEX idx_accounts_handle ON accounts(handle);

INSERT INTO schema_version (version, applied_at, description)
VALUES (8, datetime('now'), 'Remove deprecated field');
```

## Forward Compatibility

Forward compatibility ensures older code can work with newer database schemas.

### Design Principles

1. **Additive Changes Only**: Add new tables/columns rather than modifying existing ones
2. **Optional Columns**: New columns should have DEFAULT values or allow NULL
3. **Preserve Existing APIs**: Don't change the meaning of existing columns
4. **Graceful Degradation**: Older code ignores new columns it doesn't understand

### Example: Forward-Compatible Column Addition

```sql
-- Migration 009: Add optional profile_image column
ALTER TABLE accounts ADD COLUMN profile_image TEXT DEFAULT NULL;

INSERT INTO schema_version (version, applied_at, description)
VALUES (9, datetime('now'), 'Add optional profile image');
```

Older code that doesn't know about `profile_image` will:
- Successfully read accounts (ignoring the new column)
- Successfully write accounts (column gets NULL or DEFAULT value)
- Continue functioning without errors

### Code Pattern for Forward Compatibility

```objc
// Older code reading accounts
- (PDSAccount *)loadAccount:(NSString *)did error:(NSError **)error {
    NSString *query = @"SELECT did, email, handle, password_hash, created_at, updated_at "
                      @"FROM accounts WHERE did = ?";
    NSArray *results = [self.database executeQuery:query withParameters:@[did] error:error];
    
    if (results.count == 0) {
        return nil;
    }
    
    NSDictionary *row = results[0];
    PDSAccount *account = [[PDSAccount alloc] init];
    account.did = row[@"did"];
    account.email = row[@"email"];
    account.handle = row[@"handle"];
    // ... other fields
    
    // New profile_image column is ignored by older code
    return account;
}
```

## Backward Compatibility

Backward compatibility ensures newer code can work with older database schemas.

### Design Principles

1. **Check Column Existence**: Verify columns exist before using them
2. **Provide Defaults**: Handle missing columns gracefully
3. **Conditional Logic**: Use different code paths based on schema version
4. **Fallback Behavior**: Degrade gracefully when features aren't available

### Example: Backward-Compatible Column Access

```objc
// Newer code that handles both old and new schemas
- (PDSAccount *)loadAccount:(NSString *)did error:(NSError **)error {
    // Check if profile_image column exists
    BOOL hasProfileImage = [self columnExists:@"profile_image" inTable:@"accounts"];
    
    NSString *query;
    if (hasProfileImage) {
        query = @"SELECT did, email, handle, password_hash, created_at, updated_at, profile_image "
                @"FROM accounts WHERE did = ?";
    } else {
        query = @"SELECT did, email, handle, password_hash, created_at, updated_at "
                @"FROM accounts WHERE did = ?";
    }
    
    NSArray *results = [self.database executeQuery:query withParameters:@[did] error:error];
    
    if (results.count == 0) {
        return nil;
    }
    
    NSDictionary *row = results[0];
    PDSAccount *account = [[PDSAccount alloc] init];
    account.did = row[@"did"];
    account.email = row[@"email"];
    account.handle = row[@"handle"];
    // ... other fields
    
    // Only set profile_image if column exists
    if (hasProfileImage && row[@"profile_image"] != [NSNull null]) {
        account.profileImage = row[@"profile_image"];
    }
    
    return account;
}

// Helper method to check column existence
- (BOOL)columnExists:(NSString *)columnName inTable:(NSString *)tableName {
    NSString *query = @"PRAGMA table_info(?)";
    NSArray *results = [self.database executeQuery:query withParameters:@[tableName] error:nil];
    
    for (NSDictionary *row in results) {
        if ([row[@"name"] isEqualToString:columnName]) {
            return YES;
        }
    }
    
    return NO;
}
```

### Version-Based Conditional Logic

```objc
// Execute different logic based on schema version
- (void)performOperation:(NSError **)error {
    NSInteger version = [self currentSchemaVersion:self.database error:error];
    
    if (version >= 9) {
        // Use new profile_image feature
        [self updateProfileImage:@"https://example.com/image.jpg" error:error];
    } else {
        // Fall back to older behavior
        PDS_LOG_DB_INFO(@"Profile images not supported in schema version %ld", (long)version);
    }
}
```

## Migration Planning

### Pre-Migration Checklist

Before deploying a migration:

- [ ] **Backup Database**: Always backup before migration
- [ ] **Test on Staging**: Run migration on staging environment
- [ ] **Measure Duration**: Time the migration with production-like data
- [ ] **Review Rollback Plan**: Document how to revert if needed
- [ ] **Check Disk Space**: Ensure sufficient space for migration
- [ ] **Verify Indexes**: Confirm indexes will be recreated
- [ ] **Test Compatibility**: Verify old and new code work with migrated schema

### Migration Execution Flow

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
5. Update statistics (ANALYZE)
   ↓
6. Report success/failure
```

### Batch Migration Pattern

**Source:** `ATProtoPDS/Sources/Database/Migration/PDSMigrationManager.m` (Lines 100-130)

```objc
// Migrate accounts in batches for better performance
const NSUInteger batchSize = 100;
for (NSUInteger i = 0; i < allAccounts.count; i += batchSize) {
    if (self.cancelBlock && self.cancelBlock()) {
        // Migration cancelled
        return NO;
    }

    NSUInteger endIndex = MIN(i + batchSize, allAccounts.count);
    NSArray<PDSDatabaseAccount *> *batch = [allAccounts subarrayWithRange:NSMakeRange(i, endIndex - i)];

    NSError *createError = nil;
    BOOL batchSuccess = [serviceDb createAccounts:batch error:&createError];
    if (!batchSuccess) {
        PDS_LOG_DB_ERROR(@"Migration failed to create account batch: %@", createError);
        return NO;
    }

    // Update progress
    [self updateProgress:(0.1 + 0.3 * ((double)(i + batch.count) / allAccounts.count))
                  status:[NSString stringWithFormat:@"Migrating accounts (%lu/%lu)", 
                         (unsigned long)(i + batch.count), (unsigned long)allAccounts.count]];
}
```

**Key Benefits:**
- Reduces memory usage for large datasets
- Provides progress feedback
- Allows cancellation between batches
- Improves transaction performance

## Multi-Database Migration

The PDS uses separate databases for service-level and per-actor data. Migrations must handle both types.

### Service Database Migration

```objc
// Migrate shared service database
- (BOOL)migrateServiceDatabase:(PDSServiceDatabases *)serviceDb error:(NSError **)error {
    NSInteger currentVersion = [self currentSchemaVersion:serviceDb.database error:error];
    NSInteger targetVersion = [self latestSchemaVersion];
    
    for (NSInteger version = currentVersion + 1; version <= targetVersion; version++) {
        NSString *migrationSQL = [self migrationSQLForVersion:version];
        
        BOOL success = [serviceDb.database executeSQL:migrationSQL error:error];
        if (!success) {
            return NO;
        }
        
        // Update version
        NSString *updateSQL = @"INSERT INTO schema_version (version, applied_at, description) "
                              @"VALUES (?, datetime('now'), ?)";
        [serviceDb.database executeSQL:updateSQL 
                        withParameters:@[@(version), [self descriptionForVersion:version]]
                                 error:error];
    }
    
    return YES;
}
```

### Actor Database Migration

```objc
// Migrate per-actor databases
- (BOOL)migrateActorDatabases:(PDSDatabasePool *)pool error:(NSError **)error {
    NSArray<NSString *> *allDIDs = [pool allDIDs];
    
    for (NSString *did in allDIDs) {
        PDSActorStore *store = [pool storeForDID:did error:error];
        if (!store) {
            continue;
        }
        
        NSInteger currentVersion = [self currentSchemaVersion:store.database error:error];
        NSInteger targetVersion = [self latestActorSchemaVersion];
        
        for (NSInteger version = currentVersion + 1; version <= targetVersion; version++) {
            NSString *migrationSQL = [self actorMigrationSQLForVersion:version];
            
            BOOL success = [store.database executeSQL:migrationSQL error:error];
            if (!success) {
                PDS_LOG_DB_ERROR(@"Failed to migrate actor database for %@: %@", did, *error);
                return NO;
            }
            
            // Update version
            NSString *updateSQL = @"INSERT INTO schema_version (version, applied_at, description) "
                                  @"VALUES (?, datetime('now'), ?)";
            [store.database executeSQL:updateSQL 
                            withParameters:@[@(version), [self actorDescriptionForVersion:version]]
                                     error:error];
        }
    }
    
    return YES;
}
```

## Migration Testing

### Unit Test Pattern

```objc
- (void)testMigrationFromVersion1ToVersion2 {
    // Create database at version 1
    PDSDatabase *db = [self createDatabaseAtVersion:1];
    
    // Insert test data
    [db executeSQL:@"INSERT INTO accounts (did, email, handle, password_hash, created_at, updated_at) "
                   @"VALUES ('did:plc:test', 'test@example.com', 'test', 'hash', datetime('now'), datetime('now'))"
             error:nil];
    
    // Run migration to version 2
    PDSMigrationManager *manager = [PDSMigrationManager sharedManager];
    NSError *error = nil;
    BOOL success = [manager migrateDatabase:db toVersion:2 error:&error];
    
    XCTAssertTrue(success, @"Migration should succeed");
    XCTAssertNil(error, @"No error should occur");
    
    // Verify schema version
    NSInteger version = [manager currentSchemaVersion:db error:nil];
    XCTAssertEqual(version, 2, @"Schema version should be 2");
    
    // Verify data is preserved
    NSArray *results = [db executeQuery:@"SELECT * FROM accounts WHERE did = 'did:plc:test'" error:nil];
    XCTAssertEqual(results.count, 1, @"Account should still exist");
    
    // Verify new table exists
    NSArray *tables = [db executeQuery:@"SELECT name FROM sqlite_master WHERE type='table' AND name='invite_codes'" error:nil];
    XCTAssertEqual(tables.count, 1, @"invite_codes table should exist");
}
```

### Integration Test Pattern

```objc
- (void)testFullMigrationPath {
    // Create database at version 1
    PDSDatabase *db = [self createDatabaseAtVersion:1];
    
    // Insert test data at each version
    [self insertTestDataForVersion:1 inDatabase:db];
    
    // Migrate through all versions
    PDSMigrationManager *manager = [PDSMigrationManager sharedManager];
    NSInteger targetVersion = [manager latestSchemaVersion];
    
    for (NSInteger version = 2; version <= targetVersion; version++) {
        NSError *error = nil;
        BOOL success = [manager migrateDatabase:db toVersion:version error:&error];
        
        XCTAssertTrue(success, @"Migration to version %ld should succeed", (long)version);
        XCTAssertNil(error, @"No error should occur at version %ld", (long)version);
        
        // Verify data integrity after each migration
        [self verifyDataIntegrityAtVersion:version inDatabase:db];
    }
    
    // Verify final schema
    NSInteger finalVersion = [manager currentSchemaVersion:db error:nil];
    XCTAssertEqual(finalVersion, targetVersion, @"Should be at latest version");
}
```

## Best Practices

### 1. Keep Migrations Small

Each migration should focus on a single logical change:

```sql
-- Good: Single focused change
-- Migration 010: Add email verification
ALTER TABLE accounts ADD COLUMN email_verified INTEGER DEFAULT 0;
INSERT INTO schema_version (version, applied_at, description)
VALUES (10, datetime('now'), 'Add email verification');
```

```sql
-- Bad: Multiple unrelated changes
-- Migration 010: Various updates
ALTER TABLE accounts ADD COLUMN email_verified INTEGER DEFAULT 0;
ALTER TABLE accounts ADD COLUMN phone_number TEXT;
CREATE TABLE notifications (...);
-- Too many changes in one migration
```

### 2. Use Transactions

Always wrap migrations in transactions:

```objc
- (BOOL)executeMigration:(NSString *)sql error:(NSError **)error {
    [self.database beginTransaction];
    
    BOOL success = [self.database executeSQL:sql error:error];
    
    if (success) {
        [self.database commitTransaction];
    } else {
        [self.database rollbackTransaction];
    }
    
    return success;
}
```

### 3. Validate Before Migrating

```objc
- (BOOL)validateBeforeMigration:(NSError **)error {
    // Check disk space
    if (![self hasSufficientDiskSpace]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                        code:PDSMigrationErrorInsufficientSpace
                                    userInfo:@{NSLocalizedDescriptionKey: @"Insufficient disk space"}];
        }
        return NO;
    }
    
    // Check database integrity
    if (![self.database checkIntegrity:error]) {
        return NO;
    }
    
    // Verify backup exists
    if (![self hasRecentBackup]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                        code:PDSMigrationErrorNoBackup
                                    userInfo:@{NSLocalizedDescriptionKey: @"No recent backup found"}];
        }
        return NO;
    }
    
    return YES;
}
```

### 4. Document Migration Impact

```objc
// Migration metadata
typedef struct {
    NSInteger version;
    NSString *description;
    NSTimeInterval estimatedDuration;  // seconds
    BOOL requiresDowntime;
    NSString *rollbackProcedure;
} PDSMigrationMetadata;

- (PDSMigrationMetadata)metadataForVersion:(NSInteger)version {
    switch (version) {
        case 10:
            return (PDSMigrationMetadata){
                .version = 10,
                .description = @"Add email verification",
                .estimatedDuration = 5.0,
                .requiresDowntime = NO,
                .rollbackProcedure = @"Run migration 010_rollback.sql"
            };
        // ... other versions
    }
}
```

### 5. Monitor Migration Progress

```objc
// Progress reporting
- (void)migrateWithProgress:(void (^)(double progress, NSString *status))progressBlock {
    NSInteger totalSteps = [self countMigrationSteps];
    NSInteger currentStep = 0;
    
    for (NSInteger version = currentVersion + 1; version <= targetVersion; version++) {
        NSString *status = [NSString stringWithFormat:@"Migrating to version %ld", (long)version];
        double progress = (double)currentStep / totalSteps;
        
        progressBlock(progress, status);
        
        [self executeMigrationForVersion:version];
        currentStep++;
    }
    
    progressBlock(1.0, @"Migration complete");
}
```

## See Also

- [Migration Rollback](./migration-rollback.md) — Rollback procedures and safety checks
- [Data Integrity](./data-integrity.md) — Verification and consistency checks
- [Zero-Downtime Migrations](./zero-downtime-migrations.md) — Online migration strategies
- [Migrations](./migrations.md) — Basic migration concepts and examples
- [SQLite Architecture](./sqlite-architecture.md) — Database design patterns

