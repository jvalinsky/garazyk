// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSMigrationManager.h"
#import "Database/Schema/PDSSchemaManager.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"
#import "Database/PDSBlock.h"
#import "Debug/GZLogger.h"
#import "Compat/PDSTypes.h"
#import <sqlite3.h>

// Suppress -Wobjc-string-concatenation: multi-line SQL string literals
// inside NSArray expressions are intentional C string concatenation,
// not missing commas.
#pragma clang diagnostic ignored "-Wobjc-string-concatenation"

NSString * const PDSMigrationErrorDomain = @"com.atproto.pds.migration";

#pragma mark - V2 Ozone Schema Migration

@interface V2OzoneSchema : NSObject <PDSMigration>
@end

@implementation V2OzoneSchema

- (NSInteger)version {
    return 2;
}

- (NSString *)name {
    return @"ozone_moderation_schema";
}

- (BOOL)up:(sqlite3 *)db error:(NSError **)error {
    PDSSchemaManager *sm = [PDSSchemaManager sharedManager];
    NSArray *schemas = @[
        [sm ozoneEventsTableSchema],
        [sm ozoneSetsTableSchema],
        [sm ozoneSetMembersTableSchema],
        [sm ozoneTemplatesTableSchema],
        [sm ozoneTeamTableSchema],
        @"CREATE INDEX IF NOT EXISTS idx_mod_events_subject ON moderation_events(subject_did, subject_type)",
        @"CREATE INDEX IF NOT EXISTS idx_mod_events_created ON moderation_events(created_at)",
        @"CREATE INDEX IF NOT EXISTS idx_mod_set_members_did ON moderation_set_members(did)"
    ];

    for (NSString *sql in schemas) {
        char *errMsg = NULL;
        int result = sqlite3_exec(db, sql.UTF8String, NULL, NULL, &errMsg);
        if (result != SQLITE_OK) {
            if (error) {
                NSString *msg = errMsg ? [NSString stringWithUTF8String:errMsg] : @"Unknown SQL error";
                *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                             code:PDSMigrationErrorMigrationFailed
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"V2 up failed: %@", msg]}];
            }
            if (errMsg) sqlite3_free(errMsg);
            return NO;
        }
    }
    return YES;
}

- (BOOL)down:(sqlite3 *)db error:(NSError **)error {
    // Whitelist of known migration tables
    NSSet<NSString *> *allowedTables = [NSSet setWithArray:@[
        @"moderation_events", @"moderation_sets", @"moderation_set_members",
        @"moderation_templates", @"moderation_team"
    ]];
    for (NSString *table in allowedTables) {
        NSString *sql = [NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", table];
        sqlite3_exec(db, sql.UTF8String, NULL, NULL, NULL);
    }
    return YES;
}

@end

#pragma mark - V3 Diagnostics Schema Migration

@interface V3DiagnosticsSchema : NSObject <PDSMigration>
@end

@implementation V3DiagnosticsSchema

- (NSInteger)version {
    return 3;
}

- (NSString *)name {
    return @"diagnostics_schema";
}

- (BOOL)up:(sqlite3 *)db error:(NSError **)error {
    PDSSchemaManager *sm = [PDSSchemaManager sharedManager];
    NSArray *schemas = @[
        [sm sequencerAnalyticsTableSchema],
        [sm blobAuditJobsTableSchema],
        [sm rateLimitHistoryTableSchema],
        @"CREATE INDEX IF NOT EXISTS idx_sequencer_analytics_timestamp ON sequencer_analytics(timestamp)",
        @"CREATE INDEX IF NOT EXISTS idx_blob_audit_jobs_status ON blob_audit_jobs(status)",
        @"CREATE INDEX IF NOT EXISTS idx_rate_limit_history_identifier ON rate_limit_history(identifier)",
        @"CREATE INDEX IF NOT EXISTS idx_rate_limit_history_timestamp ON rate_limit_history(timestamp)"
    ];

    for (NSString *sql in schemas) {
        char *errMsg = NULL;
        int result = sqlite3_exec(db, sql.UTF8String, NULL, NULL, &errMsg);
        if (result != SQLITE_OK) {
            if (error) {
                NSString *msg = errMsg ? [NSString stringWithUTF8String:errMsg] : @"Unknown SQL error";
                *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                             code:PDSMigrationErrorMigrationFailed
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"V3 up failed: %@", msg]}];
            }
            if (errMsg) sqlite3_free(errMsg);
            return NO;
        }
    }
    return YES;
}

