---
title: Zero-Downtime Migrations
---

# Zero-Downtime Migrations

## Overview

Zero-downtime migrations allow schema changes without service interruption. This document covers online migration strategies, staging approaches, and techniques for maintaining availability during database updates.

## Migration Strategies

### Expand-Contract Pattern

The expand-contract pattern enables zero-downtime migrations through three phases:

**Phase 1: Expand** — Add new schema elements without removing old ones
**Phase 2: Migrate** — Dual-write to both old and new schema
**Phase 3: Contract** — Remove old schema elements after migration complete

#### Example: Renaming a Column

**Phase 1: Expand (Deploy v1)**

```sql
-- Add new column alongside old one
ALTER TABLE accounts ADD COLUMN user_handle TEXT;

-- Create trigger to keep columns in sync
CREATE TRIGGER sync_handle_to_user_handle
AFTER UPDATE OF handle ON accounts
BEGIN
    UPDATE accounts SET user_handle = NEW.handle WHERE did = NEW.did;
END;

-- Backfill existing data
UPDATE accounts SET user_handle = handle WHERE user_handle IS NULL;
```

```objc
// Application code reads from old column, writes to both
- (void)updateAccount:(PDSAccount *)account {
    NSString *sql = @"UPDATE accounts SET handle = ?, user_handle = ? WHERE did = ?";
    [self.db executeSQL:sql 
         withParameters:@[account.handle, account.handle, account.did]
                  error:nil];
}
```

**Phase 2: Migrate (Deploy v2)**

```objc
// Application code reads from new column, writes to both
- (PDSAccount *)loadAccount:(NSString *)did {
    NSString *sql = @"SELECT did, user_handle, email FROM accounts WHERE did = ?";
    NSArray *results = [self.db executeQuery:sql withParameters:@[did] error:nil];
    
    if (results.count > 0) {
        PDSAccount *account = [[PDSAccount alloc] init];
        account.did = results[0][@"did"];
        account.handle = results[0][@"user_handle"]; // Read from new column
        account.email = results[0][@"email"];
        return account;
    }
    
    return nil;
}

- (void)updateAccount:(PDSAccount *)account {
    // Still write to both columns
    NSString *sql = @"UPDATE accounts SET handle = ?, user_handle = ? WHERE did = ?";
    [self.db executeSQL:sql 
         withParameters:@[account.handle, account.handle, account.did]
                  error:nil];
}
```

**Phase 3: Contract (Deploy v3)**

```sql
-- Remove old column and trigger
DROP TRIGGER sync_handle_to_user_handle;

-- Create new table without old column
CREATE TABLE accounts_new (
    did TEXT PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    user_handle TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL
);

-- Copy data
INSERT INTO accounts_new SELECT did, email, user_handle, password_hash, created_at, updated_at FROM accounts;

-- Swap tables
DROP TABLE accounts;
ALTER TABLE accounts_new RENAME TO accounts;

-- Recreate indexes
CREATE INDEX idx_accounts_email ON accounts(email);
CREATE INDEX idx_accounts_user_handle ON accounts(user_handle);
```

```objc
// Application code only uses new column
- (void)updateAccount:(PDSAccount *)account {
    NSString *sql = @"UPDATE accounts SET user_handle = ? WHERE did = ?";
    [self.db executeSQL:sql withParameters:@[account.handle, account.did] error:nil];
}
```

### Blue-Green Deployment

Run two complete environments and switch traffic after migration:

```objc
@interface PDSBlueGreenMigration : NSObject

@property (nonatomic, strong) PDSDatabase *blueDatabase;  // Current production
@property (nonatomic, strong) PDSDatabase *greenDatabase; // New version

- (BOOL)performBlueGreenMigration:(NSError **)error;

@end

@implementation PDSBlueGreenMigration

- (BOOL)performBlueGreenMigration:(NSError **)error {
    // 1. Create green database (copy of blue)
    if (![self createGreenDatabase:error]) {
        return NO;
    }
    
    // 2. Run migrations on green database
    if (![self migrateGreenDatabase:error]) {
        return NO;
    }
    
    // 3. Sync recent changes from blue to green
    if (![self syncBlueToGreen:error]) {
        return NO;
    }
    
    // 4. Switch traffic to green
    if (![self switchToGreen:error]) {
        return NO;
    }
    
    // 5. Keep blue as backup for rollback
    PDS_LOG_DB_INFO(@"Blue-green migration complete, blue database retained for rollback");
    
    return YES;
}

- (BOOL)createGreenDatabase:(NSError **)error {
    NSString *bluePath = self.blueDatabase.path;
    NSString *greenPath = [bluePath.stringByDeletingLastPathComponent 
                           stringByAppendingPathComponent:@"green.db"];
    
    // Use SQLite online backup API
    return [self createOnlineBackup:bluePath toPath:greenPath error:error];
}

- (BOOL)migrateGreenDatabase:(NSError **)error {
    PDSMigrationManager *manager = [PDSMigrationManager sharedManager];
    return [manager migrateDatabase:self.greenDatabase toVersion:[manager latestSchemaVersion] error:error];
}

- (BOOL)syncBlueToGreen:(NSError **)error {
    // Sync changes that occurred during migration
    NSDate *migrationStartTime = self.migrationStartTime;
    
    // Sync accounts
    NSString *query = @"SELECT * FROM accounts WHERE updated_at > ?";
    NSArray *recentAccounts = [self.blueDatabase executeQuery:query 
                                               withParameters:@[@(migrationStartTime.timeIntervalSince1970)]
                                                        error:error];
    
    for (NSDictionary *account in recentAccounts) {
        [self.greenDatabase executeSQL:@"INSERT OR REPLACE INTO accounts VALUES (?, ?, ?, ?, ?, ?)"
                        withParameters:@[account[@"did"], account[@"email"], account[@"handle"], 
                                       account[@"password_hash"], account[@"created_at"], account[@"updated_at"]]
                                 error:error];
    }
    
    return YES;
}

- (BOOL)switchToGreen:(NSError **)error {
    // Atomic switch: rename databases
    NSFileManager *fm = [NSFileManager defaultManager];
    
    NSString *bluePath = self.blueDatabase.path;
    NSString *greenPath = self.greenDatabase.path;
    NSString *backupPath = [bluePath.stringByDeletingLastPathComponent 
                            stringByAppendingPathComponent:@"blue-backup.db"];
    
    // Close connections
    [self.blueDatabase close];
    [self.greenDatabase close];
    
    // Rename blue to backup
    if (![fm moveItemAtPath:bluePath toPath:backupPath error:error]) {
        return NO;
    }
    
    // Rename green to production
    if (![fm moveItemAtPath:greenPath toPath:bluePath error:error]) {
        // Rollback: restore blue
        [fm moveItemAtPath:backupPath toPath:bluePath error:nil];
        return NO;
    }
    
    // Reopen production database (now pointing to green)
    self.blueDatabase = [[PDSDatabase alloc] initWithPath:bluePath];
    
    return YES;
}

@end
```

### Shadow Migration

Run migration in background while serving from old schema:

```objc
- (void)performShadowMigration {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSError *error = nil;
        
        // 1. Create shadow database
        NSString *shadowPath = [self.database.path stringByAppendingString:@".shadow"];
        [self createOnlineBackup:self.database.path toPath:shadowPath error:&error];
        
        // 2. Run migration on shadow database
        PDSDatabase *shadowDb = [[PDSDatabase alloc] initWithPath:shadowPath];
        PDSMigrationManager *manager = [PDSMigrationManager sharedManager];
        [manager migrateDatabase:shadowDb toVersion:[manager latestSchemaVersion] error:&error];
        
        // 3. Verify shadow database
        if ([self verifyDatabaseIntegrity:shadowPath error:&error]) {
            // 4. Schedule cutover during low-traffic period
            [self scheduleCutover:shadowPath];
        } else {
            PDS_LOG_DB_ERROR(@"Shadow migration verification failed: %@", error);
        }
    });
}

- (void)scheduleCutover:(NSString *)shadowPath {
    // Schedule cutover for 3 AM
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *components = [[NSDateComponents alloc] init];
    components.hour = 3;
    components.minute = 0;
    
    NSDate *cutoverTime = [calendar nextDateAfterDate:[NSDate date]
                                   matchingComponents:components
                                              options:NSCalendarMatchNextTime];
    
    NSTimeInterval delay = [cutoverTime timeIntervalSinceNow];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self performCutover:shadowPath];
    });
}

- (void)performCutover:(NSString *)shadowPath {
    // Brief service pause for atomic switch
    [self pauseService];
    
    NSError *error = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    
    NSString *productionPath = self.database.path;
    NSString *backupPath = [productionPath stringByAppendingString:@".backup"];
    
    // Close database
    [self.database close];
    
    // Atomic rename
    [fm moveItemAtPath:productionPath toPath:backupPath error:&error];
    [fm moveItemAtPath:shadowPath toPath:productionPath error:&error];
    
    // Reopen database
    self.database = [[PDSDatabase alloc] initWithPath:productionPath];
    
    [self resumeService];
    
    PDS_LOG_DB_INFO(@"Cutover complete, service resumed");
}
```

## Online Migration Techniques

### Read-Only Migration

Migrations that only add tables/columns don't require downtime:

```sql
-- Safe online migrations (no locks)
ALTER TABLE accounts ADD COLUMN profile_image TEXT DEFAULT NULL;
CREATE INDEX CONCURRENTLY idx_accounts_profile_image ON accounts(profile_image);
CREATE TABLE notifications (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    did TEXT NOT NULL,
    type TEXT NOT NULL,
    data BLOB,
    created_at DATETIME NOT NULL
);
```

```objc
- (BOOL)performOnlineMigration:(NSError **)error {
    // These operations don't block reads or writes
    NSArray *migrations = @[
        @"ALTER TABLE accounts ADD COLUMN profile_image TEXT DEFAULT NULL",
        @"CREATE TABLE notifications (id INTEGER PRIMARY KEY AUTOINCREMENT, did TEXT NOT NULL, type TEXT NOT NULL, data BLOB, created_at DATETIME NOT NULL)",
        @"CREATE INDEX idx_notifications_did ON notifications(did)"
    ];
    
    for (NSString *sql in migrations) {
        if (![self.database executeSQL:sql error:error]) {
            return NO;
        }
    }
    
    return YES;
}
```

### Batched Data Migration

Migrate data in small batches to avoid long locks:

```objc
- (BOOL)migrateDataInBatches:(NSError **)error {
    const NSUInteger batchSize = 1000;
    NSUInteger offset = 0;
    NSUInteger totalMigrated = 0;
    
    while (YES) {
        @autoreleasepool {
            // Fetch batch
            NSString *query = [NSString stringWithFormat:
                              @"SELECT * FROM accounts WHERE profile_image IS NULL LIMIT %lu OFFSET %lu",
                              (unsigned long)batchSize, (unsigned long)offset];
            
            NSArray *batch = [self.database executeQuery:query error:error];
            
            if (batch.count == 0) {
                break; // No more records
            }
            
            // Migrate batch
            for (NSDictionary *account in batch) {
                NSString *profileImage = [self generateProfileImage:account[@"did"]];
                
                NSString *update = @"UPDATE accounts SET profile_image = ? WHERE did = ?";
                [self.database executeSQL:update 
                           withParameters:@[profileImage, account[@"did"]]
                                    error:error];
            }
            
            totalMigrated += batch.count;
            offset += batchSize;
            
            // Brief pause between batches
            [NSThread sleepForTimeInterval:0.1];
            
            PDS_LOG_DB_INFO(@"Migrated %lu accounts", (unsigned long)totalMigrated);
        }
    }
    
    return YES;
}
```

