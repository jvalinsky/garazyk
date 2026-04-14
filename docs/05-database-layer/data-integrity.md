---
title: Data Integrity Verification
---

# Data Integrity Verification

## Overview

Data integrity is critical for a PDS. This document covers verification strategies, consistency checks, repair procedures, and monitoring approaches to ensure database reliability.

## Integrity Check Types

### SQLite Integrity Check

The primary integrity verification uses SQLite's built-in `PRAGMA integrity_check`:

**Source:** `Garazyk/Sources/Database/Monitoring/PDSHealthCheck.m` (Lines 60-90)

```objc
- (PDSHealthStatus)checkDatabaseIntegrity:(NSError **)error {
    PDSServiceDatabases *serviceDb = [PDSServiceDatabases sharedInstance];
    PDSActorStore *store = [serviceDb.servicePool storeForDid:@"__service__" error:nil];
    
    if (!store || !store.isOpen) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds.health"
                                        code:-1
                                    userInfo:@{NSLocalizedDescriptionKey: @"Service database not available"}];
        }
        return PDSHealthStatusCritical;
    }
    
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt;
    int result = sqlite3_prepare_v2(store.db, "PRAGMA integrity_check", -1, &stmt, NULL);
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds.health"
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to prepare integrity check"}];
        }
        return PDSHealthStatusCritical;
    }
    
    NSString *checkResult = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        const char *text = (const char *)sqlite3_column_text(stmt, 0);
        checkResult = [NSString stringWithUTF8String:text];
    }
    
    if ([checkResult isEqualToString:@"ok"]) {
        return PDSHealthStatusHealthy;
    } else if ([checkResult.lowercaseString containsString:@"ok"]) {
        return PDSHealthStatusWarning;
    } else {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds.health"
                                        code:-2
                                    userInfo:@{NSLocalizedDescriptionKey: checkResult ?: @"Integrity check failed"}];
        }
        return PDSHealthStatusCritical;
    }
}
```

**What it checks:**
- B-tree structure validity
- Page checksums
- Index consistency
- Freelist integrity


### Foreign Key Constraint Check

Verify referential integrity between tables:

**Source:** `Garazyk/Sources/Database/Monitoring/PDSHealthCheck.m` (Lines 92-120)

```objc
- (BOOL)checkForeignKeys:(NSError **)error {
    PDSServiceDatabases *serviceDb = [PDSServiceDatabases sharedInstance];
    PDSActorStore *store = [serviceDb.servicePool storeForDid:@"__service__" error:nil];
    
    if (!store) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds.health"
                                        code:-1
                                    userInfo:@{NSLocalizedDescriptionKey: @"Service database not available"}];
        }
        return NO;
    }
    
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt;
    int result = sqlite3_prepare_v2(store.db, "PRAGMA foreign_key_check", -1, &stmt, NULL);
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds.health"
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to prepare foreign key check"}];
        }
        return NO;
    }
    
    BOOL hasViolations = NO;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        hasViolations = YES;
        break;
    }
    
    return !hasViolations;
}
```

**What it checks:**
- Foreign key references exist
- No orphaned records
- Referential integrity maintained

### Quick Integrity Check

For faster checks, use `PRAGMA quick_check`:

```sql
PRAGMA quick_check;
```

**Differences from full check:**
- Skips BLOB content verification
- Faster execution (seconds vs minutes)
- Good for routine monitoring
- Use full check for thorough validation

## Consistency Checks

### Repository Consistency

Verify repository data structures are valid:

```objc
- (BOOL)verifyRepositoryConsistency:(NSString *)did error:(NSError **)error {
    PDSActorStore *store = [self.pool storeForDID:did error:error];
    if (!store) {
        return NO;
    }
    
    // 1. Check repo_root exists
    NSString *query = @"SELECT cid FROM repo_root LIMIT 1";
    NSArray *results = [store executeQuery:query error:error];
    if (results.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSIntegrityErrorDomain
                                        code:PDSIntegrityErrorNoRepoRoot
                                    userInfo:@{NSLocalizedDescriptionKey: @"No repo root found"}];
        }
        return NO;
    }
    
    NSData *rootCID = results[0][@"cid"];
    
    // 2. Verify root CID exists in blocks
    query = @"SELECT cid FROM ipld_blocks WHERE cid = ?";
    results = [store executeQuery:query withParameters:@[rootCID] error:error];
    if (results.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSIntegrityErrorDomain
                                        code:PDSIntegrityErrorMissingBlock
                                    userInfo:@{NSLocalizedDescriptionKey: @"Root CID not found in blocks"}];
        }
        return NO;
    }
    
    // 3. Verify all records have corresponding blocks
    query = @"SELECT r.uri, r.cid FROM records r "
            @"LEFT JOIN ipld_blocks b ON r.cid = b.cid "
            @"WHERE b.cid IS NULL";
    results = [store executeQuery:query error:error];
    if (results.count > 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSIntegrityErrorDomain
                                        code:PDSIntegrityErrorOrphanedRecords
                                    userInfo:@{
                                        NSLocalizedDescriptionKey: @"Records without blocks found",
                                        @"count": @(results.count)
                                    }];
        }
        return NO;
    }
    
    return YES;
}
```