- (BOOL)down:(sqlite3 *)db error:(NSError **)error {
    // Whitelist of known diagnostic tables
    NSSet<NSString *> *allowedTables = [NSSet setWithArray:@[
        @"sequencer_analytics", @"blob_audit_jobs", @"rate_limit_history"
    ]];
    for (NSString *table in allowedTables) {
        NSString *sql = [NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", table];
        sqlite3_exec(db, sql.UTF8String, NULL, NULL, NULL);
    }
    return YES;
}

@end

#pragma mark - V4 Ozone Scheduled Actions Schema Migration

@interface V4OzoneScheduledActionsSchema : NSObject <PDSMigration>
@end

@implementation V4OzoneScheduledActionsSchema

- (NSInteger)version {
    return 4;
}

- (NSString *)name {
    return @"ozone_scheduled_actions_schema";
}

- (BOOL)up:(sqlite3 *)db error:(NSError **)error {
    PDSSchemaManager *sm = [PDSSchemaManager sharedManager];
    NSArray *schemas = @[
        [sm ozoneScheduledActionsTableSchema]
    ];

    for (NSString *sql in schemas) {
        char *errMsg = NULL;
        int result = sqlite3_exec(db, sql.UTF8String, NULL, NULL, &errMsg);
        if (result != SQLITE_OK) {
            if (error) {
                NSString *msg = errMsg ? [NSString stringWithUTF8String:errMsg] : @"Unknown SQL error";
                *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                             code:PDSMigrationErrorMigrationFailed
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"V4 up failed: %@", msg]}];
            }
            if (errMsg) sqlite3_free(errMsg);
            return NO;
        }
    }
    return YES;
}

- (BOOL)down:(sqlite3 *)db error:(NSError **)error {
    NSString *sql = @"DROP TABLE IF EXISTS moderation_scheduled_actions";
    sqlite3_exec(db, sql.UTF8String, NULL, NULL, NULL);
    return YES;
}

@end

#pragma mark - V5 Hosting Events Schema Migration

@interface V5HostingEventsSchema : NSObject <PDSMigration>
@end

@implementation V5HostingEventsSchema

- (NSInteger)version {
    return 5;
}

- (NSString *)name {
    return @"hosting_events_schema";
}

- (BOOL)up:(sqlite3 *)db error:(NSError **)error {
    PDSSchemaManager *sm = [PDSSchemaManager sharedManager];
    NSArray *schemas = @[
        [sm serviceHostingEventsTableSchema],
        @"CREATE INDEX IF NOT EXISTS idx_hosting_events_did ON hosting_events(did)"
    ];

    for (NSString *sql in schemas) {
        char *errMsg = NULL;
        int result = sqlite3_exec(db, sql.UTF8String, NULL, NULL, &errMsg);
        if (result != SQLITE_OK) {
            if (error) {
                NSString *msg = errMsg ? [NSString stringWithUTF8String:errMsg] : @"Unknown SQL error";
                *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                             code:PDSMigrationErrorMigrationFailed
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"V5 up failed: %@", msg]}];
            }
            if (errMsg) sqlite3_free(errMsg);
            return NO;
        }
    }
    return YES;
}

- (BOOL)down:(sqlite3 *)db error:(NSError **)error {
    NSString *sql = @"DROP TABLE IF EXISTS hosting_events";
    sqlite3_exec(db, sql.UTF8String, NULL, NULL, NULL);
    return YES;
}

@end

#pragma mark - V6 Drafts Schema Migration (Actor Store)

@interface V6DraftsSchema : NSObject <PDSMigration>
@end

@implementation V6DraftsSchema

- (NSInteger)version {
    return 6;
}

- (NSString *)name {
    return @"drafts_schema";
}

- (BOOL)up:(sqlite3 *)db error:(NSError **)error {
    NSArray *schemas = @[
        @"CREATE TABLE IF NOT EXISTS drafts ("
        @"id TEXT PRIMARY KEY, "
        @"did TEXT NOT NULL, "
        @"content TEXT NOT NULL, "
        @"created_at INTEGER NOT NULL, "
        @"updated_at INTEGER NOT NULL"
        @")",
        @"CREATE INDEX IF NOT EXISTS idx_drafts_did ON drafts(did)"
    ];

    for (NSString *sql in schemas) {
        char *errMsg = NULL;
        int result = sqlite3_exec(db, sql.UTF8String, NULL, NULL, &errMsg);
        if (result != SQLITE_OK) {
            if (error) {
                NSString *msg = errMsg ? [NSString stringWithUTF8String:errMsg] : @"Unknown SQL error";
                *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                             code:PDSMigrationErrorMigrationFailed
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"V6 up failed: %@", msg]}];
            }
            if (errMsg) sqlite3_free(errMsg);
            return NO;
        }
    }
    return YES;
}

- (BOOL)down:(sqlite3 *)db error:(NSError **)error {
    sqlite3_exec(db, "DROP TABLE IF EXISTS drafts", NULL, NULL, NULL);
    return YES;
}

@end

#pragma mark - V7 Search FTS5 Schema Migration (Service DB)

@interface V7SearchFTS5Schema : NSObject <PDSMigration>
@end

@implementation V7SearchFTS5Schema

- (NSInteger)version {
    return 7;
}

- (NSString *)name {
    return @"search_fts5_schema";
}