### Throttled Migration

Limit migration rate to avoid impacting production:

```objc
- (void)performThrottledMigration {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSUInteger recordsPerSecond = 100;
        NSTimeInterval sleepInterval = 1.0 / recordsPerSecond;
        
        NSString *query = @"SELECT did FROM accounts WHERE profile_image IS NULL";
        NSArray *accounts = [self.database executeQuery:query error:nil];
        
        for (NSDictionary *account in accounts) {
            @autoreleasepool {
                // Migrate one record
                [self migrateAccount:account[@"did"]];
                
                // Throttle
                [NSThread sleepForTimeInterval:sleepInterval];
            }
        }
        
        PDS_LOG_DB_INFO(@"Throttled migration complete");
    });
}
```

## Staging Strategies

### Multi-Stage Rollout

Deploy migrations in stages to minimize risk:

```objc
@interface PDSMultiStageMigration : NSObject

typedef NS_ENUM(NSInteger, PDSMigrationStage) {
    PDSMigrationStageCanary,      // 1% of users
    PDSMigrationStageBeta,        // 10% of users
    PDSMigrationStageProduction   // 100% of users
};

- (BOOL)performMultiStageMigration:(NSError **)error;

@end

@implementation PDSMultiStageMigration

- (BOOL)performMultiStageMigration:(NSError **)error {
    // Stage 1: Canary (1% of users)
    if (![self migrateStage:PDSMigrationStageCanary error:error]) {
        return NO;
    }
    
    // Monitor for 24 hours
    [self monitorStage:PDSMigrationStageCanary duration:86400];
    
    if (![self stageHealthy:PDSMigrationStageCanary]) {
        PDS_LOG_DB_ERROR(@"Canary stage unhealthy, aborting migration");
        [self rollbackStage:PDSMigrationStageCanary];
        return NO;
    }
    
    // Stage 2: Beta (10% of users)
    if (![self migrateStage:PDSMigrationStageBeta error:error]) {
        return NO;
    }
    
    // Monitor for 12 hours
    [self monitorStage:PDSMigrationStageBeta duration:43200];
    
    if (![self stageHealthy:PDSMigrationStageBeta]) {
        PDS_LOG_DB_ERROR(@"Beta stage unhealthy, aborting migration");
        [self rollbackStage:PDSMigrationStageBeta];
        return NO;
    }
    
    // Stage 3: Production (100% of users)
    if (![self migrateStage:PDSMigrationStageProduction error:error]) {
        return NO;
    }
    
    PDS_LOG_DB_INFO(@"Multi-stage migration complete");
    return YES;
}

- (BOOL)migrateStage:(PDSMigrationStage)stage error:(NSError **)error {
    NSArray *userDIDs = [self selectUsersForStage:stage];
    
    for (NSString *did in userDIDs) {
        PDSActorStore *store = [self.pool storeForDID:did error:error];
        if (!store) {
            continue;
        }
        
        // Run migration on user's database
        PDSMigrationManager *manager = [PDSMigrationManager sharedManager];
        if (![manager migrateDatabase:store.database toVersion:[manager latestSchemaVersion] error:error]) {
            return NO;
        }
    }
    
    return YES;
}

- (NSArray<NSString *> *)selectUsersForStage:(PDSMigrationStage)stage {
    double percentage;
    switch (stage) {
        case PDSMigrationStageCanary:
            percentage = 0.01; // 1%
            break;
        case PDSMigrationStageBeta:
            percentage = 0.10; // 10%
            break;
        case PDSMigrationStageProduction:
            percentage = 1.00; // 100%
            break;
    }
    
    NSString *query = [NSString stringWithFormat:
                      @"SELECT did FROM accounts WHERE RANDOM() %% 100 < %d ORDER BY created_at",
                      (int)(percentage * 100)];
    
    NSArray *results = [self.serviceDb executeQuery:query error:nil];
    return [results valueForKey:@"did"];
}

@end
```

