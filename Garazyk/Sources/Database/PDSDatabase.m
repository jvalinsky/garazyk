// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase.h"
#import <sqlite3.h>
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Compat/PDSTypes.h"
#import "Database/Schema.h"
#import "Identity/ATProtoHandleValidator.h"
#import "Debug/GZLogger.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Database/Migration/PDSMigrationExecutor.h"
#import "Database/Migration/PDSServiceMigration001.h"
#import "Database/Migration/PDSServiceMigration002.h"
#if !defined(__linux__) && !defined(__GNUstep__)
#import <Security/Security.h>
#endif

// Suppress -Wblock-capture-autoreleasing: all block captures in this file
// use dispatch_sync (via safeExecuteSync:), which completes before the
// method returns, so the autorelease pool is still valid.
#pragma clang diagnostic ignored "-Wblock-capture-autoreleasing"

NSString * const PDSDatabaseErrorDomain = @"com.atproto.pds.database";
static const void *kPDSDatabaseQueueKey = &kPDSDatabaseQueueKey;

// Explicit column lists for tables with migration-added columns.
// Using named columns instead of SELECT * prevents index-shift bugs
// when ALTER TABLE adds columns in different orders on migrated vs.
// fresh databases.
// Note: kAccountsColumns moved to PDSDatabase+Accounts.m

#import "Database/PDSDatabase+Private.h"

@interface PDSDatabase ()

@property (nonatomic, readwrite) NSURL *databaseURL;
@property (nonatomic, readwrite) BOOL isOpen;
@property (nonatomic, assign) sqlite3 *db;
@property (nonatomic, strong) NSMutableDictionary *statementCache;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t dbQueue;
@property (nonatomic, strong) NSMutableArray<NSString *> *statementCacheOrder;

@end

@implementation PDSDatabase

- (instancetype)init {
    self = [super init];
    if (self) {
        _statementCache = [NSMutableDictionary dictionary];
        _statementCacheOrder = [NSMutableArray array];
        _dbQueue = dispatch_queue_create("com.atproto.pds.database.db", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_dbQueue, kPDSDatabaseQueueKey, (void *)kPDSDatabaseQueueKey, NULL);
    }
    return self;
}

- (void *)internalSQLiteHandle {
    return _db;
}

- (void)safeExecuteSync:(void(^)(void))block {
    if (dispatch_get_specific(kPDSDatabaseQueueKey)) {
        block();
    } else {
        dispatch_sync(self.dbQueue, block);
    }
}

+ (instancetype)databaseAtURL:(NSURL *)url {
    PDSDatabase *database = [[PDSDatabase alloc] init];
    database.databaseURL = url;
    database.isOpen = NO;
    database.db = NULL;
    return database;
}

- (BOOL)openWithError:(NSError **)error {
    if (self.isOpen) {
        return YES;
    }

    // Ensure parent directory exists
    NSURL *parentDir = [self.databaseURL URLByDeletingLastPathComponent];
    if (![[NSFileManager defaultManager] fileExistsAtPath:parentDir.path]) {
        NSError *dirError = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtURL:parentDir
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&dirError]) {
            if (error) {
                *error = [NSError errorWithDomain:PDSDatabaseErrorDomain
                                             code:PDSDatabaseErrorNotOpen
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to create database directory: %@", dirError.localizedDescription]}];
            }
            return NO;
        }
    }

    __block BOOL result = NO;
    [self safeExecuteSync:^{
        int rc = sqlite3_open(self.databaseURL.path.fileSystemRepresentation, &_db);
        if (rc != SQLITE_OK) {
            if (error) {
                *error = [NSError errorWithDomain:PDSDatabaseErrorDomain
                                             code:PDSDatabaseErrorNotOpen
                                         userInfo:@{NSLocalizedDescriptionKey: @(sqlite3_errmsg(_db))}];
            }
            result = NO;
            return;
        }

        sqlite3_busy_timeout(_db, 5000);

        // Mark database as open immediately so subsequent operations (including migrations)
        // can execute. This must be set before running migrations that use executeParameterizedUpdate.
        self.isOpen = YES;

        [self setPerformanceOptimizations:error];
        [self setWalMode:error];
        [self createSchema:error];

        // Run pending migrations
        PDSMigrationExecutor *executor = [[PDSMigrationExecutor alloc] init];
        NSArray *migrations = @[
            [[PDSServiceMigration001 alloc] init],
            [[PDSServiceMigration002 alloc] init],
            // Future migrations go here
        ];
        if (![executor executePendingMigrationsOnDatabase:self migrations:migrations error:error]) {
            GZ_LOG_DB_ERROR(@"Failed to execute pending migrations: %@", *error);
            [self close];  // Clean up on failure
            result = NO;
            return;
        }

        result = self.isOpen;
    }];

    return result;
}