- (BOOL)up:(sqlite3 *)db error:(NSError **)error {
    NSArray *schemas = @[
        // Content tables (source of truth for FTS rebuild)
        @"CREATE TABLE IF NOT EXISTS search_actors("
        @"rowid INTEGER PRIMARY KEY, "
        @"did TEXT NOT NULL, "
        @"display_name TEXT, "
        @"handle TEXT, "
        @"description TEXT"
        @")",

        @"CREATE TABLE IF NOT EXISTS search_posts("
        @"rowid INTEGER PRIMARY KEY, "
        @"uri TEXT NOT NULL, "
        @"did TEXT NOT NULL, "
        @"text TEXT"
        @")",

        @"CREATE TABLE IF NOT EXISTS search_starter_packs("
        @"rowid INTEGER PRIMARY KEY, "
        @"uri TEXT NOT NULL, "
        @"did TEXT NOT NULL, "
        @"name TEXT"
        @")",

        // FTS5 virtual tables
        @"CREATE VIRTUAL TABLE IF NOT EXISTS fts_actors "
        @"USING fts5(did, display_name, handle, description, "
        @"content=search_actors, content_rowid=rowid)",

        @"CREATE VIRTUAL TABLE IF NOT EXISTS fts_posts "
        @"USING fts5(uri, did, text, "
        @"content=search_posts, content_rowid=rowid)",

        @"CREATE VIRTUAL TABLE IF NOT EXISTS fts_starter_packs "
        @"USING fts5(uri, did, name, "
        @"content=search_starter_packs, content_rowid=rowid)",

        // Indexes on content tables
        @"CREATE INDEX IF NOT EXISTS idx_search_actors_did ON search_actors(did)",
        @"CREATE INDEX IF NOT EXISTS idx_search_posts_uri ON search_posts(uri)",
        @"CREATE INDEX IF NOT EXISTS idx_search_starter_packs_uri ON search_starter_packs(uri)"
    ];

    for (NSString *sql in schemas) {
        char *errMsg = NULL;
        int result = sqlite3_exec(db, sql.UTF8String, NULL, NULL, &errMsg);
        if (result != SQLITE_OK) {
            if (error) {
                NSString *msg = errMsg ? [NSString stringWithUTF8String:errMsg] : @"Unknown SQL error";
                *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                             code:PDSMigrationErrorMigrationFailed
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"V7 up failed: %@", msg]}];
            }
            if (errMsg) sqlite3_free(errMsg);
            return NO;
        }
    }
    return YES;
}

- (BOOL)down:(sqlite3 *)db error:(NSError **)error {
    sqlite3_exec(db, "DROP TABLE IF EXISTS fts_starter_packs", NULL, NULL, NULL);
    sqlite3_exec(db, "DROP TABLE IF EXISTS fts_posts", NULL, NULL, NULL);
    sqlite3_exec(db, "DROP TABLE IF EXISTS fts_actors", NULL, NULL, NULL);
    sqlite3_exec(db, "DROP TABLE IF EXISTS search_starter_packs", NULL, NULL, NULL);
    sqlite3_exec(db, "DROP TABLE IF EXISTS search_posts", NULL, NULL, NULL);
    sqlite3_exec(db, "DROP TABLE IF EXISTS search_actors", NULL, NULL, NULL);
    return YES;
}

@end

#pragma mark - V8 Ozone Subjects & Safelinks Schema

@interface V8OzoneSubjectsSchema : NSObject <PDSMigration>
@end

@implementation V8OzoneSubjectsSchema

- (NSInteger)version {
    return 8;
}

- (NSString *)name {
    return @"ozone_subjects_safelinks_schema";
}

- (BOOL)up:(sqlite3 *)db error:(NSError **)error {
    PDSSchemaManager *sm = [PDSSchemaManager sharedManager];
    NSArray *schemas = @[
        [sm ozoneSubjectsTableSchema],
        [sm ozoneSafelinksTableSchema],
        @"CREATE INDEX IF NOT EXISTS idx_mod_subjects_state ON moderation_subjects(review_state)",
        @"CREATE INDEX IF NOT EXISTS idx_mod_subjects_did ON moderation_subjects(subject_did)",
        @"CREATE INDEX IF NOT EXISTS idx_mod_safelinks_url ON moderation_safelinks(url)"
    ];

    for (NSString *sql in schemas) {
        char *errMsg = NULL;
        int result = sqlite3_exec(db, sql.UTF8String, NULL, NULL, &errMsg);
        if (result != SQLITE_OK) {
            if (error) {
                NSString *msg = errMsg ? [NSString stringWithUTF8String:errMsg] : @"Unknown SQL error";
                *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                             code:PDSMigrationErrorMigrationFailed
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"V8 up failed: %@", msg]}];
            }
            if (errMsg) sqlite3_free(errMsg);
            return NO;
        }
    }
    return YES;
}

- (BOOL)down:(sqlite3 *)db error:(NSError **)error {
    sqlite3_exec(db, "DROP TABLE IF EXISTS moderation_subjects", NULL, NULL, NULL);
    sqlite3_exec(db, "DROP TABLE IF EXISTS moderation_safelinks", NULL, NULL, NULL);
    return YES;
}

@end

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

    GZ_LOG_DB_INFO(@"V1 %@ schema migration applied", self.schemaType);
    return YES;
}

