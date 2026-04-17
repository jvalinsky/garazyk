#import "PDSMigrationManager.h"
#import "Database/Schema/PDSSchemaManager.h"
#import "Debug/PDSLogger.h"
#import <sqlite3.h>

NSString * const PDSMigrationErrorDomain = @"com.atproto.pds.migration";

#pragma mark - V1 Initial Schema Migration

@interface V1InitialSchema : NSObject <PDSMigration>
@property (nonatomic, copy) NSString *schemaType;  // "service" or "actor"
- (instancetype)initWithSchemaType:(NSString *)schemaType;
@end

@implementation V1InitialSchema

- (instancetype)initWithSchemaType:(NSString *)schemaType {
    if ((self = [super init])) {
        _schemaType = [schemaType copy];
    }
    return self;
}

- (NSInteger)version {
    return 1;
}

- (NSString *)name {
    return [NSString stringWithFormat:@"%@_initial_schema", self.schemaType];
}

- (BOOL)up:(sqlite3 *)db error:(NSError **)error {
    NSString *schemaSQL;
    if ([self.schemaType isEqualToString:@"service"]) {
        schemaSQL = [[PDSSchemaManager sharedManager] serviceSchemaSQL];
    } else {
        schemaSQL = [[PDSSchemaManager sharedManager] actorStoreSchemaSQL];
    }

    char *errMsg = NULL;
    int result = sqlite3_exec(db, schemaSQL.UTF8String, NULL, NULL, &errMsg);

    if (result != SQLITE_OK) {
        if (error) {
            NSString *msg = errMsg ? [NSString stringWithUTF8String:errMsg] : @"Unknown SQL error";
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                         code:PDSMigrationErrorMigrationFailed
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: [NSString stringWithFormat:@"V1 up migration failed: %@", msg],
                                         @"sqlite_code": @(result)
                                     }];
        }
        if (errMsg) sqlite3_free(errMsg);
        return NO;
    }

    PDS_LOG_DB_INFO(@"V1 %@ schema migration applied", self.schemaType);
    return YES;
}

- (BOOL)down:(sqlite3 *)db error:(NSError **)error {
    // Drop all tables created by the schema
    NSArray<NSString *> *tablesToDrop;
    if ([self.schemaType isEqualToString:@"service"]) {
        tablesToDrop = @[
            @"accounts", @"invite_codes", @"reserved_handles", @"app_passwords",
            @"refresh_tokens", @"webauthn_credentials", @"jwt_signing_keys",
            @"events", @"actor_preferences", @"actor_mutes", @"did_cache", @"repo_sequence"
        ];
    } else {
        tablesToDrop = @[
            @"repo_root", @"records", @"ipld_blocks", @"record_tombstones",
            @"blobs", @"rotation_keys", @"signing_keys"
        ];
    }

    NSMutableString *dropSQL = [NSMutableString string];
    for (NSString *table in tablesToDrop) {
        [dropSQL appendFormat:@"DROP TABLE IF EXISTS %@;", table];
    }

    char *errMsg = NULL;
    int result = sqlite3_exec(db, dropSQL.UTF8String, NULL, NULL, &errMsg);

    if (result != SQLITE_OK) {
        if (error) {
            NSString *msg = errMsg ? [NSString stringWithUTF8String:errMsg] : @"Unknown SQL error";
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                         code:PDSMigrationErrorRollbackFailed
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: [NSString stringWithFormat:@"V1 down migration failed: %@", msg],
                                         @"sqlite_code": @(result)
                                     }];
        }
        if (errMsg) sqlite3_free(errMsg);
        return NO;
    }

    PDS_LOG_DB_INFO(@"V1 %@ schema migration rolled back", self.schemaType);
    return YES;
}

@end

#pragma mark - PDSMigrationManager Implementation

@interface PDSMigrationManager ()
@property (nonatomic, strong) NSMutableArray<id<PDSMigration>> *migrations;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation PDSMigrationManager