### Blob Consistency

Verify blob references are valid:

```objc
- (BOOL)verifyBlobConsistency:(NSString *)did error:(NSError **)error {
    PDSActorStore *store = [self.pool storeForDID:did error:error];
    if (!store) {
        return NO;
    }
    
    // 1. Check for orphaned blobs (no record references)
    NSString *query = @"SELECT b.cid FROM blobs b "
                      @"LEFT JOIN records r ON r.value LIKE '%' || b.cid || '%' "
                      @"WHERE r.uri IS NULL";
    NSArray *orphanedBlobs = [store executeQuery:query error:error];
    
    if (orphanedBlobs.count > 0) {
        PDS_LOG_DB_WARNING(@"Found %lu orphaned blobs for %@", 
                          (unsigned long)orphanedBlobs.count, did);
    }
    
    // 2. Check for missing blobs (record references but no blob)
    query = @"SELECT r.uri, r.value FROM records r "
            @"WHERE r.value LIKE '%\"$type\":\"blob\"%'";
    NSArray *recordsWithBlobs = [store executeQuery:query error:error];
    
    NSMutableArray *missingBlobs = [NSMutableArray array];
    for (NSDictionary *record in recordsWithBlobs) {
        NSData *valueData = record[@"value"];
        NSDictionary *value = [NSJSONSerialization JSONObjectWithData:valueData options:0 error:nil];
        
        // Extract blob CIDs from record value
        NSArray *blobCIDs = [self extractBlobCIDsFromValue:value];
        
        for (NSString *blobCID in blobCIDs) {
            NSString *checkQuery = @"SELECT cid FROM blobs WHERE cid = ?";
            NSArray *results = [store executeQuery:checkQuery withParameters:@[blobCID] error:nil];
            
            if (results.count == 0) {
                [missingBlobs addObject:@{@"uri": record[@"uri"], @"cid": blobCID}];
            }
        }
    }
    
    if (missingBlobs.count > 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSIntegrityErrorDomain
                                        code:PDSIntegrityErrorMissingBlobs
                                    userInfo:@{
                                        NSLocalizedDescriptionKey: @"Missing blob references",
                                        @"missing": missingBlobs
                                    }];
        }
        return NO;
    }
    
    return YES;
}
```

### Account Consistency

Verify account data is consistent:

```objc
- (BOOL)verifyAccountConsistency:(NSError **)error {
    PDSServiceDatabases *serviceDb = [PDSServiceDatabases sharedInstance];
    
    // 1. Check for duplicate handles
    NSString *query = @"SELECT handle, COUNT(*) as count FROM accounts "
                      @"GROUP BY handle HAVING count > 1";
    NSArray *duplicates = [serviceDb executeQuery:query error:error];
    
    if (duplicates.count > 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSIntegrityErrorDomain
                                        code:PDSIntegrityErrorDuplicateHandles
                                    userInfo:@{
                                        NSLocalizedDescriptionKey: @"Duplicate handles found",
                                        @"duplicates": duplicates
                                    }];
        }
        return NO;
    }
    
    // 2. Check for duplicate emails
    query = @"SELECT email, COUNT(*) as count FROM accounts "
            @"WHERE email IS NOT NULL "
            @"GROUP BY email HAVING count > 1";
    duplicates = [serviceDb executeQuery:query error:error];
    
    if (duplicates.count > 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSIntegrityErrorDomain
                                        code:PDSIntegrityErrorDuplicateEmails
                                    userInfo:@{
                                        NSLocalizedDescriptionKey: @"Duplicate emails found",
                                        @"duplicates": duplicates
                                    }];
        }
        return NO;
    }
    
    // 3. Verify all accounts have actor databases
    query = @"SELECT did FROM accounts";
    NSArray *accounts = [serviceDb executeQuery:query error:error];
    
    for (NSDictionary *account in accounts) {
        NSString *did = account[@"did"];
        PDSActorStore *store = [self.pool storeForDID:did error:nil];
        
        if (!store) {
            if (error) {
                *error = [NSError errorWithDomain:PDSIntegrityErrorDomain
                                            code:PDSIntegrityErrorMissingActorDB
                                        userInfo:@{
                                            NSLocalizedDescriptionKey: @"Missing actor database",
                                            @"did": did
                                        }];
            }
            return NO;
        }
    }
    
    return YES;
}
```