- (BOOL)down:(sqlite3 *)db error:(NSError **)error {
    // Whitelist tables to drop (prevent SQL injection via schemaType)
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

    for (NSString *table in tablesToDrop) {
        // table is from a hardcoded list, but defensively validate anyway
        NSError *regexError = nil;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^[a-z0-9_]+$" options:0 error:&regexError];
        if (regex) {
            NSRange range = NSMakeRange(0, table.length);
            if ([regex numberOfMatchesInString:table options:0 range:range] == 0) continue;
        } else {
            continue; // invalid regex, skip
        }
        NSString *sql = [NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", table];
        sqlite3_exec(db, sql.UTF8String, NULL, NULL, NULL);
    }
    
    GZ_LOG_DB_INFO(@"V1 %@ schema migration rolled back", self.schemaType);
    return YES;
}

@end

#pragma mark - PDSMigrationManager Implementation

@interface PDSMigrationManager ()
@property (nonatomic, strong) NSMutableArray<id<PDSMigration>> *migrations;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t queue;

// Monolithic migration helpers
- (NSArray<NSString *> *)queryAllDIDsFromDatabase:(sqlite3 *)db error:(NSError **)error;
- (NSString *)actorStoreDirectoryForDID:(NSString *)did inBaseDirectory:(NSString *)baseDir;
- (BOOL)migrateAccountForDID:(NSString *)did from:(sqlite3 *)sourceDb to:(id<PDSActorStoreTransactor>)txn error:(NSError **)error;
- (BOOL)migrateReposForDID:(NSString *)did from:(sqlite3 *)sourceDb to:(id<PDSActorStoreTransactor>)txn error:(NSError **)error;
- (BOOL)migrateRecordsForDID:(NSString *)did from:(sqlite3 *)sourceDb to:(id<PDSActorStoreTransactor>)txn error:(NSError **)error;
- (BOOL)migrateBlocksForDID:(NSString *)did from:(sqlite3 *)sourceDb to:(id<PDSActorStoreTransactor>)txn error:(NSError **)error;
- (NSData *)convertCIDStringToData:(NSString *)cidString;
- (NSString *)convertUnixTimestampToISO8601:(NSTimeInterval)timestamp;
@end

@implementation PDSMigrationManager

+ (instancetype)sharedManager {
    static PDSMigrationManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[PDSMigrationManager alloc] init];
    });
    return sharedInstance;
}

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
        GZ_LOG_DB_INFO(@"Database is up to date, no migrations pending");
        return YES;
    }

    GZ_LOG_DB_INFO(@"Applying %lu migrations...", (unsigned long)pending.count);

    // Apply each migration
    for (id<PDSMigration> migration in pending) {
        if (![self applyMigration:migration toDatabase:db error:error]) {
            return NO;
        }
    }

    GZ_LOG_DB_INFO(@"All migrations applied successfully");
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

    GZ_LOG_DB_INFO(@"Rolling back %lu migrations to version %ld...", (unsigned long)toRollback.count, (long)version);

    // Rollback each migration
    for (id<PDSMigration> migration in toRollback) {
        if (![self rollbackMigration:migration fromDatabase:db error:error]) {
            return NO;
        }
    }

    GZ_LOG_DB_INFO(@"Rollback completed successfully");
    return YES;
}

#pragma mark - Monolithic Migration

- (NSUInteger)estimatedMigrateTimeWithSourcePath:(NSString *)sourcePath {
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:sourcePath error:nil];
    unsigned long long fileSize = [attrs fileSize];
    // Estimate based on file size in MiB (1 minute per MiB)
    return (NSUInteger)(fileSize / (1024 * 1024));
}