- (instancetype)init {
    if ((self = [super init])) {
        _migrations = [NSMutableArray array];
        _queue = dispatch_queue_create("com.atproto.pds.migration", DISPATCH_QUEUE_SERIAL);

        // Register built-in migrations (none yet - migrations are per-database type)
        // Callers will use different managers for service vs actor stores
    }
    return self;
}

#pragma mark - Migration Status

- (NSInteger)currentVersion:(sqlite3 *)db {
    __block NSInteger version = 0;

    dispatch_sync(self.queue, ^{
        // Check if _migrations table exists
        const char *checkSQL = "SELECT name FROM sqlite_master WHERE type='table' AND name='_migrations'";
        sqlite3_stmt *checkStmt = NULL;
        if (sqlite3_prepare_v2(db, checkSQL, -1, &checkStmt, NULL) != SQLITE_OK) {
            return;
        }

        BOOL tableExists = (sqlite3_step(checkStmt) == SQLITE_ROW);
        sqlite3_finalize(checkStmt);

        if (!tableExists) {
            // No migrations table = version 0
            return;
        }

        // Get max version
        const char *sql = "SELECT MAX(version) FROM _migrations";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
            return;
        }

        if (sqlite3_step(stmt) == SQLITE_ROW) {
            if (sqlite3_column_type(stmt, 0) != SQLITE_NULL) {
                version = sqlite3_column_int64(stmt, 0);
            }
        }

        sqlite3_finalize(stmt);
    });

    return version;
}

- (NSArray<id<PDSMigration>> *)pendingMigrations:(sqlite3 *)db {
    NSInteger current = [self currentVersion:db];

    dispatch_sync(self.queue, ^{
        // Sort migrations by version
        [self.migrations sortUsingComparator:^NSComparisonResult(id<PDSMigration> a, id<PDSMigration> b) {
            if (a.version < b.version) return NSOrderedAscending;
            if (a.version > b.version) return NSOrderedDescending;
            return NSOrderedSame;
        }];
    });

    NSMutableArray *pending = [NSMutableArray array];
    for (id<PDSMigration> migration in self.migrations) {
        if (migration.version > current) {
            [pending addObject:migration];
        }
    }

    return [pending copy];
}

- (BOOL)isMigrationApplied:(sqlite3 *)db version:(NSInteger)version {
    const char *sql = "SELECT 1 FROM _migrations WHERE version = ? LIMIT 1";
    sqlite3_stmt *stmt = NULL;

    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return NO;
    }

    sqlite3_bind_int64(stmt, 1, version);
    BOOL applied = (sqlite3_step(stmt) == SQLITE_ROW);
    sqlite3_finalize(stmt);

    return applied;
}

#pragma mark - Migration Operations

- (BOOL)migrateDatabase:(sqlite3 *)db error:(NSError **)error {
    // Create _migrations table if not exists
    const char *createMigrationsTable =
        "CREATE TABLE IF NOT EXISTS _migrations ("
        "    version INTEGER PRIMARY KEY,"
        "    name TEXT NOT NULL,"
        "    applied_at REAL NOT NULL"
        ")";

    char *errMsg = NULL;
    int result = sqlite3_exec(db, createMigrationsTable, NULL, NULL, &errMsg);
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                         code:PDSMigrationErrorTransactionFailed
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"Failed to create _migrations table",
                                         @"sqlite_message": errMsg ? [NSString stringWithUTF8String:errMsg] : @""
                                     }];
        }
        if (errMsg) sqlite3_free(errMsg);
        return NO;
    }

    // Get pending migrations
    NSArray<id<PDSMigration>> *pending = [self pendingMigrations:db];
    if (pending.count == 0) {
        PDS_LOG_DB_INFO(@"Database is up to date, no migrations pending");
        return YES;
    }

    PDS_LOG_DB_INFO(@"Applying %lu migrations...", (unsigned long)pending.count);

    // Apply each migration
    for (id<PDSMigration> migration in pending) {
        if (![self applyMigration:migration toDatabase:db error:error]) {
            return NO;
        }
    }

    PDS_LOG_DB_INFO(@"All migrations applied successfully");
    return YES;
}

