---
title: Migration Rollback Procedures
---

# Migration Rollback Procedures

## Overview

Database migrations in the PDS are designed to be forward-only. When migrations fail or cause issues, explicit rollback procedures manage recovery. Establish safety checks and rollback strategies before deploying changes.

## Rollback Philosophy

### Forward-Only Migrations

The PDS migration system does not support automatic rollback:

```objc
// Rollback is NOT supported automatically
// To revert a migration, create a new migration that undoes the changes
```

**Rationale:**
- Automatic rollback is complex and error-prone
- Data transformations may not be reversible
- Forward migrations with explicit undo steps are more predictable
- Allows testing of rollback procedures before deployment

### Manual Rollback Strategy

Instead of automatic rollback, use:

1. **Database Backups**: Restore from backup if migration fails
2. **Compensating Migrations**: Create new migrations that undo changes
3. **Point-in-Time Recovery**: Use WAL mode for transaction-level recovery
4. **Blue-Green Deployment**: Keep old database version running during migration

## Pre-Migration Safety Checks

### Backup Verification

Always verify backup exists before migration:

```objc
- (BOOL)verifyBackupBeforeMigration:(NSString *)databasePath error:(NSError **)error {
    NSString *backupPath = [self backupPathForDatabase:databasePath];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // Check backup exists
    if (![fm fileExistsAtPath:backupPath]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                        code:PDSMigrationErrorNoBackup
                                    userInfo:@{NSLocalizedDescriptionKey: @"No backup found"}];
        }
        return NO;
    }
    
    // Check backup is recent (within last hour)
    NSDictionary *attrs = [fm attributesOfItemAtPath:backupPath error:error];
    NSDate *backupDate = attrs[NSFileModificationDate];
    NSTimeInterval age = [[NSDate date] timeIntervalSinceDate:backupDate];
    
    if (age > 3600) { // 1 hour
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                        code:PDSMigrationErrorStaleBackup
                                    userInfo:@{NSLocalizedDescriptionKey: @"Backup is too old"}];
        }
        return NO;
    }
    
    // Verify backup integrity
    if (![self verifyDatabaseIntegrity:backupPath error:error]) {
        return NO;
    }
    
    PDS_LOG_DB_INFO(@"Backup verified: %@", backupPath);
    return YES;
}
```

### Disk Space Check

Ensure sufficient disk space for migration:

```objc
- (BOOL)checkDiskSpaceForMigration:(NSString *)databasePath error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // Get database size
    NSDictionary *attrs = [fm attributesOfItemAtPath:databasePath error:error];
    unsigned long long dbSize = [attrs[NSFileSize] unsignedLongLongValue];
    
    // Get available disk space
    NSDictionary *fsAttrs = [fm attributesOfFileSystemForPath:databasePath error:error];
    unsigned long long freeSpace = [fsAttrs[NSFileSystemFreeSize] unsignedLongLongValue];
    
    // Require 3x database size for safety (original + backup + migration temp space)
    unsigned long long requiredSpace = dbSize * 3;
    
    if (freeSpace < requiredSpace) {
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                        code:PDSMigrationErrorInsufficientSpace
                                    userInfo:@{
                                        NSLocalizedDescriptionKey: @"Insufficient disk space",
                                        @"required": @(requiredSpace),
                                        @"available": @(freeSpace)
                                    }];
        }
        return NO;
    }
    
    return YES;
}
```

### Database Integrity Check

Verify database integrity before migration:

```objc
- (BOOL)verifyDatabaseIntegrity:(NSString *)databasePath error:(NSError **)error {
    sqlite3 *db;
    int result = sqlite3_open(databasePath.UTF8String, &db);
    
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to open database"}];
        }
        return NO;
    }
    
    // Run integrity check
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt;
    sqlite3_prepare_v2(db, "PRAGMA integrity_check", -1, &stmt, NULL);
    
    BOOL isIntact = NO;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        const char *result = (const char *)sqlite3_column_text(stmt, 0);
        isIntact = (strcmp(result, "ok") == 0);
    }
    
    sqlite3_close(db);
    
    if (!isIntact) {
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                        code:PDSMigrationErrorCorruptDatabase
                                    userInfo:@{NSLocalizedDescriptionKey: @"Database integrity check failed"}];
        }
        return NO;
    }
    
    return YES;
}
```