## Fragmentation Analysis

### Measuring Fragmentation

**Source:** `Garazyk/Sources/Database/Monitoring/PDSHealthCheck.m` (Lines 150-170)

```objc
- (NSUInteger)getFragmentationPercent {
    PDSServiceDatabases *serviceDb = [PDSServiceDatabases sharedInstance];
    PDSActorStore *store = [serviceDb.servicePool storeForDid:@"__service__" error:nil];
    
    if (!store || !store.isOpen) {
        return 0;
    }
    
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(store.db, 
        "SELECT SUM((leaf_pages - 1) * payload) / SUM(payload) FROM dbstat WHERE name = 'accounts'", 
        -1, &stmt, NULL) != SQLITE_OK) {
        return 0;
    }
    
    double fragmentation = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        fragmentation = sqlite3_column_double(stmt, 0);
    }
    
    return (NSUInteger)(fragmentation * 100);
}
```

### Fragmentation Thresholds

```objc
- (PDSFragmentationLevel)assessFragmentation:(NSUInteger)percent {
    if (percent < 10) {
        return PDSFragmentationLevelLow;
    } else if (percent < 30) {
        return PDSFragmentationLevelModerate;
    } else if (percent < 50) {
        return PDSFragmentationLevelHigh;
    } else {
        return PDSFragmentationLevelCritical;
    }
}
```

**Recommended Actions:**
- **Low (< 10%)**: No action needed
- **Moderate (10-30%)**: Schedule VACUUM during maintenance window
- **High (30-50%)**: VACUUM recommended soon
- **Critical (> 50%)**: VACUUM urgently needed

## Repair Procedures

### VACUUM Operation

Rebuild database to eliminate fragmentation:

```objc
- (BOOL)vacuumDatabase:(NSString *)databasePath error:(NSError **)error {
    sqlite3 *db;
    int result = sqlite3_open(databasePath.UTF8String, &db);
    
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSIntegrityErrorDomain
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to open database"}];
        }
        return NO;
    }
    
    // VACUUM requires exclusive lock and cannot run in transaction
    PDS_LOG_DB_INFO(@"Starting VACUUM on %@", databasePath);
    
    result = sqlite3_exec(db, "VACUUM", NULL, NULL, NULL);
    
    sqlite3_close(db);
    
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSIntegrityErrorDomain
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: @"VACUUM failed"}];
        }
        return NO;
    }
    
    PDS_LOG_DB_INFO(@"VACUUM completed on %@", databasePath);
    return YES;
}
```

**Important Notes:**
- VACUUM requires 2x database size in free disk space
- Database is locked during VACUUM (no writes)
- Can take minutes to hours for large databases
- Always backup before VACUUM

### Incremental VACUUM

For databases that can't afford downtime:

```objc
- (BOOL)incrementalVacuum:(NSString *)databasePath 
                    pages:(NSInteger)pageCount 
                    error:(NSError **)error {
    sqlite3 *db;
    int result = sqlite3_open(databasePath.UTF8String, &db);
    
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSIntegrityErrorDomain
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to open database"}];
        }
        return NO;
    }
    
    // Enable auto_vacuum=incremental if not already set
    sqlite3_exec(db, "PRAGMA auto_vacuum=INCREMENTAL", NULL, NULL, NULL);
    
    // Vacuum specified number of pages
    NSString *sql = [NSString stringWithFormat:@"PRAGMA incremental_vacuum(%ld)", (long)pageCount];
    result = sqlite3_exec(db, sql.UTF8String, NULL, NULL, NULL);
    
    sqlite3_close(db);
    
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSIntegrityErrorDomain
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: @"Incremental VACUUM failed"}];
        }
        return NO;
    }
    
    return YES;
}
```

### REINDEX Operation

Rebuild indexes to fix corruption:

```objc
- (BOOL)reindexDatabase:(NSString *)databasePath error:(NSError **)error {
    sqlite3 *db;
    int result = sqlite3_open(databasePath.UTF8String, &db);
    
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSIntegrityErrorDomain
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to open database"}];
        }
        return NO;
    }
    
    PDS_LOG_DB_INFO(@"Starting REINDEX on %@", databasePath);
    
    result = sqlite3_exec(db, "REINDEX", NULL, NULL, NULL);
    
    sqlite3_close(db);
    
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSIntegrityErrorDomain
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: @"REINDEX failed"}];
        }
        return NO;
    }
    
    PDS_LOG_DB_INFO(@"REINDEX completed on %@", databasePath);
    return YES;
}
```

### ANALYZE Operation

Update query planner statistics:

```objc
- (BOOL)analyzeDatabase:(NSString *)databasePath error:(NSError **)error {
    sqlite3 *db;
    int result = sqlite3_open(databasePath.UTF8String, &db);
    
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSIntegrityErrorDomain
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to open database"}];
        }
        return NO;
    }
    
    // ANALYZE collects statistics for query optimization
    result = sqlite3_exec(db, "ANALYZE", NULL, NULL, NULL);
    
    sqlite3_close(db);
    
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSIntegrityErrorDomain
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: @"ANALYZE failed"}];
        }
        return NO;
    }
    
    return YES;
}
```

## Monitoring and Health Checks

### Comprehensive Health Check

**Source:** `Garazyk/Sources/Database/Monitoring/PDSHealthCheck.m` (Lines 20-60)

```objc
- (NSDictionary<NSString *, id> *)performHealthCheck {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSMutableArray *warnings = [NSMutableArray array];
    NSMutableArray *errors = [NSMutableArray array];
    
    result[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
    result[@"status"] = @"healthy";
    
    // Check database integrity
    NSError *integrityError = nil;
    PDSHealthStatus integrityStatus = [self checkDatabaseIntegrity:&integrityError];
    result[@"database_integrity"] = @(integrityStatus);
    
    if (integrityStatus == PDSHealthStatusCritical) {
        [errors addObject:integrityError.localizedDescription ?: @"Database integrity check failed"];
        result[@"status"] = @"critical";
    } else if (integrityStatus == PDSHealthStatusWarning) {
        [warnings addObject:integrityError.localizedDescription ?: @"Database integrity warning"];
        result[@"status"] = @"warning";
    }
    
    // Get table sizes
    NSDictionary *tableSizes = [self getTableSizes];
    result[@"table_sizes"] = tableSizes;
    
    // Check fragmentation
    NSUInteger fragmentation = [self getFragmentationPercent];
    result[@"fragmentation_percent"] = @(fragmentation);
    
    if (fragmentation > 50) {
        [warnings addObject:[NSString stringWithFormat:@"High fragmentation: %lu%%", (unsigned long)fragmentation]];
    }
    
    // Get pool metrics
    NSDictionary *metrics = [[PDSServiceDatabases sharedInstance].servicePool collectMetrics];
    result[@"pool_metrics"] = metrics;
    
    // Check file handle usage
    NSUInteger openHandles = [metrics[@"open_file_handles"] unsignedIntegerValue];
    NSUInteger maxHandles = [metrics[@"max_size"] unsignedIntegerValue];
    result[@"file_handles"] = @{@"open": @(openHandles), @"max": @(maxHandles)};
    
    if (openHandles >= maxHandles * 0.9) {
        [warnings addObject:@"File handle pool approaching capacity"];
    }
    
    result[@"warnings"] = warnings;
    result[@"errors"] = errors;
    
    return result;
}
```

### Scheduled Integrity Checks

Run integrity checks on a schedule:

```objc
- (void)scheduleIntegrityChecks {
    // Run quick check every hour
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
    
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 3600 * NSEC_PER_SEC, 60 * NSEC_PER_SEC);
    
    dispatch_source_set_event_handler(timer, ^{
        [self performQuickIntegrityCheck];
    });
    
    dispatch_resume(timer);
    self.integrityCheckTimer = timer;
}

- (void)performQuickIntegrityCheck {
    NSError *error = nil;
    
    // Quick check on service database
    if (![self quickCheckDatabase:self.serviceDb.path error:&error]) {
        PDS_LOG_DB_ERROR(@"Quick integrity check failed: %@", error);
        [self notifyIntegrityFailure:error];
    }
    
    // Check fragmentation
    NSUInteger fragmentation = [self getFragmentationPercent];
    if (fragmentation > 50) {
        PDS_LOG_DB_WARNING(@"High fragmentation detected: %lu%%", (unsigned long)fragmentation);
        [self scheduleVacuum];
    }
}
```