- (BOOL)migrateDatabase:(sqlite3 *)db
              toVersion:(NSInteger)version
                  error:(NSError **)error {
    NSInteger current = [self currentVersion:db];

    if (version > current) {
        // Forward migration
        NSArray<id<PDSMigration>> *pending = [self pendingMigrations:db];
        for (id<PDSMigration> migration in pending) {
            if (migration.version > version) {
                break;
            }
            if (![self applyMigration:migration toDatabase:db error:error]) {
                return NO;
            }
        }
    } else if (version < current) {
        // Rollback
        return [self rollbackToVersion:db version:version error:error];
    }

    return YES;
}

- (BOOL)rollbackToVersion:(sqlite3 *)db
                 version:(NSInteger)version
                   error:(NSError **)error {
    NSInteger current = [self currentVersion:db];

    if (version >= current) {
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                         code:PDSMigrationErrorInvalidVersion
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Target version %ld must be less than current %ld", (long)version, (long)current]
                                     }];
        }
        return NO;
    }

    // Get migrations to rollback (in reverse order)
    NSArray<id<PDSMigration>> *allMigrations = [self.migrations sortedArrayUsingComparator:^NSComparisonResult(id<PDSMigration> a, id<PDSMigration> b) {
        if (a.version < b.version) return NSOrderedAscending;
        if (a.version > b.version) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    NSMutableArray *toRollback = [NSMutableArray array];
    for (id<PDSMigration> migration in [allMigrations reverseObjectEnumerator]) {
        if (migration.version <= version) {
            break;
        }
        if ([self isMigrationApplied:db version:migration.version]) {
            [toRollback addObject:migration];
        }
    }

    PDS_LOG_DB_INFO(@"Rolling back %lu migrations to version %ld...", (unsigned long)toRollback.count, (long)version);

    // Rollback each migration
    for (id<PDSMigration> migration in toRollback) {
        if (![self rollbackMigration:migration fromDatabase:db error:error]) {
            return NO;
        }
    }

    PDS_LOG_DB_INFO(@"Rollback completed successfully");
    return YES;
}

#pragma mark - Migration Registration

- (void)registerMigration:(id<PDSMigration>)migration {
    dispatch_sync(self.queue, ^{
        // Check for duplicate version
        for (id<PDSMigration> existing in self.migrations) {
            if (existing.version == migration.version) {
                PDS_LOG_DB_WARN(@"Migration version %ld already registered, skipping", (long)migration.version);
                return;
            }
        }
        [self.migrations addObject:migration];
    });
}

- (NSArray<id<PDSMigration>> *)registeredMigrations {
    return [self.migrations sortedArrayUsingComparator:^NSComparisonResult(id<PDSMigration> a, id<PDSMigration> b) {
        if (a.version < b.version) return NSOrderedAscending;
        if (a.version > b.version) return NSOrderedDescending;
        return NSOrderedSame;
    }];
}

#pragma mark - Private Helpers

- (BOOL)applyMigration:(id<PDSMigration>)migration
           toDatabase:(sqlite3 *)db
                 error:(NSError **)error {
    PDS_LOG_DB_INFO(@"Applying migration V%ld: %@", (long)migration.version, migration.name);

    // Begin transaction
    char *errMsg = NULL;
    int result = sqlite3_exec(db, "BEGIN TRANSACTION", NULL, NULL, &errMsg);
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                         code:PDSMigrationErrorTransactionFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to begin transaction"}];
        }
        return NO;
    }

    // Run migration up method
    NSError *upError = nil;
    BOOL success = [migration up:db error:&upError];

    if (success) {
        // Record migration
        const char *recordSQL = "INSERT INTO _migrations (version, name, applied_at) VALUES (?, ?, ?)";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(db, recordSQL, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int64(stmt, 1, migration.version);
            sqlite3_bind_text(stmt, 2, migration.name.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_double(stmt, 3, [[NSDate date] timeIntervalSince1970]);

            if (sqlite3_step(stmt) == SQLITE_DONE) {
                // Commit
                result = sqlite3_exec(db, "COMMIT", NULL, NULL, &errMsg);
                if (result != SQLITE_OK) {
                    PDS_LOG_DB_ERROR(@"Failed to commit migration V%ld: %s", (long)migration.version, errMsg);
                    sqlite3_exec(db, "ROLLBACK", NULL, NULL, NULL);
                    success = NO;
                } else {
                    PDS_LOG_DB_INFO(@"Migration V%ld applied successfully", (long)migration.version);
                }
            } else {
                PDS_LOG_DB_ERROR(@"Failed to record migration V%ld", (long)migration.version);
                sqlite3_exec(db, "ROLLBACK", NULL, NULL, NULL);
                success = NO;
            }
            sqlite3_finalize(stmt);
        } else {
            PDS_LOG_DB_ERROR(@"Failed to prepare migration record statement");
            sqlite3_exec(db, "ROLLBACK", NULL, NULL, NULL);
            success = NO;
        }
    } else {
        PDS_LOG_DB_ERROR(@"Migration V%ld up method failed: %@", (long)migration.version, upError);
        sqlite3_exec(db, "ROLLBACK", NULL, NULL, NULL);

        if (error && upError) {
            *error = upError;
        } else if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                         code:PDSMigrationErrorMigrationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Migration up method failed"}];
        }
        success = NO;
    }

    return success;
}