## Backup Strategies

### Full Database Backup

Create a complete copy before migration:

```objc
- (BOOL)createBackup:(NSString *)databasePath error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // Generate backup path with timestamp
    NSString *timestamp = [self timestampString];
    NSString *backupPath = [NSString stringWithFormat:@"%@.backup-%@", databasePath, timestamp];
    
    // For SQLite with WAL mode, must backup all files
    NSArray *extensions = @[@"", @"-wal", @"-shm"];
    
    for (NSString *ext in extensions) {
        NSString *sourcePath = [databasePath stringByAppendingString:ext];
        NSString *destPath = [backupPath stringByAppendingString:ext];
        
        if ([fm fileExistsAtPath:sourcePath]) {
            if (![fm copyItemAtPath:sourcePath toPath:destPath error:error]) {
                PDS_LOG_DB_ERROR(@"Failed to backup %@: %@", sourcePath, *error);
                return NO;
            }
        }
    }
    
    PDS_LOG_DB_INFO(@"Created backup: %@", backupPath);
    return YES;
}

- (NSString *)timestampString {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyyMMdd-HHmmss";
    return [formatter stringFromDate:[NSDate date]];
}
```

### Online Backup (SQLite API)

Use SQLite's online backup API for consistent backups:

```objc
- (BOOL)createOnlineBackup:(NSString *)sourcePath 
                    toPath:(NSString *)destPath 
                     error:(NSError **)error {
    sqlite3 *sourceDb = NULL;
    sqlite3 *destDb = NULL;
    
    // Open source database
    int result = sqlite3_open(sourcePath.UTF8String, &sourceDb);
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to open source database"}];
        }
        return NO;
    }
    
    // Create destination database
    result = sqlite3_open(destPath.UTF8String, &destDb);
    if (result != SQLITE_OK) {
        sqlite3_close(sourceDb);
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to create backup database"}];
        }
        return NO;
    }
    
    // Perform online backup
    sqlite3_backup *backup = sqlite3_backup_init(destDb, "main", sourceDb, "main");
    if (backup == NULL) {
        sqlite3_close(sourceDb);
        sqlite3_close(destDb);
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                        code:PDSMigrationErrorBackupFailed
                                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to initialize backup"}];
        }
        return NO;
    }
    
    // Copy all pages
    result = sqlite3_backup_step(backup, -1);
    sqlite3_backup_finish(backup);
    
    sqlite3_close(sourceDb);
    sqlite3_close(destDb);
    
    if (result != SQLITE_DONE) {
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: @"Backup failed"}];
        }
        return NO;
    }
    
    PDS_LOG_DB_INFO(@"Online backup completed: %@", destPath);
    return YES;
}
```

## Rollback Procedures

### Restore from Backup

If migration fails, restore from backup:

```objc
- (BOOL)restoreFromBackup:(NSString *)backupPath 
               toDatabase:(NSString *)databasePath 
                    error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // Close any open connections to database
    [self closeAllConnections:databasePath];
    
    // Remove current database files
    NSArray *extensions = @[@"", @"-wal", @"-shm"];
    for (NSString *ext in extensions) {
        NSString *path = [databasePath stringByAppendingString:ext];
        if ([fm fileExistsAtPath:path]) {
            if (![fm removeItemAtPath:path error:error]) {
                PDS_LOG_DB_ERROR(@"Failed to remove %@: %@", path, *error);
                return NO;
            }
        }
    }
    
    // Restore backup files
    for (NSString *ext in extensions) {
        NSString *sourcePath = [backupPath stringByAppendingString:ext];
        NSString *destPath = [databasePath stringByAppendingString:ext];
        
        if ([fm fileExistsAtPath:sourcePath]) {
            if (![fm copyItemAtPath:sourcePath toPath:destPath error:error]) {
                PDS_LOG_DB_ERROR(@"Failed to restore %@: %@", sourcePath, *error);
                return NO;
            }
        }
    }
    
    // Verify restored database
    if (![self verifyDatabaseIntegrity:databasePath error:error]) {
        return NO;
    }
    
    PDS_LOG_DB_INFO(@"Restored database from backup: %@", backupPath);
    return YES;
}
```