- (BOOL)migrateFromMonolithicDatabase:(NSString *)sourcePath
               toSingleTenantDirectory:(NSString *)destinationDirectory
                                 error:(NSError **)error {
    GZ_LOG_DB_INFO(@"Starting monolithic migration from %@ to %@", sourcePath, destinationDirectory);

    // Validate source file exists
    if (![[NSFileManager defaultManager] fileExistsAtPath:sourcePath]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                         code:PDSMigrationErrorSourceNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"Source database file not found"}];
        }
        return NO;
    }

    // Check for cancellation
    if (self.cancelBlock && self.cancelBlock()) {
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                         code:PDSMigrationErrorCancelled
                                     userInfo:@{NSLocalizedDescriptionKey: @"Migration cancelled"}];
        }
        return NO;
    }

    if (self.progressBlock) self.progressBlock(0.05, @"Opening source database...");

    // Open source database
    sqlite3 *sourceDb = NULL;
    int rc = sqlite3_open([sourcePath UTF8String], &sourceDb);
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                         code:PDSMigrationErrorMigrationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to open source database"}];
        }
        if (sourceDb) sqlite3_close(sourceDb);
        return NO;
    }

    // Query all DIDs from accounts table
    if (self.progressBlock) self.progressBlock(0.1, @"Querying accounts...");

    NSArray<NSString *> *dids = [self queryAllDIDsFromDatabase:sourceDb error:error];
    if (!dids) {
        sqlite3_close(sourceDb);
        return NO;
    }

    NSInteger totalDIDs = dids.count;
    if (totalDIDs == 0) {
        GZ_LOG_DB_INFO(@"No accounts to migrate");
        sqlite3_close(sourceDb);
        if (self.progressBlock) self.progressBlock(1.0, @"Migration complete");
        return YES;
    }

    // Ensure destination directory exists
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm createDirectoryAtPath:destinationDirectory withIntermediateDirectories:YES attributes:nil error:error]) {
        sqlite3_close(sourceDb);
        return NO;
    }

    // Migrate each DID's data
    NSInteger currentDID = 0;
    for (NSString *did in dids) {
        // Check for cancellation
        if (self.cancelBlock && self.cancelBlock()) {
            if (error) {
                *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                             code:PDSMigrationErrorCancelled
                                         userInfo:@{NSLocalizedDescriptionKey: @"Migration cancelled"}];
            }
            sqlite3_close(sourceDb);
            return NO;
        }

        // Create ActorStore directory for this DID
        NSString *actorDir = [self actorStoreDirectoryForDID:did inBaseDirectory:destinationDirectory];
        if (![fm createDirectoryAtPath:actorDir withIntermediateDirectories:YES attributes:nil error:error]) {
            sqlite3_close(sourceDb);
            return NO;
        }

        // Create ActorStore database path
        NSString *actorDbPath = [actorDir stringByAppendingPathComponent:@"actorstore.db"];

        // Create and open ActorStore
        NSError *storeError = nil;
        PDSActorStore *store = [PDSActorStore storeWithDid:did dbPath:actorDbPath error:&storeError];
        if (!store || ![store openWithError:&storeError]) {
            if (error) *error = storeError;
            sqlite3_close(sourceDb);
            return NO;
        }

        // Migrate data in transaction
        __block BOOL transactionSuccess = YES;
        __block NSError *transactionError = nil;

        [store transactWithBlock:^(id<PDSActorStoreTransactor> txn, NSError **txnError) {
            if (![self migrateAccountForDID:did from:sourceDb to:txn error:txnError]) {
                transactionSuccess = NO;
                return;
            }
            if (![self migrateReposForDID:did from:sourceDb to:txn error:txnError]) {
                transactionSuccess = NO;
                return;
            }
            if (![self migrateRecordsForDID:did from:sourceDb to:txn error:txnError]) {
                transactionSuccess = NO;
                return;
            }
            if (![self migrateBlocksForDID:did from:sourceDb to:txn error:txnError]) {
                transactionSuccess = NO;
                return;
            }
        } error:&transactionError];

        [store close];

        if (!transactionSuccess || transactionError) {
            if (error) *error = transactionError;
            sqlite3_close(sourceDb);
            return NO;
        }

        // Update progress
        currentDID++;
        double progress = 0.1 + (0.9 * (double)currentDID / totalDIDs);
        if (self.progressBlock) {
            self.progressBlock(progress, [NSString stringWithFormat:@"Migrated %@ (%ld/%ld)", did, (long)currentDID, (long)totalDIDs]);
        }
    }

    sqlite3_close(sourceDb);

    if (self.progressBlock) self.progressBlock(1.0, @"Migration completed successfully");
    GZ_LOG_DB_INFO(@"Monolithic migration completed successfully");

    return YES;
}

- (void)migrateFromMonolithicDatabaseAsync:(NSString *)sourcePath
                    toSingleTenantDirectory:(NSString *)destinationDirectory
                                 completion:(void (^)(NSError * _Nullable error))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        [self migrateFromMonolithicDatabase:sourcePath 
                    toSingleTenantDirectory:destinationDirectory 
                                      error:&error];
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(error);
            });
        }
    });
}

#pragma mark - Migration Registration

- (void)registerMigration:(id<PDSMigration>)migration {
    dispatch_sync(self.queue, ^{
        // Check for duplicate version
        for (id<PDSMigration> existing in self.migrations) {
            if (existing.version == migration.version) {
                GZ_LOG_DB_WARN(@"Migration version %ld already registered, skipping", (long)migration.version);
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
    GZ_LOG_DB_INFO(@"Applying migration V%ld: %@", (long)migration.version, migration.name);

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
                    GZ_LOG_DB_ERROR(@"Failed to commit migration V%ld: %s", (long)migration.version, errMsg);
                    sqlite3_exec(db, "ROLLBACK", NULL, NULL, NULL);
                    success = NO;
                } else {
                    GZ_LOG_DB_INFO(@"Migration V%ld applied successfully", (long)migration.version);
                }
            } else {
                GZ_LOG_DB_ERROR(@"Failed to record migration V%ld", (long)migration.version);
                sqlite3_exec(db, "ROLLBACK", NULL, NULL, NULL);
                success = NO;
            }
            sqlite3_finalize(stmt);
        } else {
            GZ_LOG_DB_ERROR(@"Failed to prepare migration record statement");
            sqlite3_exec(db, "ROLLBACK", NULL, NULL, NULL);
            success = NO;
        }
    } else {
        GZ_LOG_DB_ERROR(@"Migration V%ld up method failed: %@", (long)migration.version, upError);
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
    GZ_LOG_DB_INFO(@"Rolling back migration V%ld: %@", (long)migration.version, migration.name);

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
                    GZ_LOG_DB_ERROR(@"Failed to commit rollback V%ld: %s", (long)migration.version, errMsg);
                    sqlite3_exec(db, "ROLLBACK", NULL, NULL, NULL);
                    success = NO;
                } else {
                    GZ_LOG_DB_INFO(@"Migration V%ld rolled back successfully", (long)migration.version);
                }
            } else {
                GZ_LOG_DB_ERROR(@"Failed to remove migration record V%ld", (long)migration.version);
                sqlite3_exec(db, "ROLLBACK", NULL, NULL, NULL);
                success = NO;
            }
            sqlite3_finalize(stmt);
        } else {
            GZ_LOG_DB_ERROR(@"Failed to prepare migration removal statement");
            sqlite3_exec(db, "ROLLBACK", NULL, NULL, NULL);
            success = NO;
        }
    } else {
        GZ_LOG_DB_ERROR(@"Migration V%ld down method failed: %@", (long)migration.version, downError);
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

#pragma mark - Monolithic Migration Helpers

- (NSArray<NSString *> *)queryAllDIDsFromDatabase:(sqlite3 *)db error:(NSError **)error {
    const char *sql = "SELECT DISTINCT did FROM accounts ORDER BY did";
    sqlite3_stmt *stmt = NULL;

    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                         code:PDSMigrationErrorMigrationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to query DIDs"}];
        }
        return nil;
    }

    NSMutableArray<NSString *> *dids = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        const char *didStr = (const char *)sqlite3_column_text(stmt, 0);
        if (didStr) {
            [dids addObject:[NSString stringWithUTF8String:didStr]];
        }
    }

    sqlite3_finalize(stmt);
    return [dids copy];
}