- (BOOL)rollbackMigration:(id<PDSMigration>)migration
             fromDatabase:(sqlite3 *)db
                   error:(NSError **)error {
    PDS_LOG_DB_INFO(@"Rolling back migration V%ld: %@", (long)migration.version, migration.name);

    // Begin transaction
    char *errMsg = NULL;
    int result = sqlite3_exec(db, "BEGIN TRANSACTION", NULL, NULL, &errMsg);
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                         code:PDSMigrationErrorTransactionFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to begin transaction"}];
        }
        return NO;
    }

    // Run migration down method
    NSError *downError = nil;
    BOOL success = [migration down:db error:&downError];

    if (success) {
        // Remove migration record
        const char *removeSQL = "DELETE FROM _migrations WHERE version = ?";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(db, removeSQL, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int64(stmt, 1, migration.version);

            if (sqlite3_step(stmt) == SQLITE_DONE) {
                // Commit
                result = sqlite3_exec(db, "COMMIT", NULL, NULL, &errMsg);
                if (result != SQLITE_OK) {
                    PDS_LOG_DB_ERROR(@"Failed to commit rollback V%ld: %s", (long)migration.version, errMsg);
                    sqlite3_exec(db, "ROLLBACK", NULL, NULL, NULL);
                    success = NO;
                } else {
                    PDS_LOG_DB_INFO(@"Migration V%ld rolled back successfully", (long)migration.version);
                }
            } else {
                PDS_LOG_DB_ERROR(@"Failed to remove migration record V%ld", (long)migration.version);
                sqlite3_exec(db, "ROLLBACK", NULL, NULL, NULL);
                success = NO;
            }
            sqlite3_finalize(stmt);
        } else {
            PDS_LOG_DB_ERROR(@"Failed to prepare migration removal statement");
            sqlite3_exec(db, "ROLLBACK", NULL, NULL, NULL);
            success = NO;
        }
    } else {
        PDS_LOG_DB_ERROR(@"Migration V%ld down method failed: %@", (long)migration.version, downError);
        sqlite3_exec(db, "ROLLBACK", NULL, NULL, NULL);

        if (error && downError) {
            *error = downError;
        } else if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                         code:PDSMigrationErrorRollbackFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Migration down method failed"}];
        }
        success = NO;
    }

    return success;
}

@end

#pragma mark - Convenience Factory Methods

@implementation PDSMigrationManager (Factory)

+ (instancetype)serviceDatabaseMigrationManager {
    PDSMigrationManager *manager = [[PDSMigrationManager alloc] init];
    [manager registerMigration:[[V1InitialSchema alloc] initWithSchemaType:@"service"]];
    return manager;
}

+ (instancetype)actorStoreMigrationManager {
    PDSMigrationManager *manager = [[PDSMigrationManager alloc] init];
    [manager registerMigration:[[V1InitialSchema alloc] initWithSchemaType:@"actor"]];
    return manager;
}

@end