### Compensating Migration

Create a new migration that undoes changes:

```sql
-- Original Migration 010: Add email verification
ALTER TABLE accounts ADD COLUMN email_verified INTEGER DEFAULT 0;
INSERT INTO schema_version (version, applied_at, description)
VALUES (10, datetime('now'), 'Add email verification');
```

```sql
-- Compensating Migration 011: Remove email verification
-- SQLite requires table recreation to drop columns

CREATE TABLE accounts_new (
    did TEXT PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    handle TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL
    -- email_verified column removed
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
VALUES (11, datetime('now'), 'Rollback: Remove email verification');
```

### Compensating Migration Pattern

```objc
- (NSString *)compensatingMigrationForVersion:(NSInteger)version {
    switch (version) {
        case 10: // Undo "Add email verification"
            return @"CREATE TABLE accounts_new (...); "
                   @"INSERT INTO accounts_new SELECT did, email, handle, password_hash, created_at, updated_at FROM accounts; "
                   @"DROP TABLE accounts; "
                   @"ALTER TABLE accounts_new RENAME TO accounts; "
                   @"CREATE INDEX idx_accounts_email ON accounts(email); "
                   @"CREATE INDEX idx_accounts_handle ON accounts(handle);";
            
        case 9: // Undo "Add profile image"
            return @"CREATE TABLE accounts_new (...); "
                   @"INSERT INTO accounts_new SELECT did, email, handle, password_hash, created_at, updated_at FROM accounts; "
                   @"DROP TABLE accounts; "
                   @"ALTER TABLE accounts_new RENAME TO accounts;";
            
        default:
            return nil;
    }
}

- (BOOL)rollbackToVersion:(NSInteger)targetVersion error:(NSError **)error {
    NSInteger currentVersion = [self currentSchemaVersion:self.database error:error];
    
    if (targetVersion >= currentVersion) {
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                        code:PDSMigrationErrorInvalidVersion
                                    userInfo:@{NSLocalizedDescriptionKey: @"Target version must be less than current version"}];
        }
        return NO;
    }
    
    // Apply compensating migrations in reverse order
    for (NSInteger version = currentVersion; version > targetVersion; version--) {
        NSString *compensatingSQL = [self compensatingMigrationForVersion:version];
        
        if (!compensatingSQL) {
            if (error) {
                *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                            code:PDSMigrationErrorNoCompensatingMigration
                                        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"No compensating migration for version %ld", (long)version]}];
            }
            return NO;
        }
        
        BOOL success = [self.database executeSQL:compensatingSQL error:error];
        if (!success) {
            return NO;
        }
        
        // Update schema version
        NSString *updateSQL = @"UPDATE schema_version SET version = ? WHERE version = ?";
        [self.database executeSQL:updateSQL withParameters:@[@(version - 1), @(version)] error:error];
    }
    
    return YES;
}
```

## Transaction Rollback

### Automatic Transaction Rollback

Migrations use transactions for automatic rollback on failure:

```objc
- (BOOL)executeMigrationWithRollback:(NSString *)sql error:(NSError **)error {
    // Begin transaction
    if (![self.database executeSQL:@"BEGIN TRANSACTION" error:error]) {
        return NO;
    }
    
    // Execute migration
    BOOL success = [self.database executeSQL:sql error:error];
    
    if (success) {
        // Commit on success
        if (![self.database executeSQL:@"COMMIT" error:error]) {
            [self.database executeSQL:@"ROLLBACK" error:nil];
            return NO;
        }
        PDS_LOG_DB_INFO(@"Migration committed successfully");
    } else {
        // Rollback on failure
        [self.database executeSQL:@"ROLLBACK" error:nil];
        PDS_LOG_DB_ERROR(@"Migration failed, rolled back: %@", *error);
    }
    
    return success;
}
```