### Continuous Monitoring

Monitor database health metrics:

```objc
- (void)startContinuousMonitoring {
    self.monitoringQueue = dispatch_queue_create("com.atproto.pds.db.monitor", DISPATCH_QUEUE_SERIAL);
    
    dispatch_async(self.monitoringQueue, ^{
        while (self.isMonitoring) {
            @autoreleasepool {
                NSDictionary *metrics = [self collectMetrics];
                [self recordMetrics:metrics];
                
                // Check for anomalies
                [self detectAnomalies:metrics];
                
                // Sleep for 60 seconds
                [NSThread sleepForTimeInterval:60.0];
            }
        }
    });
}

- (void)detectAnomalies:(NSDictionary *)metrics {
    // Check for sudden size increases
    NSUInteger currentSize = [metrics[@"database_size"] unsignedIntegerValue];
    NSUInteger previousSize = [self.previousMetrics[@"database_size"] unsignedIntegerValue];
    
    if (currentSize > previousSize * 1.5) {
        PDS_LOG_DB_WARNING(@"Database size increased by 50%% in last minute");
    }
    
    // Check for high error rates
    NSUInteger errorCount = [metrics[@"error_count"] unsignedIntegerValue];
    if (errorCount > 10) {
        PDS_LOG_DB_ERROR(@"High error rate detected: %lu errors", (unsigned long)errorCount);
    }
    
    self.previousMetrics = metrics;
}
```

## Automated Repair

### Self-Healing Database

Automatically repair minor issues:

```objc
- (void)performAutomatedRepair {
    NSError *error = nil;
    
    // 1. Check integrity
    PDSHealthStatus status = [self checkDatabaseIntegrity:&error];
    
    if (status == PDSHealthStatusCritical) {
        PDS_LOG_DB_ERROR(@"Critical integrity failure, manual intervention required: %@", error);
        [self notifyAdministrator:error];
        return;
    }
    
    // 2. Check fragmentation
    NSUInteger fragmentation = [self getFragmentationPercent];
    if (fragmentation > 30) {
        PDS_LOG_DB_INFO(@"High fragmentation (%lu%%), running VACUUM", (unsigned long)fragmentation);
        [self vacuumDatabase:self.database.path error:&error];
    }
    
    // 3. Rebuild indexes if needed
    if (![self checkForeignKeys:&error]) {
        PDS_LOG_DB_WARNING(@"Foreign key violations detected, rebuilding indexes");
        [self reindexDatabase:self.database.path error:&error];
    }
    
    // 4. Update statistics
    [self analyzeDatabase:self.database.path error:&error];
    
    PDS_LOG_DB_INFO(@"Automated repair completed");
}
```

### Orphan Cleanup

Remove orphaned data:

```objc
- (NSUInteger)cleanupOrphanedBlobs:(NSString *)did error:(NSError **)error {
    PDSActorStore *store = [self.pool storeForDID:did error:error];
    if (!store) {
        return 0;
    }
    
    // Find orphaned blobs
    NSString *query = @"SELECT b.cid FROM blobs b "
                      @"LEFT JOIN records r ON r.value LIKE '%' || b.cid || '%' "
                      @"WHERE r.uri IS NULL AND b.created_at < datetime('now', '-7 days')";
    
    NSArray *orphanedBlobs = [store executeQuery:query error:error];
    
    if (orphanedBlobs.count == 0) {
        return 0;
    }
    
    // Delete orphaned blobs
    NSString *deleteSQL = @"DELETE FROM blobs WHERE cid = ?";
    
    NSUInteger deletedCount = 0;
    for (NSDictionary *blob in orphanedBlobs) {
        NSData *cid = blob[@"cid"];
        
        if ([store executeSQL:deleteSQL withParameters:@[cid] error:error]) {
            deletedCount++;
        }
    }
    
    PDS_LOG_DB_INFO(@"Cleaned up %lu orphaned blobs for %@", (unsigned long)deletedCount, did);
    return deletedCount;
}

- (NSUInteger)cleanupOrphanedBlocks:(NSString *)did error:(NSError **)error {
    PDSActorStore *store = [self.pool storeForDID:did error:error];
    if (!store) {
        return 0;
    }
    
    // Find blocks not referenced by repo_root or records
    NSString *query = @"SELECT b.cid FROM ipld_blocks b "
                      @"WHERE b.cid NOT IN (SELECT cid FROM repo_root) "
                      @"AND b.cid NOT IN (SELECT cid FROM records) "
                      @"AND b.created_at < datetime('now', '-7 days')";
    
    NSArray *orphanedBlocks = [store executeQuery:query error:error];
    
    if (orphanedBlocks.count == 0) {
        return 0;
    }
    
    // Delete orphaned blocks
    NSString *deleteSQL = @"DELETE FROM ipld_blocks WHERE cid = ?";
    
    NSUInteger deletedCount = 0;
    for (NSDictionary *block in orphanedBlocks) {
        NSData *cid = block[@"cid"];
        
        if ([store executeSQL:deleteSQL withParameters:@[cid] error:error]) {
            deletedCount++;
        }
    }
    
    PDS_LOG_DB_INFO(@"Cleaned up %lu orphaned blocks for %@", (unsigned long)deletedCount, did);
    return deletedCount;
}
```