- (void)close {
    if (!_db) {
        return;
    }

    [self safeExecuteSync:^{
        if (!_db) return;

        // Finalize all cached statements
        for (NSValue *stmtValue in [self.statementCache allValues]) {
            sqlite3_stmt *stmt = [stmtValue pointerValue];
            sqlite3_finalize(stmt);
        }
        [self.statementCache removeAllObjects];
        [self.statementCacheOrder removeAllObjects];
        self.statementCache = nil;
        self.statementCacheOrder = nil;

        // Use sqlite3_close_v2 which safely handles virtual table
        // internal statements (e.g., FTS5 content= sync tables).
        // Manual stray statement finalization via sqlite3_next_stmt
        // can corrupt virtual table internals and crash.
        sqlite3_close_v2(_db);
        _db = NULL;
    }];

    self.isOpen = NO;
    GZ_LOG_DB_DEBUG(@"Database connection closed");
}

- (void)dealloc {
    [self close];
}

- (sqlite3_stmt *)preparedStatementForQuery:(NSString *)query {
    __block sqlite3_stmt *stmt = NULL;
    [self safeExecuteSync:^{
        NSValue *stmtValue = self.statementCache[query];
        if (stmtValue) {
            stmt = [stmtValue pointerValue];
            sqlite3_reset(stmt);
            [self.statementCacheOrder removeObject:query];
            [self.statementCacheOrder addObject:query];
            return;
        }

        if (sqlite3_prepare_v2(_db, [query UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
            if (self.statementCacheOrder.count >= 100) {
                NSString *keyToRemove = self.statementCacheOrder.firstObject;
                if (keyToRemove) {
                    [self.statementCacheOrder removeObjectAtIndex:0];
                    NSValue *staleValue = self.statementCache[keyToRemove];
                    if (staleValue) {
                        sqlite3_finalize([staleValue pointerValue]);
                        [self.statementCache removeObjectForKey:keyToRemove];
                    }
                }
            }

            self.statementCache[query] = [NSValue valueWithPointer:stmt];
            [self.statementCacheOrder addObject:query];
        } else {
            stmt = NULL;
        }
    }];
    return stmt;
}

- (BOOL)prepareStatement:(sqlite3_stmt **)stmt sql:(NSString *)sql error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        }
        result = NO;
        return;
    }
    result = YES;
    return;
    }];
    return result;
}

- (BOOL)setWalMode:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    char *errMsg = NULL;
    int rc = sqlite3_exec(_db, "PRAGMA journal_mode=WAL", NULL, NULL, &errMsg);
    if (rc != SQLITE_OK && errMsg) {
        NSError *e = [NSError errorWithDomain:PDSDatabaseErrorDomain
                                         code:PDSDatabaseErrorQueryFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @(errMsg)}];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }
    result = YES;
    return;
    }];
    return result;
}

- (BOOL)setPerformanceOptimizations:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    char *errMsg = NULL;
    int rc;

    rc = sqlite3_exec(_db, "PRAGMA synchronous=NORMAL", NULL, NULL, &errMsg);
    if (rc != SQLITE_OK && errMsg) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

#if DEBUG
    rc = sqlite3_exec(_db, "PRAGMA cache_size=64", NULL, NULL, &errMsg);
#else
    rc = sqlite3_exec(_db, "PRAGMA cache_size=65536", NULL, NULL, &errMsg);
#endif
    if (rc != SQLITE_OK && errMsg) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, "PRAGMA temp_store=MEMORY", NULL, NULL, &errMsg);
    if (rc != SQLITE_OK && errMsg) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

#if DEBUG
    rc = sqlite3_exec(_db, "PRAGMA mmap_size=4194304", NULL, NULL, &errMsg);
#else
    rc = sqlite3_exec(_db, "PRAGMA mmap_size=268435456", NULL, NULL, &errMsg);
#endif
    if (rc != SQLITE_OK && errMsg) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, "PRAGMA page_size=65536", NULL, NULL, &errMsg);
    if (rc != SQLITE_OK && errMsg) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    result = YES;

    return;
    }];
    return result;
}