### Savepoint-Based Rollback

Use savepoints for partial rollback:

```objc
- (BOOL)executeMigrationWithSavepoints:(NSArray<NSString *> *)migrations error:(NSError **)error {
    // Begin transaction
    if (![self.database executeSQL:@"BEGIN TRANSACTION" error:error]) {
        return NO;
    }
    
    for (NSInteger i = 0; i < migrations.count; i++) {
        NSString *migration = migrations[i];
        NSString *savepointName = [NSString stringWithFormat:@"migration_%ld", (long)i];
        
        // Create savepoint
        NSString *savepointSQL = [NSString stringWithFormat:@"SAVEPOINT %@", savepointName];
        if (![self.database executeSQL:savepointSQL error:error]) {
            [self.database executeSQL:@"ROLLBACK" error:nil];
            return NO;
        }
        
        // Execute migration step
        BOOL success = [self.database executeSQL:migration error:error];
        
        if (!success) {
            // Rollback to savepoint
            NSString *rollbackSQL = [NSString stringWithFormat:@"ROLLBACK TO SAVEPOINT %@", savepointName];
            [self.database executeSQL:rollbackSQL error:nil];
            [self.database executeSQL:@"ROLLBACK" error:nil];
            
            PDS_LOG_DB_ERROR(@"Migration step %ld failed, rolled back to savepoint", (long)i);
            return NO;
        }
        
        // Release savepoint
        NSString *releaseSQL = [NSString stringWithFormat:@"RELEASE SAVEPOINT %@", savepointName];
        [self.database executeSQL:releaseSQL error:nil];
    }
    
    // Commit all changes
    if (![self.database executeSQL:@"COMMIT" error:error]) {
        [self.database executeSQL:@"ROLLBACK" error:nil];
        return NO;
    }
    
    return YES;
}
```

## WAL Mode Recovery

### Point-in-Time Recovery

WAL mode enables point-in-time recovery:

```objc
- (BOOL)recoverToCheckpoint:(NSString *)databasePath error:(NSError **)error {
    sqlite3 *db;
    int result = sqlite3_open(databasePath.UTF8String, &db);
    
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to open database"}];
        }
        return NO;
    }
    
    // Checkpoint WAL to main database
    result = sqlite3_wal_checkpoint_v2(db, NULL, SQLITE_CHECKPOINT_TRUNCATE, NULL, NULL);
    
    sqlite3_close(db);
    
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to checkpoint WAL"}];
        }
        return NO;
    }
    
    PDS_LOG_DB_INFO(@"Recovered to checkpoint: %@", databasePath);
    return YES;
}
```

### WAL Truncation

Truncate WAL file to discard uncommitted changes:

```objc
- (BOOL)truncateWAL:(NSString *)databasePath error:(NSError **)error {
    NSString *walPath = [databasePath stringByAppendingString:@"-wal"];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if ([fm fileExistsAtPath:walPath]) {
        if (![fm removeItemAtPath:walPath error:error]) {
            PDS_LOG_DB_ERROR(@"Failed to remove WAL file: %@", *error);
            return NO;
        }
    }
    
    NSString *shmPath = [databasePath stringByAppendingString:@"-shm"];
    if ([fm fileExistsAtPath:shmPath]) {
        if (![fm removeItemAtPath:shmPath error:error]) {
            PDS_LOG_DB_ERROR(@"Failed to remove SHM file: %@", *error);
            return NO;
        }
    }
    
    PDS_LOG_DB_INFO(@"Truncated WAL: %@", databasePath);
    return YES;
}
```

## Failure Recovery

### Migration Failure Handling