## Best Practices

### 1. Regular Integrity Checks

```objc
// Schedule daily full integrity check
- (void)scheduleDailyIntegrityCheck {
    // Run at 3 AM local time
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *components = [[NSDateComponents alloc] init];
    components.hour = 3;
    components.minute = 0;
    
    NSDate *nextRun = [calendar nextDateAfterDate:[NSDate date]
                                 matchingComponents:components
                                            options:NSCalendarMatchNextTime];
    
    NSTimeInterval interval = [nextRun timeIntervalSinceNow];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        [self performFullIntegrityCheck];
        [self scheduleDailyIntegrityCheck]; // Reschedule for next day
    });
}
```

### 2. Backup Before Repair

Always backup before running repair operations:

```objc
- (BOOL)safeVacuum:(NSString *)databasePath error:(NSError **)error {
    // Create backup
    NSString *backupPath = [self createBackup:databasePath error:error];
    if (!backupPath) {
        return NO;
    }
    
    // Run VACUUM
    BOOL success = [self vacuumDatabase:databasePath error:error];
    
    if (!success) {
        // Restore from backup on failure
        [self restoreFromBackup:backupPath toDatabase:databasePath error:error];
    }
    
    return success;
}
```

### 3. Monitor Repair Operations

Track repair operation metrics:

```objc
- (void)vacuumWithMonitoring:(NSString *)databasePath {
    NSDate *startTime = [NSDate date];
    NSError *error = nil;
    
    PDS_LOG_DB_INFO(@"Starting VACUUM on %@", databasePath);
    
    BOOL success = [self vacuumDatabase:databasePath error:&error];
    
    NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:startTime];
    
    if (success) {
        PDS_LOG_DB_INFO(@"VACUUM completed in %.2f seconds", duration);
        [self recordMetric:@"vacuum_duration" value:duration];
    } else {
        PDS_LOG_DB_ERROR(@"VACUUM failed after %.2f seconds: %@", duration, error);
        [self recordMetric:@"vacuum_failure" value:1];
    }
}
```

### 4. Gradual Repair

For large databases, use incremental repair:

```objc
- (void)performGradualVacuum:(NSString *)databasePath {
    const NSInteger pagesPerBatch = 1000;
    NSInteger totalPages = [self getTotalPages:databasePath];
    NSInteger batchCount = (totalPages + pagesPerBatch - 1) / pagesPerBatch;
    
    for (NSInteger i = 0; i < batchCount; i++) {
        NSError *error = nil;
        [self incrementalVacuum:databasePath pages:pagesPerBatch error:&error];
        
        // Sleep between batches to avoid blocking
        [NSThread sleepForTimeInterval:1.0];
    }
}
```

### 5. Alert on Critical Issues

Notify administrators of critical integrity issues:

```objc
- (void)notifyIntegrityFailure:(NSError *)error {
    // Log critical error
    PDS_LOG_DB_ERROR(@"CRITICAL: Database integrity failure: %@", error);
    
    // Send alert (email, Slack, PagerDuty, etc.)
    [self sendAlert:@"Database Integrity Failure" 
            message:error.localizedDescription
           severity:@"critical"];
    
    // Record incident
    [self recordIncident:@"integrity_failure" details:error.userInfo];
}
```

## See Also

- [Migration Strategy](migration-strategy) — Versioning and compatibility
- [Migration Rollback](migration-rollback) — Rollback procedures
- [Zero-Downtime Migrations](zero-downtime-migrations) — Online migration strategies
- [WAL Mode](wal-mode) — Write-Ahead Logging benefits
- [SQLite Architecture](sqlite-architecture) — Database design patterns