- (NSString *)actorStoreDirectoryForDID:(NSString *)did inBaseDirectory:(NSString *)baseDir {
    // Directory structure: {baseDir}/{did}/
    return [baseDir stringByAppendingPathComponent:did];
}

- (BOOL)migrateAccountForDID:(NSString *)did from:(sqlite3 *)sourceDb to:(id<PDSActorStoreTransactor>)txn error:(NSError **)error {
    const char *sql = "SELECT did, handle, email, password_hash, password_salt, access_jwt, refresh_jwt, created_at, updated_at FROM accounts WHERE did = ? LIMIT 1";
    sqlite3_stmt *stmt = NULL;

    if (sqlite3_prepare_v2(sourceDb, sql, -1, &stmt, NULL) != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                         code:PDSMigrationErrorMigrationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to query account"}];
        }
        return NO;
    }

    sqlite3_bind_text(stmt, 1, [did UTF8String], -1, SQLITE_TRANSIENT);

    BOOL found = NO;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        found = YES;
        PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
        account.did = did;

        // Handle
        const char *handleStr = (const char *)sqlite3_column_text(stmt, 1);
        if (handleStr) {
            account.handle = [NSString stringWithUTF8String:handleStr];
        }

        // Email
        const char *emailStr = (const char *)sqlite3_column_text(stmt, 2);
        if (emailStr) {
            account.email = [NSString stringWithUTF8String:emailStr];
        }

        // Password hash
        if (sqlite3_column_type(stmt, 3) == SQLITE_BLOB) {
            const void *hashBytes = sqlite3_column_blob(stmt, 3);
            int hashLen = sqlite3_column_bytes(stmt, 3);
            if (hashBytes && hashLen > 0) {
                account.passwordHash = [NSData dataWithBytes:hashBytes length:hashLen];
            }
        }

        // Password salt
        if (sqlite3_column_type(stmt, 4) == SQLITE_BLOB) {
            const void *saltBytes = sqlite3_column_blob(stmt, 4);
            int saltLen = sqlite3_column_bytes(stmt, 4);
            if (saltBytes && saltLen > 0) {
                account.passwordSalt = [NSData dataWithBytes:saltBytes length:saltLen];
            }
        }

        // Access JWT
        if (sqlite3_column_type(stmt, 5) == SQLITE_BLOB) {
            const void *jwtBytes = sqlite3_column_blob(stmt, 5);
            int jwtLen = sqlite3_column_bytes(stmt, 5);
            if (jwtBytes && jwtLen > 0) {
                account.accessJwt = [NSData dataWithBytes:jwtBytes length:jwtLen];
            }
        }

        // Refresh JWT
        if (sqlite3_column_type(stmt, 6) == SQLITE_BLOB) {
            const void *refreshBytes = sqlite3_column_blob(stmt, 6);
            int refreshLen = sqlite3_column_bytes(stmt, 6);
            if (refreshBytes && refreshLen > 0) {
                account.refreshJwt = [NSData dataWithBytes:refreshBytes length:refreshLen];
            }
        }

        // Timestamps
        account.createdAt = sqlite3_column_double(stmt, 7);
        account.updatedAt = sqlite3_column_double(stmt, 8);

        if (![txn createAccount:account error:error]) {
            sqlite3_finalize(stmt);
            return NO;
        }
    }

    sqlite3_finalize(stmt);
    return found;
}