- (BOOL)createSchema:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    char *errMsg = NULL;
    int rc = sqlite3_exec(_db, [kPDSAccountTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSRepoTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSRecordTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSBlockTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSBlobTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexBlocksRepoDidSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexBlobsDidSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexAccountsHandleSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSInviteCodeTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSAdminTakedownTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSAdminAuditLogTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSReportsTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSAdminConfigTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexInviteCodesAccountDidSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexTakedownsSubjectIdSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexAuditLogAdminSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexAuditLogSubjectSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexAuditLogCreatedSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexReportsStatusSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexReportsSubjectSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexReportsReportedBySQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexReportsCreatedSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSPasskeysTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSOAuthClientsTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSLabelTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSReservedHandleTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexLabelsUriSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexLabelsSourceSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexReservedHandlesHandleSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSJWTSigningKeysTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexPasskeysAccountDidSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexPasskeysCredentialIdSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSBookmarkTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSStarterPackTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexBookmarksDidSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexStarterPacksDidSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    // Chat tables
    rc = sqlite3_exec(_db, [kPDSConversationsTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSConversationMembersTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSMessagesTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSMessageReactionsTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexConversationMembersConvoSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexConversationMembersActorSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexMessagesConvoSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexMessagesCreatedSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    // Group tables
    rc = sqlite3_exec(_db, [kPDSGroupsTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSGroupMembersTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSGroupInviteLinksTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSGroupJoinRequestsTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexGroupMembersGroupSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexGroupMembersMemberSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexGroupInviteLinksGroupSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexGroupJoinRequestsGroupSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexGroupJoinRequestsRequesterSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSGroupMessagesTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSGroupMessageReactionsTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexGroupMessagesGroupSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSIndexGroupMessagesCreatedSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSVideoJobsTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSVideoJobsIndexDidSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSVideoJobsIndexStateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    rc = sqlite3_exec(_db, [kPDSVideoJobsIndexCreatedSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    errMsg = NULL;
    NSString *refreshTokensSQL = @"CREATE TABLE IF NOT EXISTS refresh_tokens ("
                                 @"token TEXT PRIMARY KEY,"
                                 @"account_did TEXT NOT NULL,"
                                 @"created_at REAL NOT NULL,"
                                 @"expires_at REAL NOT NULL"
                                 @")";
    rc = sqlite3_exec(_db, refreshTokensSQL.UTF8String, NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    errMsg = NULL;
    NSString *refreshTokensIndexSQL = @"CREATE INDEX IF NOT EXISTS idx_refresh_tokens_did ON refresh_tokens(account_did)";
    rc = sqlite3_exec(_db, refreshTokensIndexSQL.UTF8String, NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    // Inline ALTERs removed — all schema evolution is now handled by
    // versioned migrations (PDSServiceMigration002+). Columns that
    // were previously added here (password_salt, tfa_enabled, etc.)
    // are already in the CREATE TABLE statements for fresh databases,
    // and are added to old databases by the migration system.

    if (errMsg) sqlite3_free(errMsg);

    result = YES;

    return;
    }];
    return result;
}

- (BOOL)executeUnsafeRawSQL:(NSString *)sql error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    if (!self.isOpen) {
        if (error) {
            *error = [NSError errorWithDomain:PDSDatabaseErrorDomain
                                         code:PDSDatabaseErrorNotOpen
                                     userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Database is not open (path=%@, called from %s)", self.databaseURL.path ?: @"<unknown>", __func__]}];
        }
        result = NO;
        return;
    }

    char *errMsg = NULL;
    int rc = sqlite3_exec(_db, sql.UTF8String, NULL, NULL, &errMsg);

    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    result = YES;

    return;
    }];
    return result;
}

- (NSArray<NSDictionary *> *)executeUnsafeRawQuery:(NSString *)sql error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    if (!self.isOpen) {
        if (error) {
            *error = [NSError errorWithDomain:PDSDatabaseErrorDomain
                                         code:PDSDatabaseErrorNotOpen
                                     userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Database is not open (path=%@, called from %s)", self.databaseURL.path ?: @"<unknown>", __func__]}];
        }
        result = @[];
        return;
    }

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);

    if (rc != SQLITE_OK) {
        if (error) {
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        }
        result = @[];
        return;
    }

    NSMutableArray *results = [NSMutableArray array];
    int columnCount = sqlite3_column_count(stmt);

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        NSMutableDictionary *row = [NSMutableDictionary dictionary];
        for (int i = 0; i < columnCount; i++) {
            NSString *columnName = @(sqlite3_column_name(stmt, i));
            id value = [self valueFromStatement:stmt columnIndex:i];
            if (value) {
                row[columnName] = value;
            }
        }
        [results addObject:row];
    }

    result = results;

    return;
    }];
    return result;
}

- (id)valueFromStatement:(sqlite3_stmt *)stmt columnIndex:(int)colIndex {
    __block id result = nil;
    [self safeExecuteSync:^{

    int type = sqlite3_column_type(stmt, colIndex);
    switch (type) {
        case SQLITE_INTEGER:
            result = @(sqlite3_column_int64(stmt, colIndex));
            return;
        case SQLITE_FLOAT:
            result = @(sqlite3_column_double(stmt, colIndex));
            return;
        case SQLITE_BLOB: {
            const void *bytes = sqlite3_column_blob(stmt, colIndex);
            int size = sqlite3_column_bytes(stmt, colIndex);
            result = [NSData dataWithBytes:bytes length:size];
            return;
        }
        case SQLITE_TEXT: {
            const unsigned char *text = sqlite3_column_text(stmt, colIndex);
            result = @((const char *)text);
            return;
        }
        case SQLITE_NULL:
        default:
            result = nil;
            return;
    }
    }];
    return result;
}

- (NSError *)errorWithMessage:(const char *)message code:(NSInteger)code {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *msg = message ? @(message) : @"Unknown error";
    result = [NSError errorWithDomain:PDSDatabaseErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: msg}];
    return;
    }];
    return result;
}