```objc
- (BOOL)handleMigrationFailure:(NSError *)migrationError 
                   forDatabase:(NSString *)databasePath 
                         error:(NSError **)error {
    PDS_LOG_DB_ERROR(@"Migration failed: %@", migrationError);
    
    // 1. Attempt transaction rollback
    [self.database executeSQL:@"ROLLBACK" error:nil];
    
    // 2. Check database integrity
    if (![self verifyDatabaseIntegrity:databasePath error:error]) {
        PDS_LOG_DB_ERROR(@"Database corrupted after migration failure");
        
        // 3. Restore from backup
        NSString *backupPath = [self mostRecentBackupForDatabase:databasePath];
        if (backupPath) {
            if ([self restoreFromBackup:backupPath toDatabase:databasePath error:error]) {
                PDS_LOG_DB_INFO(@"Restored from backup after migration failure");
                return YES;
            }
        }
        
        // 4. If restore fails, database is unrecoverable
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                        code:PDSMigrationErrorUnrecoverable
                                    userInfo:@{
                                        NSLocalizedDescriptionKey: @"Database unrecoverable after migration failure",
                                        NSUnderlyingErrorKey: migrationError
                                    }];
        }
        return NO;
    }
    
    // Database integrity OK, migration can be retried
    PDS_LOG_DB_INFO(@"Database intact after migration failure, can retry");
    return YES;
}
```

### Partial Migration Recovery

```objc
- (BOOL)recoverFromPartialMigration:(NSInteger)targetVersion error:(NSError **)error {
    NSInteger currentVersion = [self currentSchemaVersion:self.database error:error];
    
    if (currentVersion < targetVersion) {
        // Migration was interrupted
        PDS_LOG_DB_INFO(@"Partial migration detected: current=%ld, target=%ld", 
                        (long)currentVersion, (long)targetVersion);
        
        // Verify database integrity
        if (![self verifyDatabaseIntegrity:self.database.path error:error]) {
            // Database corrupted, restore from backup
            NSString *backupPath = [self mostRecentBackupForDatabase:self.database.path];
            return [self restoreFromBackup:backupPath toDatabase:self.database.path error:error];
        }
        
        // Database intact, resume migration
        PDS_LOG_DB_INFO(@"Resuming migration from version %ld", (long)currentVersion);
        return [self migrateToVersion:targetVersion error:error];
    }
    
    return YES;
}
```

## Testing Rollback Procedures

### Rollback Test Pattern

```objc
- (void)testMigrationRollback {
    // Create database at version 1
    PDSDatabase *db = [self createDatabaseAtVersion:1];
    
    // Insert test data
    [db executeSQL:@"INSERT INTO accounts (did, email, handle, password_hash, created_at, updated_at) "
                   @"VALUES ('did:plc:test', 'test@example.com', 'test', 'hash', datetime('now'), datetime('now'))"
             error:nil];
    
    // Create backup
    NSString *backupPath = [self createBackup:db.path error:nil];
    
    // Attempt migration (simulate failure)
    PDSMigrationManager *manager = [PDSMigrationManager sharedManager];
    NSError *error = nil;
    BOOL success = [manager migrateDatabase:db toVersion:2 error:&error];
    
    // Simulate migration failure
    if (!success) {
        // Restore from backup
        BOOL restored = [manager restoreFromBackup:backupPath toDatabase:db.path error:&error];
        XCTAssertTrue(restored, @"Restore should succeed");
        
        // Verify data is intact
        NSArray *results = [db executeQuery:@"SELECT * FROM accounts WHERE did = 'did:plc:test'" error:nil];
        XCTAssertEqual(results.count, 1, @"Account should still exist after rollback");
        
        // Verify schema version
        NSInteger version = [manager currentSchemaVersion:db error:nil];
        XCTAssertEqual(version, 1, @"Schema version should be 1 after rollback");
    }
}
```

### Compensating Migration Test