- (BOOL)migrateReposForDID:(NSString *)did from:(sqlite3 *)sourceDb to:(id<PDSActorStoreTransactor>)txn error:(NSError **)error {
    const char *sql = "SELECT owner_did, root_cid, collection_data, created_at, updated_at FROM repos WHERE owner_did = ?";
    sqlite3_stmt *stmt = NULL;

    if (sqlite3_prepare_v2(sourceDb, sql, -1, &stmt, NULL) != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                         code:PDSMigrationErrorMigrationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to query repos"}];
        }
        return NO;
    }

    sqlite3_bind_text(stmt, 1, [did UTF8String], -1, SQLITE_TRANSIENT);

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        PDSDatabaseRepo *repo = [[PDSDatabaseRepo alloc] init];
        repo.ownerDid = did;

        // Root CID
        if (sqlite3_column_type(stmt, 1) == SQLITE_BLOB) {
            const void *cidBytes = sqlite3_column_blob(stmt, 1);
            int cidLen = sqlite3_column_bytes(stmt, 1);
            if (cidBytes && cidLen > 0) {
                repo.rootCid = [NSData dataWithBytes:cidBytes length:cidLen];
            }
        }

        // Collection data
        if (sqlite3_column_type(stmt, 2) == SQLITE_BLOB) {
            const void *collBytes = sqlite3_column_blob(stmt, 2);
            int collLen = sqlite3_column_bytes(stmt, 2);
            if (collBytes && collLen > 0) {
                repo.collectionData = [NSData dataWithBytes:collBytes length:collLen];
            }
        }

        // Timestamps
        NSTimeInterval createdTime = sqlite3_column_double(stmt, 3);
        NSTimeInterval updatedTime = sqlite3_column_double(stmt, 4);
        repo.createdAt = [NSDate dateWithTimeIntervalSince1970:createdTime];
        repo.updatedAt = [NSDate dateWithTimeIntervalSince1970:updatedTime];

        if (![txn createRepo:repo error:error]) {
            sqlite3_finalize(stmt);
            return NO;
        }
    }

    sqlite3_finalize(stmt);
    return YES;
}

- (BOOL)migrateRecordsForDID:(NSString *)did from:(sqlite3 *)sourceDb to:(id<PDSActorStoreTransactor>)txn error:(NSError **)error {
    const char *sql = "SELECT uri, did, collection, rkey, cid, created_at FROM records WHERE did = ?";
    sqlite3_stmt *stmt = NULL;

    if (sqlite3_prepare_v2(sourceDb, sql, -1, &stmt, NULL) != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                         code:PDSMigrationErrorMigrationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to query records"}];
        }
        return NO;
    }

    sqlite3_bind_text(stmt, 1, [did UTF8String], -1, SQLITE_TRANSIENT);

    NSMutableArray<PDSDatabaseRecord *> *records = [NSMutableArray array];

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        PDSDatabaseRecord *record = [[PDSDatabaseRecord alloc] init];

        // URI
        const char *uriStr = (const char *)sqlite3_column_text(stmt, 0);
        if (uriStr) {
            record.uri = [NSString stringWithUTF8String:uriStr];
        }

        // DID
        const char *didStr = (const char *)sqlite3_column_text(stmt, 1);
        if (didStr) {
            record.did = [NSString stringWithUTF8String:didStr];
        }

        // Collection
        const char *collStr = (const char *)sqlite3_column_text(stmt, 2);
        if (collStr) {
            record.collection = [NSString stringWithUTF8String:collStr];
        }

        // RKey
        const char *rkeyStr = (const char *)sqlite3_column_text(stmt, 3);
        if (rkeyStr) {
            record.rkey = [NSString stringWithUTF8String:rkeyStr];
        }

        // CID (kept as string in PDSDatabaseRecord)
        const char *cidStr = (const char *)sqlite3_column_text(stmt, 4);
        if (cidStr) {
            record.cid = [NSString stringWithUTF8String:cidStr];
        }

        // Timestamp
        NSTimeInterval createdTime = sqlite3_column_double(stmt, 5);
        record.createdAt = [NSDate dateWithTimeIntervalSince1970:createdTime];

        // No indexed_at, rev, value, subject_did in source - set reasonable defaults
        record.rev = nil;

        [records addObject:record];
    }

    sqlite3_finalize(stmt);

    // Batch insert records for performance
    if (records.count > 0) {
        if (![txn putRecords:records forDid:did error:error]) {
            return NO;
        }
    }

    return YES;
}