### Feature Flags

Control migration rollout with feature flags:

```objc
@interface PDSFeatureFlags : NSObject

+ (BOOL)isEnabled:(NSString *)feature forDID:(NSString *)did;
+ (void)enable:(NSString *)feature forDID:(NSString *)did;
+ (void)enableForPercentage:(NSString *)feature percentage:(double)percentage;

@end

// Usage in migration
- (BOOL)shouldUseMigratedSchema:(NSString *)did {
    return [PDSFeatureFlags isEnabled:@"new_account_schema" forDID:did];
}

- (PDSAccount *)loadAccount:(NSString *)did {
    if ([self shouldUseMigratedSchema:did]) {
        // Use new schema
        return [self loadAccountFromNewSchema:did];
    } else {
        // Use old schema
        return [self loadAccountFromOldSchema:did];
    }
}

- (void)updateAccount:(PDSAccount *)account {
    if ([self shouldUseMigratedSchema:account.did]) {
        // Write to new schema
        [self updateAccountInNewSchema:account];
    } else {
        // Write to old schema (and optionally dual-write to new)
        [self updateAccountInOldSchema:account];
        
        if ([PDSFeatureFlags isEnabled:@"dual_write_accounts" forDID:account.did]) {
            [self updateAccountInNewSchema:account];
        }
    }
}
```

### Gradual Rollout

Incrementally increase migration percentage:

```objc
- (void)performGradualRollout {
    // Day 1: 1%
    [PDSFeatureFlags enableForPercentage:@"new_account_schema" percentage:0.01];
    [self scheduleRolloutIncrease:1];
}

- (void)scheduleRolloutIncrease:(NSInteger)day {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 86400 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        double percentage;
        switch (day) {
            case 1: percentage = 0.05; break;  // Day 2: 5%
            case 2: percentage = 0.10; break;  // Day 3: 10%
            case 3: percentage = 0.25; break;  // Day 4: 25%
            case 4: percentage = 0.50; break;  // Day 5: 50%
            case 5: percentage = 1.00; break;  // Day 6: 100%
            default: return;
        }
        
        [PDSFeatureFlags enableForPercentage:@"new_account_schema" percentage:percentage];
        PDS_LOG_DB_INFO(@"Rollout increased to %.0f%%", percentage * 100);
        
        if (day < 5) {
            [self scheduleRolloutIncrease:day + 1];
        }
    });
}
```

## WAL Mode for Online Operations

### Checkpoint Control

Control WAL checkpointing during migrations:

```objc
- (BOOL)performMigrationWithCheckpointControl:(NSError **)error {
    sqlite3 *db;
    int result = sqlite3_open(self.database.path.UTF8String, &db);
    
    if (result != SQLITE_OK) {
        return NO;
    }
    
    // Disable automatic checkpointing during migration
    sqlite3_wal_autocheckpoint(db, 0);
    
    // Run migration
    BOOL success = [self executeMigration:error];
    
    if (success) {
        // Manual checkpoint after migration
        int nLog, nCkpt;
        result = sqlite3_wal_checkpoint_v2(db, NULL, SQLITE_CHECKPOINT_RESTART, &nLog, &nCkpt);
        
        if (result != SQLITE_OK) {
            PDS_LOG_DB_WARNING(@"Checkpoint after migration failed");
        }
    }
    
    // Re-enable automatic checkpointing
    sqlite3_wal_autocheckpoint(db, 1000);
    
    sqlite3_close(db);
    return success;
}
```

### Read-While-Write

WAL mode allows reads during migration writes:

```objc
- (void)demonstrateReadWhileWrite {
    // Writer thread (migration)
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self.database executeSQL:@"BEGIN IMMEDIATE" error:nil];
        
        // Long-running migration
        for (NSInteger i = 0; i < 10000; i++) {
            [self.database executeSQL:@"INSERT INTO new_table VALUES (?)" 
                       withParameters:@[@(i)]
                                error:nil];
        }
        
        [self.database executeSQL:@"COMMIT" error:nil];
    });
    
    // Reader threads (serving requests)
    for (NSInteger i = 0; i < 10; i++) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            // Reads continue unblocked during migration
            NSArray *results = [self.database executeQuery:@"SELECT * FROM accounts LIMIT 10" error:nil];
            PDS_LOG_DB_INFO(@"Read %lu accounts during migration", (unsigned long)results.count);
        });
    }
}
```

## Monitoring During Migration

### Migration Progress Tracking

**Source:** `Garazyk/Sources/Database/Migration/PDSMigrationManager.m` (Lines 235-245)

```objc
- (void)migrateWithProgress:(void (^)(double progress, NSString *status))progressBlock {
    self.progressBlock = progressBlock;
    
    NSInteger currentVersion = [self currentSchemaVersion:self.database error:nil];
    NSInteger targetVersion = [self latestSchemaVersion];
    NSInteger totalSteps = targetVersion - currentVersion;
    
    for (NSInteger version = currentVersion + 1; version <= targetVersion; version++) {
        double progress = (double)(version - currentVersion) / totalSteps;
        NSString *status = [NSString stringWithFormat:@"Migrating to version %ld", (long)version];
        
        progressBlock(progress, status);
        
        [self executeMigrationForVersion:version];
    }
    
    progressBlock(1.0, @"Migration complete");
}
```

### Health Monitoring

Monitor database health during migration:

```objc
- (void)monitorMigrationHealth {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        while (self.isMigrating) {
            @autoreleasepool {
                // Check database integrity
                NSError *error = nil;
                if (![self verifyDatabaseIntegrity:self.database.path error:&error]) {
                    PDS_LOG_DB_ERROR(@"Integrity check failed during migration: %@", error);
                    [self abortMigration];
                    break;
                }
                
                // Check query performance
                NSTimeInterval queryTime = [self measureQueryPerformance];
                if (queryTime > 1.0) {
                    PDS_LOG_DB_WARNING(@"Query performance degraded during migration: %.2fs", queryTime);
                }
                
                // Check disk space
                if (![self hasSufficientDiskSpace]) {
                    PDS_LOG_DB_ERROR(@"Insufficient disk space during migration");
                    [self abortMigration];
                    break;
                }
                
                [NSThread sleepForTimeInterval:10.0];
            }
        }
    });
}
```

### Performance Metrics

Track migration performance:

```objc
- (void)recordMigrationMetrics {
    NSMutableDictionary *metrics = [NSMutableDictionary dictionary];
    
    metrics[@"start_time"] = @(self.migrationStartTime.timeIntervalSince1970);
    metrics[@"end_time"] = @([[NSDate date] timeIntervalSince1970]);
    metrics[@"duration"] = @([[NSDate date] timeIntervalSinceDate:self.migrationStartTime]);
    
    metrics[@"records_migrated"] = @(self.recordsMigrated);
    metrics[@"records_per_second"] = @(self.recordsMigrated / [[NSDate date] timeIntervalSinceDate:self.migrationStartTime]);
    
    metrics[@"database_size_before"] = @(self.databaseSizeBefore);
    metrics[@"database_size_after"] = @([self currentDatabaseSize]);
    
    metrics[@"errors"] = @(self.errorCount);
    metrics[@"warnings"] = @(self.warningCount);
    
    [self logMetrics:metrics];
}
```

## Best Practices

### 1. Test Migration on Staging

Always test migrations on staging environment first:

```bash
# Test migration on staging
./scripts/test-migration.sh --environment staging --version 10

# Verify staging health
./scripts/health-check.sh --environment staging

# If healthy, proceed to production
./scripts/deploy-migration.sh --environment production --version 10
```