- (NSError *)errorWithDescription:(NSString *)message code:(NSInteger)code {
    __block id result = nil;
    [self safeExecuteSync:^{

    result = [NSError errorWithDomain:PDSDatabaseErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Unknown error"}];

    return;
    }];
    return result;
}

#pragma mark - Parameterized Queries

- (NSArray<NSDictionary *> *)executeParameterizedQuery:(NSString *)sql
                                                params:(NSArray *)params
                                                 error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    if (!self.isOpen) {
        if (error) {
            *error = [self errorWithMessage:"Database is not open" code:PDSDatabaseErrorNotOpen];
        }
        result = @[];
        return;
    }

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);

    if (rc != SQLITE_OK) {
        if (error) {
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        }
        result = @[];
        return;
    }

    for (NSUInteger i = 0; i < params.count; i++) {
        id param = params[i];
        int paramIndex = (int)(i + 1);

        if (param == [NSNull null]) {
            sqlite3_bind_null(stmt, paramIndex);
        } else if ([param isKindOfClass:[NSString class]]) {
            sqlite3_bind_text(stmt, paramIndex, [param UTF8String], -1, SQLITE_TRANSIENT);
        } else if ([param isKindOfClass:[NSNumber class]]) {
            const char *objCType = [param objCType];
            if (strcmp(objCType, @encode(double)) == 0 || 
                strcmp(objCType, @encode(float)) == 0) {
                sqlite3_bind_double(stmt, paramIndex, [param doubleValue]);
            } else {
                sqlite3_bind_int64(stmt, paramIndex, [param longLongValue]);
            }
        } else if ([param isKindOfClass:[NSData class]]) {
            sqlite3_bind_blob(stmt, paramIndex, [param bytes], (int)[param length], SQLITE_STATIC);
        }
    }

    NSMutableArray *results = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        NSMutableDictionary *row = [NSMutableDictionary dictionary];
        for (int i = 0; i < sqlite3_column_count(stmt); i++) {
            NSString *columnName = @(sqlite3_column_name(stmt, i));
            id value = [self valueFromStatement:stmt columnIndex:i];
            if (value) {
                row[columnName] = value;
            }
        }
        [results addObject:row];
    }

    result = results;

    return;
    }];
    return result;
}

- (nullable NSArray *)executeParameterizedQuery:(NSString *)sql
                                         params:(NSArray *)params
                                     modelClass:(Class<PDSDatabaseModel>)modelClass
                                          error:(NSError **)error {
    NSArray<NSDictionary *> *rows = [self executeParameterizedQuery:sql params:params error:error];
    if (!rows) return nil;

    NSMutableArray *models = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSDictionary *row in rows) {
        id model = [[(Class)modelClass alloc] initWithDatabaseRow:row];
        if (model) {
            [models addObject:model];
        }
    }
    return [models copy];
}

- (BOOL)executeParameterizedUpdate:(NSString *)sql
                            params:(NSArray *)params
                             error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    if (!self.isOpen) {
        if (error) {
            *error = [self errorWithMessage:"Database is not open" code:PDSDatabaseErrorNotOpen];
        }
        result = NO;
        return;
    }

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);

    if (rc != SQLITE_OK) {
        if (error) {
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        }
        result = NO;
        return;
    }

    for (NSUInteger i = 0; i < params.count; i++) {
        id param = params[i];
        int paramIndex = (int)(i + 1);

        if (param == [NSNull null]) {
            sqlite3_bind_null(stmt, paramIndex);
        } else if ([param isKindOfClass:[NSString class]]) {
            sqlite3_bind_text(stmt, paramIndex, [param UTF8String], -1, SQLITE_TRANSIENT);
        } else if ([param isKindOfClass:[NSNumber class]]) {
            const char *objCType = [param objCType];
            if (strcmp(objCType, @encode(double)) == 0 || 
                strcmp(objCType, @encode(float)) == 0) {
                sqlite3_bind_double(stmt, paramIndex, [param doubleValue]);
            } else {
                sqlite3_bind_int64(stmt, paramIndex, [param longLongValue]);
            }
        } else if ([param isKindOfClass:[NSData class]]) {
            sqlite3_bind_blob(stmt, paramIndex, [param bytes], (int)[param length], SQLITE_STATIC);
        }
    }

    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);

    if (!success && error) {
        *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
    }

    result = success;

    return;
    }];
    return result;
}

@end