- (BOOL)migrateBlocksForDID:(NSString *)did from:(sqlite3 *)sourceDb to:(id<PDSActorStoreTransactor>)txn error:(NSError **)error {
    const char *sql = "SELECT cid, repo_did, block_data, content_type, size, created_at FROM blocks WHERE repo_did = ?";
    sqlite3_stmt *stmt = NULL;

    if (sqlite3_prepare_v2(sourceDb, sql, -1, &stmt, NULL) != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                         code:PDSMigrationErrorMigrationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to query blocks"}];
        }
        return NO;
    }

    sqlite3_bind_text(stmt, 1, [did UTF8String], -1, SQLITE_TRANSIENT);

    NSMutableArray<PDSDatabaseBlock *> *blocks = [NSMutableArray array];

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        PDSDatabaseBlock *block = [[PDSDatabaseBlock alloc] init];

        // CID (already BLOB in source, store as-is)
        if (sqlite3_column_type(stmt, 0) == SQLITE_BLOB) {
            const void *cidBytes = sqlite3_column_blob(stmt, 0);
            int cidLen = sqlite3_column_bytes(stmt, 0);
            if (cidBytes && cidLen > 0) {
                block.cid = [NSData dataWithBytes:cidBytes length:cidLen];
            }
        }

        // Repo DID
        const char *repoDidStr = (const char *)sqlite3_column_text(stmt, 1);
        if (repoDidStr) {
            block.repoDid = [NSString stringWithUTF8String:repoDidStr];
        }

        // Block data
        if (sqlite3_column_type(stmt, 2) == SQLITE_BLOB) {
            const void *dataBytes = sqlite3_column_blob(stmt, 2);
            int dataLen = sqlite3_column_bytes(stmt, 2);
            if (dataBytes && dataLen > 0) {
                block.blockData = [NSData dataWithBytes:dataBytes length:dataLen];
            }
        }

        // Content type
        const char *contentTypeStr = (const char *)sqlite3_column_text(stmt, 3);
        if (contentTypeStr) {
            block.contentType = [NSString stringWithUTF8String:contentTypeStr];
        }

        // Size
        block.size = sqlite3_column_int64(stmt, 4);

        // Created at timestamp
        NSTimeInterval createdTime = sqlite3_column_double(stmt, 5);
        block.createdAt = [NSDate dateWithTimeIntervalSince1970:createdTime];

        // No rev in source
        block.rev = nil;

        [blocks addObject:block];
    }

    sqlite3_finalize(stmt);

    // Batch insert blocks for performance
    if (blocks.count > 0) {
        if (![txn putBlocks:blocks forDid:did error:error]) {
            return NO;
        }
    }

    return YES;
}

- (NSData *)convertCIDStringToData:(NSString *)cidString {
    // For now, treat the CID string as UTF8 bytes
    // In a real implementation, this might decode base32/base58 CIDs
    return [cidString dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSString *)convertUnixTimestampToISO8601:(NSTimeInterval)timestamp {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:timestamp];
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    return [formatter stringFromDate:date];
}

@end

#pragma mark - Blobs MimeType Column Rename

@interface BlobsMimeTypeRename : NSObject <PDSMigration>
@property (nonatomic) NSInteger migrationVersion;
- (instancetype)initWithVersion:(NSInteger)version;
@end

@implementation BlobsMimeTypeRename

- (instancetype)initWithVersion:(NSInteger)version {
    if ((self = [super init])) {
        _migrationVersion = version;
    }
    return self;
}

- (NSInteger)version {
    return _migrationVersion;
}

- (NSString *)name {
    return @"blobs_mime_type_rename";
}

- (BOOL)up:(sqlite3 *)db error:(NSError **)error {
    char *errMsg = NULL;
    int rc = sqlite3_exec(db, "ALTER TABLE blobs RENAME COLUMN mime_type TO mimeType", NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        // "no such column" means the column was already renamed — treat as success.
        BOOL alreadyRenamed = errMsg && strstr(errMsg, "no such column") != NULL;
        if (errMsg) sqlite3_free(errMsg);
        if (alreadyRenamed) return YES;
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                         code:PDSMigrationErrorMigrationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"blobs RENAME COLUMN failed"}];
        }
        return NO;
    }
    if (errMsg) sqlite3_free(errMsg);
    return YES;
}

- (BOOL)down:(sqlite3 *)db error:(NSError **)error {
    char *errMsg = NULL;
    int rc = sqlite3_exec(db, "ALTER TABLE blobs RENAME COLUMN mimeType TO mime_type", NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSString *msg = errMsg ? [NSString stringWithUTF8String:errMsg] : @"unknown error";
        if (errMsg) sqlite3_free(errMsg);
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                         code:PDSMigrationErrorMigrationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: msg}];
        }
        return NO;
    }
    if (errMsg) sqlite3_free(errMsg);
    return YES;
}

@end

#pragma mark - Convenience Factory Methods

@implementation PDSMigrationManager (Factory)

+ (instancetype)serviceDatabaseMigrationManager {
    PDSMigrationManager *manager = [[PDSMigrationManager alloc] init];
    [manager registerMigration:[[V1InitialSchema alloc] initWithSchemaType:@"service"]];
    [manager registerMigration:[[V2OzoneSchema alloc] init]];
    [manager registerMigration:[[V3DiagnosticsSchema alloc] init]];
    [manager registerMigration:[[V4OzoneScheduledActionsSchema alloc] init]];
    [manager registerMigration:[[V5HostingEventsSchema alloc] init]];
    [manager registerMigration:[[V6DraftsSchema alloc] init]];
    [manager registerMigration:[[V7SearchFTS5Schema alloc] init]];
    [manager registerMigration:[[V8OzoneSubjectsSchema alloc] init]];
    [manager registerMigration:[[BlobsMimeTypeRename alloc] initWithVersion:9]];
    return manager;
}

+ (instancetype)actorStoreMigrationManager {
    PDSMigrationManager *manager = [[PDSMigrationManager alloc] init];
    [manager registerMigration:[[V1InitialSchema alloc] initWithSchemaType:@"actor"]];
    [manager registerMigration:[[BlobsMimeTypeRename alloc] initWithVersion:2]];
    return manager;
}

@end