## 2. Prepare Rollback Plan

Have rollback plan ready before migration:

```objc
- (BOOL)performMigrationWithRollbackPlan:(NSError **)error {
    // 1. Create backup
    NSString *backupPath = [self createBackup:self.database.path error:error];
    if (!backupPath) {
        return NO;
    }
    
    // 2. Document rollback procedure
    [self documentRollbackProcedure:backupPath];
    
    // 3. Run migration
    BOOL success = [self executeMigration:error];
    
    if (!success) {
        // 4. Execute rollback
        PDS_LOG_DB_ERROR(@"Migration failed, executing rollback");
        [self restoreFromBackup:backupPath toDatabase:self.database.path error:error];
    }
    
    return success;
}
```

### 3. Monitor Service Health

Continuously monitor service health during migration:

```objc
- (void)performMigrationWithHealthMonitoring {
    [self startHealthMonitoring];
    
    NSError *error = nil;
    BOOL success = [self executeMigration:&error];
    
    if (!success) {
        [self handleMigrationFailure:error];
    }
    
    [self stopHealthMonitoring];
}

- (void)startHealthMonitoring {
    self.healthCheckTimer = [NSTimer scheduledTimerWithTimeInterval:10.0
                                                            repeats:YES
                                                              block:^(NSTimer *timer) {
        NSDictionary *health = [[PDSHealthCheck sharedInstance] performHealthCheck];
        
        if ([health[@"status"] isEqualToString:@"critical"]) {
            PDS_LOG_DB_ERROR(@"Critical health issue during migration: %@", health[@"errors"]);
            [self abortMigration];
        }
    }];
}
```

### 4. Communicate Maintenance Window

Notify users of planned maintenance:

```objc
- (void)scheduleMigrationWithNotification {
    // Send notification 24 hours before
    NSDate *migrationTime = [self nextMaintenanceWindow];
    NSDate *notificationTime = [migrationTime dateByAddingTimeInterval:-86400];
    
    [self scheduleNotification:@"Scheduled maintenance in 24 hours"
                        atTime:notificationTime];
    
    // Schedule migration
    [self scheduleMigration:migrationTime];
}
```

### 5. Limit Migration Scope

Keep migrations small and focused:

```objc
// Good: Small, focused migration
- (BOOL)addProfileImageColumn:(NSError **)error {
    return [self.database executeSQL:@"ALTER TABLE accounts ADD COLUMN profile_image TEXT DEFAULT NULL"
                               error:error];
}

// Bad: Large, complex migration
- (BOOL)migrateEverything:(NSError **)error {
    // Too many changes in one migration
    [self.database executeSQL:@"ALTER TABLE accounts ADD COLUMN profile_image TEXT" error:error];
    [self.database executeSQL:@"ALTER TABLE accounts ADD COLUMN bio TEXT" error:error];
    [self.database executeSQL:@"CREATE TABLE notifications (...)" error:error];
    [self.database executeSQL:@"CREATE TABLE follows (...)" error:error];
    // ... many more changes
}
```

### 6. Use Maintenance Windows

Schedule migrations during low-traffic periods:

```objc
- (NSDate *)nextMaintenanceWindow {
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *components = [[NSDateComponents alloc] init];
    
    // Sunday at 3 AM
    components.weekday = 1;
    components.hour = 3;
    components.minute = 0;
    
    return [calendar nextDateAfterDate:[NSDate date]
                    matchingComponents:components
                               options:NSCalendarMatchNextTime];
}
```

## See Also

- [Migration Strategy](migration-strategy) — Versioning and compatibility
- [Migration Rollback](migration-rollback) — Rollback procedures
- [Data Integrity](data-integrity) — Verification and consistency checks
- [WAL Mode](wal-mode) — Write-Ahead Logging benefits
- [SQLite Architecture](sqlite-architecture) — Database design patterns