```objc
- (void)testCompensatingMigration {
    // Create database at version 1
    PDSDatabase *db = [self createDatabaseAtVersion:1];
    
    // Migrate to version 2
    PDSMigrationManager *manager = [PDSMigrationManager sharedManager];
    [manager migrateDatabase:db toVersion:2 error:nil];
    
    // Verify version 2 schema
    NSInteger version = [manager currentSchemaVersion:db error:nil];
    XCTAssertEqual(version, 2);
    
    // Apply compensating migration
    NSError *error = nil;
    BOOL success = [manager rollbackToVersion:1 error:&error];
    XCTAssertTrue(success, @"Compensating migration should succeed");
    
    // Verify back at version 1
    version = [manager currentSchemaVersion:db error:nil];
    XCTAssertEqual(version, 1, @"Should be back at version 1");
    
    // Verify schema matches original version 1
    [self verifySchemaMatchesVersion:1 inDatabase:db];
}
```

## Best Practices

### 1. Always Create Backups

```objc
- (BOOL)migrateWithBackup:(NSString *)databasePath 
                toVersion:(NSInteger)targetVersion 
                    error:(NSError **)error {
    // Create backup before migration
    NSString *backupPath = [self createBackup:databasePath error:error];
    if (!backupPath) {
        return NO;
    }
    
    // Attempt migration
    BOOL success = [self migrateDatabase:databasePath toVersion:targetVersion error:error];
    
    if (!success) {
        // Restore from backup on failure
        [self restoreFromBackup:backupPath toDatabase:databasePath error:error];
    }
    
    return success;
}
```

### 2. Test Rollback Procedures

Always test rollback procedures before deploying migrations:

```bash
# Test migration and rollback on staging
./scripts/test-migration.sh --version 10 --test-rollback
```

## 3. Document Rollback Steps

Include rollback instructions in migration metadata:

```objc
// Migration metadata with rollback instructions
- (NSDictionary *)migrationMetadata:(NSInteger)version {
    return @{
        @"version": @(version),
        @"description": @"Add email verification",
        @"rollback_instructions": @"Run compensating migration 011 or restore from backup",
        @"rollback_sql": [self compensatingMigrationForVersion:version]
    };
}
```

### 4. Monitor Migration Progress

Track migration progress to detect failures early:

```objc
- (void)migrateWithMonitoring:(void (^)(NSString *status))statusBlock {
    statusBlock(@"Creating backup...");
    [self createBackup:self.database.path error:nil];
    
    statusBlock(@"Verifying integrity...");
    [self verifyDatabaseIntegrity:self.database.path error:nil];
    
    statusBlock(@"Executing migration...");
    BOOL success = [self executeMigration:error];
    
    if (success) {
        statusBlock(@"Migration complete");
    } else {
        statusBlock(@"Migration failed, rolling back...");
        [self handleMigrationFailure:error];
    }
}
```

### 5. Maintain Backup Retention

Keep multiple backup generations:

```objc
- (void)cleanupOldBackups:(NSString *)databasePath {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *directory = [databasePath stringByDeletingLastPathComponent];
    NSString *filename = [databasePath lastPathComponent];
    
    // Find all backups
    NSArray *contents = [fm contentsOfDirectoryAtPath:directory error:nil];
    NSMutableArray *backups = [NSMutableArray array];
    
    for (NSString *file in contents) {
        if ([file hasPrefix:filename] && [file containsString:@".backup-"]) {
            [backups addObject:file];
        }
    }
    
    // Sort by date (newest first)
    [backups sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [b compare:a];
    }];
    
    // Keep only last 5 backups
    const NSUInteger maxBackups = 5;
    if (backups.count > maxBackups) {
        for (NSUInteger i = maxBackups; i < backups.count; i++) {
            NSString *path = [directory stringByAppendingPathComponent:backups[i]];
            [fm removeItemAtPath:path error:nil];
            PDS_LOG_DB_INFO(@"Removed old backup: %@", backups[i]);
        }
    }
}
```

## See Also

- [Migration Strategy](migration-strategy) — Versioning and compatibility
- [Data Integrity](data-integrity) — Verification and consistency checks
- [Zero-Downtime Migrations](zero-downtime-migrations) — Online migration strategies
- [WAL Mode](wal-mode) — Write-Ahead Logging benefits
- [SQLite Architecture](sqlite-architecture) — Database design patterns

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)

