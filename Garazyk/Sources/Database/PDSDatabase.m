#import "Database/PDSDatabase.h"
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Compat/PDSTypes.h"
#import "Database/Schema.h"
#import "Identity/ATProtoHandleValidator.h"
#import "Debug/PDSLogger.h"
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
static NSString *const kAccountsColumns = @"did, handle, email, password_hash, "
    @"password_salt, access_jwt, refresh_jwt, created_at, updated_at, "
    @"tfa_enabled, tfa_secret, recovery_codes, invite_enabled, "
    @"age_assurance, age_verified_at, webauthn_enabled";

static NSString *const kRecordsColumns = @"uri, did, collection, rkey, cid, "
    @"value, subject_did, created_at, indexed_at";

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
            PDS_LOG_DB_ERROR(@"Failed to execute pending migrations: %@", *error);
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
    PDS_LOG_DB_DEBUG(@"Database connection closed");
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

    rc = sqlite3_exec(_db, "PRAGMA cache_size=65536", NULL, NULL, &errMsg);
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

    rc = sqlite3_exec(_db, "PRAGMA mmap_size=268435456", NULL, NULL, &errMsg);
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

- (BOOL)executeRawSQL:(NSString *)sql error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    if (!self.isOpen) {
        if (error) {
            *error = [NSError errorWithDomain:PDSDatabaseErrorDomain
                                         code:PDSDatabaseErrorNotOpen
                                     userInfo:@{NSLocalizedDescriptionKey:@"Database is not open"}];
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

- (NSArray<NSDictionary *> *)executeQuery:(NSString *)sql error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    if (!self.isOpen) {
        if (error) {
            *error = [NSError errorWithDomain:PDSDatabaseErrorDomain
                                         code:PDSDatabaseErrorNotOpen
                                     userInfo:@{NSLocalizedDescriptionKey:@"Database is not open"}];
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

#pragma mark - Accounts

- (BOOL)createAccount:(PDSDatabaseAccount *)account error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    // Validate handle
    if (![ATProtoHandleValidator validateHandle:account.handle error:error]) {
        result = NO;
        return;
    }
    account.handle = [ATProtoHandleValidator normalizeHandle:account.handle];

    NSString *sql = @"INSERT INTO accounts (did, handle, email, password_hash, password_salt, access_jwt, refresh_jwt, status, deactivated_at, created_at, updated_at, tfa_enabled, tfa_secret, recovery_codes, invite_enabled) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    sqlite3_bind_text(stmt, 1, account.did.UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, account.handle.UTF8String, -1, SQLITE_STATIC);
    if (account.email) {
        sqlite3_bind_text(stmt, 3, account.email.UTF8String, -1, SQLITE_STATIC);
    } else {
        sqlite3_bind_null(stmt, 3);
    }
    [self bindData:account.passwordHash toStatement:stmt index:4];
    [self bindData:account.passwordSalt toStatement:stmt index:5];
    [self bindData:account.accessJwt toStatement:stmt index:6];
    [self bindData:account.refreshJwt toStatement:stmt index:7];
    sqlite3_bind_text(stmt, 8, account.status.UTF8String ?: "active", -1, SQLITE_STATIC);
    if (account.deactivatedAt > 0) {
        sqlite3_bind_double(stmt, 9, account.deactivatedAt);
    } else {
        sqlite3_bind_null(stmt, 9);
    }
    sqlite3_bind_text(stmt, 10, [self iso8601StringFromDate:[NSDate dateWithTimeIntervalSince1970:account.createdAt]].UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 11, [self iso8601StringFromDate:[NSDate date]].UTF8String, -1, SQLITE_STATIC);
    // 2FA columns (defaults)
    sqlite3_bind_int(stmt, 12, account.tfaEnabled ? 1 : 0);
    [self bindData:account.tfaSecret toStatement:stmt index:13];
    [self bindData:account.recoveryCodes toStatement:stmt index:14];
    sqlite3_bind_int(stmt, 15, account.inviteEnabled ? 1 : 0);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        if (error) {
            NSInteger errorCode = (rc == SQLITE_CONSTRAINT) ? PDSDatabaseErrorConstraintViolation : PDSDatabaseErrorQueryFailed;
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:errorCode];
        }
        result = NO;
        return;
    }

    result = YES;

    return;
    }];
    return result;
}

- (BOOL)updateAccount:(PDSDatabaseAccount *)account error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    // Validate handle
    if (![ATProtoHandleValidator validateHandle:account.handle error:error]) {
        result = NO;
        return;
    }
    account.handle = [ATProtoHandleValidator normalizeHandle:account.handle];

    NSString *sql = @"UPDATE accounts SET handle = ?, email = ?, password_hash = ?, password_salt = ?, access_jwt = ?, refresh_jwt = ?, updated_at = ?, tfa_enabled = ?, tfa_secret = ?, recovery_codes = ?, invite_enabled = ? WHERE did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    sqlite3_bind_text(stmt, 1, account.handle.UTF8String, -1, SQLITE_STATIC);
    if (account.email) {
        sqlite3_bind_text(stmt, 2, account.email.UTF8String, -1, SQLITE_STATIC);
    } else {
        sqlite3_bind_null(stmt, 2);
    }
    [self bindData:account.passwordHash toStatement:stmt index:3];
    [self bindData:account.passwordSalt toStatement:stmt index:4];
    [self bindData:account.accessJwt toStatement:stmt index:5];
    [self bindData:account.refreshJwt toStatement:stmt index:6];
    sqlite3_bind_text(stmt, 7, [self iso8601StringFromDate:[NSDate dateWithTimeIntervalSince1970:account.updatedAt]].UTF8String, -1, SQLITE_STATIC);
    
    // 2FA
    sqlite3_bind_int(stmt, 8, account.tfaEnabled ? 1 : 0);
    [self bindData:account.tfaSecret toStatement:stmt index:9];
    [self bindData:account.recoveryCodes toStatement:stmt index:10];
    sqlite3_bind_int(stmt, 11, account.inviteEnabled ? 1 : 0);

    // WHERE did = ?
    sqlite3_bind_text(stmt, 12, account.did.UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        if (error) {
            NSInteger errorCode = (rc == SQLITE_CONSTRAINT) ? PDSDatabaseErrorConstraintViolation : PDSDatabaseErrorQueryFailed;
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:errorCode];
        }
        result = NO;
        return;
    }

    result = YES;

    return;
    }];
    return result;
}

- (nullable PDSDatabaseAccount *)getAccountByDid:(NSString *)did error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = [NSString stringWithFormat:@"SELECT %@ FROM accounts WHERE did = ?", kAccountsColumns];

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = nil;
        return;
    }

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_STATIC);

    PDSDatabaseAccount *account = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        account = [self accountFromStatement:stmt];
    }

    result = account;

    return;
    }];
    return result;
}

- (nullable PDSDatabaseAccount *)getAccountByHandle:(NSString *)handle error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = [NSString stringWithFormat:@"SELECT %@ FROM accounts WHERE handle = ?", kAccountsColumns];

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = nil;
        return;
    }

    NSString *normalizedHandle = [ATProtoHandleValidator normalizeHandle:handle];
    sqlite3_bind_text(stmt, 1, normalizedHandle.UTF8String, -1, SQLITE_STATIC);

    PDSDatabaseAccount *account = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        account = [self accountFromStatement:stmt];
    }

    result = account;

    return;
    }];
    return result;
}

- (nullable PDSDatabaseAccount *)getAccountByEmail:(NSString *)email error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = [NSString stringWithFormat:@"SELECT %@ FROM accounts WHERE email = ?", kAccountsColumns];

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = nil;
        return;
    }

    sqlite3_bind_text(stmt, 1, email.UTF8String, -1, SQLITE_STATIC);

    PDSDatabaseAccount *account = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        account = [self accountFromStatement:stmt];
    }

    result = account;

    return;
    }];
    return result;
}

- (nullable PDSDatabaseAccount *)getAccountByRefreshToken:(NSString *)refreshToken error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = [NSString stringWithFormat:@"SELECT %@ FROM accounts WHERE refresh_jwt = ?", kAccountsColumns];

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = nil;
        return;
    }

    // Convert NSString refreshToken to NSData for BLOB comparison
    NSData *refreshTokenData = [refreshToken dataUsingEncoding:NSUTF8StringEncoding];
    sqlite3_bind_blob(stmt, 1, refreshTokenData.bytes, (int)refreshTokenData.length, SQLITE_STATIC);

    PDSDatabaseAccount *account = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        account = [self accountFromStatement:stmt];
    }

    result = account;

    return;
    }];
    return result;
}



- (NSArray<PDSDatabaseAccount *> *)getAllAccountsWithError:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = [NSString stringWithFormat:@"SELECT %@ FROM accounts ORDER BY created_at DESC", kAccountsColumns];

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = @[];
        return;
    }

    NSMutableArray *accounts = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        PDSDatabaseAccount *account = [self accountFromStatement:stmt];
        if (account) {
            [accounts addObject:account];
        }
    }

    result = accounts;

    return;
    }];
    return result;
}

- (NSArray<PDSDatabaseAccount *> *)getAccountsWithLimit:(NSInteger)limit afterDid:(nullable NSString *)afterDid error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = afterDid
        ? [NSString stringWithFormat:@"SELECT %@ FROM accounts WHERE did > ? ORDER BY did ASC LIMIT ?", kAccountsColumns]
        : [NSString stringWithFormat:@"SELECT %@ FROM accounts ORDER BY did ASC LIMIT ?", kAccountsColumns];

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = @[];
        return;
    }

    int idx = 1;
    if (afterDid) {
        sqlite3_bind_text(stmt, idx++, afterDid.UTF8String, -1, SQLITE_TRANSIENT);
    }
    sqlite3_bind_int64(stmt, idx, (sqlite3_int64)limit);

    NSMutableArray *accounts = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        PDSDatabaseAccount *account = [self accountFromStatement:stmt];
        if (account) {
            [accounts addObject:account];
        }
    }

    result = accounts;

    return;
    }];
    return result;
}

- (BOOL)deleteAccount:(NSString *)did error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"DELETE FROM accounts WHERE did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    result = YES;

    return;
    }];
    return result;
}

#pragma mark - WebAuthn Credentials

- (BOOL)storeWebAuthnCredential:(NSDictionary *)credential forDid:(NSString *)did error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"INSERT OR REPLACE INTO webauthn_credentials (id, account_did, credential_id, public_key_cose, sign_count, aaguid, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    NSString *credentialId = [[NSUUID UUID] UUIDString];
    sqlite3_bind_text(stmt, 1, credentialId.UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, did.UTF8String, -1, SQLITE_STATIC);
    [self bindData:credential[@"credentialId"] toStatement:stmt index:3];
    [self bindData:credential[@"publicKey"] toStatement:stmt index:4];
    sqlite3_bind_int(stmt, 5, [credential[@"signCount"] intValue]);
    [self bindData:credential[@"aaguid"] toStatement:stmt index:6];
    sqlite3_bind_double(stmt, 7, [[NSDate date] timeIntervalSince1970]);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    result = YES;

    return;
    }];
    return result;
}

- (NSArray<NSDictionary *> *)getWebAuthnCredentialsForDid:(NSString *)did error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT * FROM webauthn_credentials WHERE account_did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = @[];
        return;
    }

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_STATIC);

    NSMutableArray *credentials = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        NSMutableDictionary *cred = [NSMutableDictionary dictionary];
        cred[@"id"] = @((const char *)sqlite3_column_text(stmt, 0));
        cred[@"accountDid"] = @((const char *)sqlite3_column_text(stmt, 1));

        int blobBytes = sqlite3_column_bytes(stmt, 2);
        if (blobBytes > 0) {
            cred[@"credentialId"] = [NSData dataWithBytes:sqlite3_column_blob(stmt, 2) length:blobBytes];
        }
        blobBytes = sqlite3_column_bytes(stmt, 3);
        if (blobBytes > 0) {
            cred[@"publicKey"] = [NSData dataWithBytes:sqlite3_column_blob(stmt, 3) length:blobBytes];
        }
        cred[@"signCount"] = @(sqlite3_column_int(stmt, 4));

        blobBytes = sqlite3_column_bytes(stmt, 5);
        if (blobBytes > 0) {
            cred[@"aaguid"] = [NSData dataWithBytes:sqlite3_column_blob(stmt, 5) length:blobBytes];
        }
        cred[@"createdAt"] = @((const char *)sqlite3_column_text(stmt, 6));

        [credentials addObject:cred];
    }

    result = credentials;

    return;
    }];
    return result;
}

- (BOOL)deleteWebAuthnCredential:(NSData *)credentialId forDid:(NSString *)did error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"DELETE FROM webauthn_credentials WHERE credential_id = ? AND account_did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    [self bindData:credentialId toStatement:stmt index:1];
    sqlite3_bind_text(stmt, 2, did.UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    result = YES;

    return;
    }];
    return result;
}

- (BOOL)updateWebAuthnCredentialSignCount:(NSData *)credentialId forDid:(NSString *)did signCount:(uint32_t)signCount error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"UPDATE webauthn_credentials SET sign_count = ? WHERE credential_id = ? AND account_did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    sqlite3_bind_int(stmt, 1, signCount);
    [self bindData:credentialId toStatement:stmt index:2];
    sqlite3_bind_text(stmt, 3, did.UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    result = YES;

    return;
    }];
    return result;
}

- (PDSDatabaseAccount *)accountFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = @((const char *)sqlite3_column_text(stmt, 0));
    account.handle = @((const char *)sqlite3_column_text(stmt, 1));
    
    const char *emailText = (const char *)sqlite3_column_text(stmt, 2);
    if (emailText) {
        account.email = @(emailText);
    }
    
    int blobBytes = sqlite3_column_bytes(stmt, 3);
    if (blobBytes > 0) {
        account.passwordHash = [NSData dataWithBytes:sqlite3_column_blob(stmt, 3) length:blobBytes];
    }
    
    blobBytes = sqlite3_column_bytes(stmt, 4);
    if (blobBytes > 0) {
        account.passwordSalt = [NSData dataWithBytes:sqlite3_column_blob(stmt, 4) length:blobBytes];
    }
    
    blobBytes = sqlite3_column_bytes(stmt, 5);
    if (blobBytes > 0) {
        account.accessJwt = [NSData dataWithBytes:sqlite3_column_blob(stmt, 5) length:blobBytes];
    }
    
    blobBytes = sqlite3_column_bytes(stmt, 6);
    if (blobBytes > 0) {
        account.refreshJwt = [NSData dataWithBytes:sqlite3_column_blob(stmt, 6) length:blobBytes];
    }

    const char *statusText = (const char *)sqlite3_column_text(stmt, 7);
    if (statusText) {
        account.status = @(statusText);
    } else {
        account.status = @"active";
    }

    if (sqlite3_column_type(stmt, 8) != SQLITE_NULL) {
        account.deactivatedAt = sqlite3_column_double(stmt, 8);
    }
    
    const char *createdAtText = (const char *)sqlite3_column_text(stmt, 9);
    if (createdAtText) {
        account.createdAt = [NSDateFormatter atproto_dateFromString:@(createdAtText)].timeIntervalSince1970;
    }
    
    const char *updatedAtText = (const char *)sqlite3_column_text(stmt, 10);
    if (updatedAtText) {
        account.updatedAt = [NSDateFormatter atproto_dateFromString:@(updatedAtText)].timeIntervalSince1970;
    }
    
    // 2FA
    account.tfaEnabled = (sqlite3_column_int(stmt, 11) != 0);
    
    blobBytes = sqlite3_column_bytes(stmt, 12);
    if (blobBytes > 0) {
        account.tfaSecret = [NSData dataWithBytes:sqlite3_column_blob(stmt, 12) length:blobBytes];
    }
    
    blobBytes = sqlite3_column_bytes(stmt, 13);
    if (blobBytes > 0) {
        account.recoveryCodes = [NSData dataWithBytes:sqlite3_column_blob(stmt, 13) length:blobBytes];
    }
    
    account.inviteEnabled = (sqlite3_column_int(stmt, 14) != 0);

    // Age assurance (columns 15, 16)
    const char *ageAssuranceText = (const char *)sqlite3_column_text(stmt, 15);
    if (ageAssuranceText) {
        account.ageAssurance = @(ageAssuranceText);
    }

    const char *ageVerifiedAtText = (const char *)sqlite3_column_text(stmt, 16);
    if (ageVerifiedAtText) {
        account.ageVerifiedAt = @(ageVerifiedAtText);
    }

    account.webauthnEnabled = (sqlite3_column_int(stmt, 17) != 0);
    
    return account;
}

- (PDSDatabaseRecord *)recordFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseRecord *record = [[PDSDatabaseRecord alloc] init];
    record.uri = @((const char *)sqlite3_column_text(stmt, 0));
    record.did = @((const char *)sqlite3_column_text(stmt, 1));
    record.collection = @((const char *)sqlite3_column_text(stmt, 2));
    record.rkey = @((const char *)sqlite3_column_text(stmt, 3));
    record.cid = @((const char *)sqlite3_column_text(stmt, 4));

    // Column 5: value (TEXT)
    const char *valueText = (const char *)sqlite3_column_text(stmt, 5);
    if (valueText) {
        record.value = @(valueText);
    }

    // Column 6: rev (TEXT)
    const char *revText = (const char *)sqlite3_column_text(stmt, 6);
    if (revText) {
        record.rev = @(revText);
    }

    // Column 7: subject_did (TEXT)
    const char *subjectDidText = (const char *)sqlite3_column_text(stmt, 7);
    if (subjectDidText) {
        record.subjectDid = @(subjectDidText);
    }

    // Column 8: created_at (TEXT)
    const char *createdAtText = (const char *)sqlite3_column_text(stmt, 8);
    if (createdAtText) {
        record.createdAt = [[NSDateFormatter atproto_iso8601Formatter] dateFromString:@(createdAtText)];
    }

    // Column 9: indexed_at (TEXT)
    const char *indexedAtText = (const char *)sqlite3_column_text(stmt, 9);
    if (indexedAtText) {
        record.indexedAt = [[NSDateFormatter atproto_iso8601Formatter] dateFromString:@(indexedAtText)];
    }

    return record;
}

#pragma mark - Repos

- (BOOL)createRepo:(PDSDatabaseRepo *)repo error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"INSERT INTO repos (owner_did, root_cid, collection_data, created_at, updated_at) VALUES (?, ?, ?, ?, ?)";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    sqlite3_bind_text(stmt, 1, repo.ownerDid.UTF8String, -1, SQLITE_STATIC);
    [self bindData:repo.rootCid toStatement:stmt index:2];
    [self bindData:repo.collectionData toStatement:stmt index:3];
    sqlite3_bind_text(stmt, 4, [self iso8601StringFromDate:repo.createdAt].UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 5, [self iso8601StringFromDate:repo.updatedAt].UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        if (error) {
            NSInteger errorCode = (rc == SQLITE_CONSTRAINT) ? PDSDatabaseErrorConstraintViolation : PDSDatabaseErrorQueryFailed;
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:errorCode];
        }
        result = NO;
        return;
    }

    result = YES;

    return;
    }];
    return result;
}

- (BOOL)updateRepoRoot:(NSString *)ownerDid rootCid:(NSData *)rootCid error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"UPDATE repos SET root_cid = ?, updated_at = ? WHERE owner_did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    [self bindData:rootCid toStatement:stmt index:1];
    sqlite3_bind_text(stmt, 2, [self iso8601StringFromDate:[NSDate date]].UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 3, ownerDid.UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
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

- (nullable PDSDatabaseRepo *)getRepoForDid:(NSString *)did error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT * FROM repos WHERE owner_did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = nil;
        return;
    }

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_STATIC);

    PDSDatabaseRepo *repo = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        repo = [self repoFromStatement:stmt];
    }

    result = repo;

    return;
    }];
    return result;
}

- (NSArray<PDSDatabaseRepo *> *)getAllReposWithError:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT * FROM repos ORDER BY updated_at DESC";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = @[];
        return;
    }

    NSMutableArray *repos = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        PDSDatabaseRepo *repo = [self repoFromStatement:stmt];
        if (repo) {
            [repos addObject:repo];
        }
    }

    result = repos;

    return;
    }];
    return result;
}

- (BOOL)deleteRepo:(NSString *)ownerDid error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"DELETE FROM repos WHERE owner_did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    sqlite3_bind_text(stmt, 1, ownerDid.UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    result = YES;

    return;
    }];
    return result;
}

- (PDSDatabaseRepo *)repoFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseRepo *repo = [[PDSDatabaseRepo alloc] init];
    repo.ownerDid = @((const char *)sqlite3_column_text(stmt, 0));
    
    int blobBytes = sqlite3_column_bytes(stmt, 1);
    if (blobBytes > 0) {
        repo.rootCid = [NSData dataWithBytes:sqlite3_column_blob(stmt, 1) length:blobBytes];
    }
    
    blobBytes = sqlite3_column_bytes(stmt, 2);
    if (blobBytes > 0) {
        repo.collectionData = [NSData dataWithBytes:sqlite3_column_blob(stmt, 2) length:blobBytes];
    }
    
    repo.createdAt = [self dateFromISO8601String:@((const char *)sqlite3_column_text(stmt, 3))];
    repo.updatedAt = [self dateFromISO8601String:@((const char *)sqlite3_column_text(stmt, 4))];
    
    return repo;
}

#pragma mark - Blocks

- (BOOL)saveBlock:(PDSDatabaseBlock *)block error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"INSERT OR REPLACE INTO blocks (cid, repo_did, block_data, content_type, size, created_at) VALUES (?, ?, ?, ?, ?, ?)";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    [self bindData:block.cid toStatement:stmt index:1];
    sqlite3_bind_text(stmt, 2, block.repoDid.UTF8String, -1, SQLITE_STATIC);
    [self bindData:block.blockData toStatement:stmt index:3];
    if (block.contentType) {
        sqlite3_bind_text(stmt, 4, block.contentType.UTF8String, -1, SQLITE_STATIC);
    } else {
        sqlite3_bind_null(stmt, 4);
    }
    sqlite3_bind_int64(stmt, 5, block.size);
    sqlite3_bind_text(stmt, 6, [self iso8601StringFromDate:block.createdAt].UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        if (error) {
            NSInteger errorCode = (rc == SQLITE_CONSTRAINT) ? PDSDatabaseErrorConstraintViolation : PDSDatabaseErrorQueryFailed;
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:errorCode];
        }
        result = NO;
        return;
    }

    result = YES;

    return;
    }];
    return result;
}

- (BOOL)saveBlocks:(NSArray<PDSDatabaseBlock *> *)blocks error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    if (blocks.count == 0) {
        result = YES;
        return;
    }

    NSString *sql = @"INSERT OR REPLACE INTO blocks (cid, repo_did, block_data, content_type, size, created_at) VALUES (?, ?, ?, ?, ?, ?)";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    for (PDSDatabaseBlock *block in blocks) {
        [self bindData:block.cid toStatement:stmt index:1];
        sqlite3_bind_text(stmt, 2, block.repoDid.UTF8String, -1, SQLITE_STATIC);
        [self bindData:block.blockData toStatement:stmt index:3];
        if (block.contentType) {
            sqlite3_bind_text(stmt, 4, block.contentType.UTF8String, -1, SQLITE_STATIC);
        } else {
            sqlite3_bind_null(stmt, 4);
        }
        sqlite3_bind_int64(stmt, 5, block.size);
        sqlite3_bind_text(stmt, 6, [self iso8601StringFromDate:block.createdAt].UTF8String, -1, SQLITE_STATIC);

        rc = sqlite3_step(stmt);
        if (rc != SQLITE_DONE) {
            if (error) {
                NSInteger errorCode = (rc == SQLITE_CONSTRAINT) ? PDSDatabaseErrorConstraintViolation : PDSDatabaseErrorQueryFailed;
                *error = [self errorWithMessage:sqlite3_errmsg(_db) code:errorCode];
            }
            result = NO;
            return;
        }

        sqlite3_reset(stmt);
    }

    result = YES;

    return;
    }];
    return result;
}

- (nullable PDSDatabaseBlock *)getBlockWithCid:(NSData *)cid repoDid:(NSString *)repoDid error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT * FROM blocks WHERE cid = ? AND repo_did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = nil;
        return;
    }

    [self bindData:cid toStatement:stmt index:1];
    sqlite3_bind_text(stmt, 2, repoDid.UTF8String, -1, SQLITE_STATIC);

    PDSDatabaseBlock *block = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        block = [self blockFromStatement:stmt];
    }

    result = block;

    return;
    }];
    return result;
}

- (NSArray<PDSDatabaseBlock *> *)getBlocksForRepo:(NSString *)repoDid limit:(NSInteger)limit offset:(NSInteger)offset error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT * FROM blocks WHERE repo_did = ? ORDER BY created_at ASC LIMIT ? OFFSET ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = @[];
        return;
    }

    sqlite3_bind_text(stmt, 1, repoDid.UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_int64(stmt, 2, limit);
    sqlite3_bind_int64(stmt, 3, offset);

    NSMutableArray *blocks = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        PDSDatabaseBlock *block = [self blockFromStatement:stmt];
        if (block) {
            [blocks addObject:block];
        }
    }

    result = blocks;

    return;
    }];
    return result;
}

- (NSInteger)getBlockCountForRepo:(NSString *)repoDid error:(NSError **)error {
    __block NSInteger result = 0;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT COUNT(*) FROM blocks WHERE repo_did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = 0;
        return;
    }

    sqlite3_bind_text(stmt, 1, repoDid.UTF8String, -1, SQLITE_STATIC);

    NSInteger count = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        count = sqlite3_column_int64(stmt, 0);
    }

    result = count;

    return;
    }];
    return result;
}

- (BOOL)deleteBlock:(NSData *)cid repoDid:(NSString *)repoDid error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"DELETE FROM blocks WHERE cid = ? AND repo_did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    [self bindData:cid toStatement:stmt index:1];
    sqlite3_bind_text(stmt, 2, repoDid.UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    result = YES;

    return;
    }];
    return result;
}

- (PDSDatabaseBlock *)blockFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseBlock *block = [[PDSDatabaseBlock alloc] init];
    
    int blobBytes = sqlite3_column_bytes(stmt, 0);
    if (blobBytes > 0) {
        block.cid = [NSData dataWithBytes:sqlite3_column_blob(stmt, 0) length:blobBytes];
    }
    
    block.repoDid = @((const char *)sqlite3_column_text(stmt, 1));
    
    blobBytes = sqlite3_column_bytes(stmt, 2);
    if (blobBytes > 0) {
        block.blockData = [NSData dataWithBytes:sqlite3_column_blob(stmt, 2) length:blobBytes];
    }
    
    const char *contentTypeText = (const char *)sqlite3_column_text(stmt, 3);
    if (contentTypeText) {
        block.contentType = @(contentTypeText);
    }
    
    block.size = sqlite3_column_int64(stmt, 4);
    block.createdAt = [self dateFromISO8601String:@((const char *)sqlite3_column_text(stmt, 5))];
    
    return block;
}

#pragma mark - Blobs

- (BOOL)saveBlob:(PDSDatabaseBlob *)blob error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"INSERT OR REPLACE INTO blobs (cid, did, mime_type, size, created_at) VALUES (?, ?, ?, ?, ?)";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    [self bindData:blob.cid toStatement:stmt index:1];
    sqlite3_bind_text(stmt, 2, blob.did.UTF8String, -1, SQLITE_STATIC);
    if (blob.mimeType) {
        sqlite3_bind_text(stmt, 3, blob.mimeType.UTF8String, -1, SQLITE_STATIC);
    } else {
        sqlite3_bind_null(stmt, 3);
    }
    sqlite3_bind_int64(stmt, 4, blob.size);
    sqlite3_bind_text(stmt, 5, [self iso8601StringFromDate:blob.createdAt].UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        if (error) {
            NSInteger errorCode = (rc == SQLITE_CONSTRAINT) ? PDSDatabaseErrorConstraintViolation : PDSDatabaseErrorQueryFailed;
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:errorCode];
        }
        result = NO;
        return;
    }

    result = YES;

    return;
    }];
    return result;
}

- (nullable PDSDatabaseBlob *)getBlobWithCid:(NSData *)cid error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT * FROM blobs WHERE cid = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = nil;
        return;
    }

    [self bindData:cid toStatement:stmt index:1];

    PDSDatabaseBlob *blob = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        blob = [self blobFromStatement:stmt];
    }

    result = blob;

    return;
    }];
    return result;
}

- (NSArray<PDSDatabaseBlob *> *)getBlobsForDid:(NSString *)did limit:(NSInteger)limit offset:(NSInteger)offset error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT * FROM blobs WHERE did = ? ORDER BY created_at DESC LIMIT ? OFFSET ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = @[];
        return;
    }

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_int64(stmt, 2, limit);
    sqlite3_bind_int64(stmt, 3, offset);

    NSMutableArray *blobs = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        PDSDatabaseBlob *blob = [self blobFromStatement:stmt];
        if (blob) {
            [blobs addObject:blob];
        }
    }

    result = blobs;

    return;
    }];
    return result;
}

- (NSInteger)getBlobCountForDid:(NSString *)did error:(NSError **)error {
    __block NSInteger result = 0;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT COUNT(*) FROM blobs WHERE did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = 0;
        return;
    }

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_STATIC);

    NSInteger count = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        count = sqlite3_column_int64(stmt, 0);
    }

    result = count;

    return;
    }];
    return result;
}

- (BOOL)deleteBlob:(NSData *)cid error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"DELETE FROM blobs WHERE cid = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    [self bindData:cid toStatement:stmt index:1];

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    result = YES;

    return;
    }];
    return result;
}

- (PDSDatabaseBlob *)blobFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseBlob *blob = [[PDSDatabaseBlob alloc] init];

    int blobBytes = sqlite3_column_bytes(stmt, 0);
    if (blobBytes > 0) {
        blob.cid = [NSData dataWithBytes:sqlite3_column_blob(stmt, 0) length:blobBytes];
    }

    blob.did = @((const char *)sqlite3_column_text(stmt, 1));

    const char *mimeTypeText = (const char *)sqlite3_column_text(stmt, 2);
    if (mimeTypeText) {
        blob.mimeType = @(mimeTypeText);
    }

    blob.size = sqlite3_column_int64(stmt, 3);
    blob.createdAt = [self dateFromISO8601String:@((const char *)sqlite3_column_text(stmt, 4))];

    return blob;
}

#pragma mark - Transactions

- (BOOL)beginTransactionWithError:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    if (!self.isOpen || !_db) {
        if (error) {
            *error = [self errorWithDescription:@"Cannot begin transaction: database is not open"
                                           code:PDSDatabaseErrorNotOpen];
        }
        result = NO;
        return;
    }
    if (sqlite3_get_autocommit(_db) == 0) {
        if (error) {
            *error = [self errorWithDescription:@"Cannot begin transaction: transaction already active; use transactWithBlock:error: for nested work"
                                           code:PDSDatabaseErrorQueryFailed];
        }
        result = NO;
        return;
    }

    char *errMsg = NULL;
    int rc = sqlite3_exec(_db, "BEGIN TRANSACTION", NULL, NULL, &errMsg);
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

- (BOOL)commitTransactionWithError:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    if (!self.isOpen || !_db) {
        if (error) {
            *error = [self errorWithDescription:@"Cannot commit transaction: database is not open"
                                           code:PDSDatabaseErrorNotOpen];
        }
        result = NO;
        return;
    }
    if (sqlite3_get_autocommit(_db) != 0) {
        if (error) {
            *error = [self errorWithDescription:@"Cannot commit transaction: no active transaction"
                                           code:PDSDatabaseErrorQueryFailed];
        }
        result = NO;
        return;
    }

    char *errMsg = NULL;
    int rc = sqlite3_exec(_db, "COMMIT", NULL, NULL, &errMsg);
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

- (BOOL)rollbackTransactionWithError:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    if (!self.isOpen || !_db) {
        if (error) {
            *error = [self errorWithDescription:@"Cannot roll back transaction: database is not open"
                                           code:PDSDatabaseErrorNotOpen];
        }
        result = NO;
        return;
    }
    if (sqlite3_get_autocommit(_db) != 0) {
        if (error) {
            *error = [self errorWithDescription:@"Cannot roll back transaction: no active transaction"
                                           code:PDSDatabaseErrorQueryFailed];
        }
        result = NO;
        return;
    }

    char *errMsg = NULL;
    int rc = sqlite3_exec(_db, "ROLLBACK", NULL, NULL, &errMsg);
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

- (BOOL)transactWithBlock:(void (^)(NSError **error))block error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    if (!block) {
        if (error) {
            *error = [NSError errorWithDomain:PDSDatabaseErrorDomain
                                          code:PDSDatabaseErrorQueryFailed
                                      userInfo:@{NSLocalizedDescriptionKey: @"Block cannot be nil"}];
        }
        result = NO;
        return;
    }

    if (!self.isOpen || !_db) {
        if (error) {
            *error = [self errorWithDescription:@"Cannot start transaction: database is not open"
                                           code:PDSDatabaseErrorNotOpen];
        }
        result = NO;
        return;
    }

    BOOL useSavepoint = (sqlite3_get_autocommit(_db) == 0);
    NSString *savepointName = nil;
    NSString *beginSQL = @"BEGIN TRANSACTION";
    if (useSavepoint) {
        savepointName = [[NSString stringWithFormat:@"pds_tx_%@", NSUUID.UUID.UUIDString]
                         stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
        beginSQL = [NSString stringWithFormat:@"SAVEPOINT %@", savepointName];
    }

    char *errMsg = NULL;
    int rc = sqlite3_exec(_db, beginSQL.UTF8String, NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    @try {
        NSError *blockError = nil;
        block(&blockError);

        if (blockError) {
            if (useSavepoint) {
                NSString *rollbackSQL = [NSString stringWithFormat:@"ROLLBACK TO %@", savepointName];
                NSString *releaseSQL = [NSString stringWithFormat:@"RELEASE %@", savepointName];
                sqlite3_exec(_db, rollbackSQL.UTF8String, NULL, NULL, NULL);
                sqlite3_exec(_db, releaseSQL.UTF8String, NULL, NULL, NULL);
            } else if (sqlite3_get_autocommit(_db) == 0) {
                sqlite3_exec(_db, "ROLLBACK", NULL, NULL, NULL);
            }
            if (error) *error = blockError;
            result = NO;
            return;
        }

        if (sqlite3_get_autocommit(_db) != 0) {
            if (error) {
                NSString *message = useSavepoint
                    ? @"Cannot release transaction savepoint: enclosing transaction was closed inside transaction block"
                    : @"Cannot commit transaction: transaction was closed inside transaction block";
                *error = [self errorWithDescription:message code:PDSDatabaseErrorQueryFailed];
            }
            result = NO;
            return;
        }

        NSString *finishSQL = useSavepoint ? [NSString stringWithFormat:@"RELEASE %@", savepointName] : @"COMMIT";
        errMsg = NULL;
        rc = sqlite3_exec(_db, finishSQL.UTF8String, NULL, NULL, &errMsg);
        if (rc != SQLITE_OK) {
            NSError *commitError = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
            sqlite3_free(errMsg);
            if (useSavepoint) {
                NSString *rollbackSQL = [NSString stringWithFormat:@"ROLLBACK TO %@", savepointName];
                NSString *releaseSQL = [NSString stringWithFormat:@"RELEASE %@", savepointName];
                sqlite3_exec(_db, rollbackSQL.UTF8String, NULL, NULL, NULL);
                sqlite3_exec(_db, releaseSQL.UTF8String, NULL, NULL, NULL);
            } else if (sqlite3_get_autocommit(_db) == 0) {
                sqlite3_exec(_db, "ROLLBACK", NULL, NULL, NULL);
            }
            if (error) *error = commitError;
            result = NO;
            return;
        }
        result = YES;
        return;
    } @catch (NSException *exception) {
        if (useSavepoint) {
            NSString *rollbackSQL = [NSString stringWithFormat:@"ROLLBACK TO %@", savepointName];
            NSString *releaseSQL = [NSString stringWithFormat:@"RELEASE %@", savepointName];
            sqlite3_exec(_db, rollbackSQL.UTF8String, NULL, NULL, NULL);
            sqlite3_exec(_db, releaseSQL.UTF8String, NULL, NULL, NULL);
        } else if (sqlite3_get_autocommit(_db) == 0) {
            sqlite3_exec(_db, "ROLLBACK", NULL, NULL, NULL);
        }
        if (error) {
            *error = [NSError errorWithDomain:PDSDatabaseErrorDomain
                                          code:PDSDatabaseErrorQueryFailed
                                      userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Transaction failed"}];
        }
        result = NO;
        return;
    }
    }];
    return result;
}

#pragma mark - Helpers

- (void)bindData:(nullable NSData *)data toStatement:(sqlite3_stmt *)stmt index:(int)index {
    [self safeExecuteSync:^{

    if (data && data.length > 0) {
        sqlite3_bind_blob(stmt, index, data.bytes, (int)data.length, SQLITE_STATIC);
    } else {
        sqlite3_bind_null(stmt, index);
    }
    }];
}

- (NSString *)iso8601StringFromDate:(NSDate *)date {
    if (!date) return @"";
    return [NSDateFormatter atproto_stringFromDate:date];
}

- (NSDate *)dateFromIso8601String:(NSString *)string {
    if (!string) return nil;
    return [NSDateFormatter atproto_dateFromString:string];
}


+ (void)parseLimit:(NSString *)limit outLimit:(NSUInteger *)outLimit {
    if (outLimit == nil) return;
    if (limit) {
        NSUInteger parsed = [[NSString stringWithFormat:@"%@", limit] integerValue];
        *outLimit = parsed > 0 ? MIN(parsed, 100) : 50;
    } else {
        *outLimit = 50;
    }
}

- (NSDate *)dateFromISO8601String:(NSString *)string {
    return [[NSDateFormatter atproto_iso8601Formatter] dateFromString:string];
}

#pragma mark - OAuth Clients

- (NSDictionary *)getClientWithID:(NSString *)clientID error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT * FROM oauth_clients WHERE client_id = ?";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = nil;
        return;
    }

    sqlite3_bind_text(stmt, 1, clientID.UTF8String, -1, SQLITE_STATIC);

    NSDictionary *client = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        dict[@"client_id"] = @((const char *)sqlite3_column_text(stmt, 0));

        const char *secret = (const char *)sqlite3_column_text(stmt, 1);
        if (secret) dict[@"client_secret"] = @(secret);

        // Parse redirect_uris as space-separated list
        const char *redirectUrisStr = (const char *)sqlite3_column_text(stmt, 2);
        if (redirectUrisStr) {
            NSString *urisString = @(redirectUrisStr);
            NSArray *uris = [urisString componentsSeparatedByString:@" "];
            dict[@"redirect_uris"] = uris;
        } else {
            dict[@"redirect_uris"] = @[];
        }

        const char *grants = (const char *)sqlite3_column_text(stmt, 3);
        if (grants) dict[@"grant_types"] = @(grants);

        const char *scope = (const char *)sqlite3_column_text(stmt, 4);
        if (scope) dict[@"scope"] = @(scope);

        client = dict;
    }

    result = client;

    return;
    }];
    return result;
}

- (BOOL)createClient:(NSDictionary *)client error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"INSERT OR REPLACE INTO oauth_clients (client_id, client_secret, redirect_uris, grant_types, scope, created_at) VALUES (?, ?, ?, ?, ?, ?)";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    NSString *clientID = client[@"client_id"];
    sqlite3_bind_text(stmt, 1, clientID.UTF8String, -1, SQLITE_STATIC);

    NSString *secret = client[@"client_secret"];
    if (secret) sqlite3_bind_text(stmt, 2, secret.UTF8String, -1, SQLITE_STATIC);
    else sqlite3_bind_null(stmt, 2);

    // Convert redirect_uris array to space-separated string
    NSArray *redirectURIs = client[@"redirect_uris"];
    NSString *redirectURIsString = @"";
    if ([redirectURIs isKindOfClass:[NSArray class]] && redirectURIs.count > 0) {
        redirectURIsString = [redirectURIs componentsJoinedByString:@" "];
    }
    sqlite3_bind_text(stmt, 3, redirectURIsString.UTF8String, -1, SQLITE_STATIC);

    NSString *grants = client[@"grant_types"];
    if (grants) sqlite3_bind_text(stmt, 4, grants.UTF8String, -1, SQLITE_STATIC);
    else sqlite3_bind_null(stmt, 4);

    NSString *scope = client[@"scope"];
    if (scope) sqlite3_bind_text(stmt, 5, scope.UTF8String, -1, SQLITE_STATIC);
    else sqlite3_bind_null(stmt, 5);

    sqlite3_bind_text(stmt, 6, [self iso8601StringFromDate:[NSDate date]].UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }
    result = YES;
    return;
    }];
    return result;
}

- (BOOL)seedTestClient:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    #ifndef DEBUG
    if (error) {
        *error = [NSError errorWithDomain:@"PDSDatabase"
                                     code:-1
                                 userInfo:@{NSLocalizedDescriptionKey: @"Test client seeding disabled in release builds"}];
    }
    result = NO;
    return;
    #else
    NSDictionary *testClient = @{
        @"client_id": @"test-client",
        // No client_secret for public client
        @"redirect_uris": @[@"http://localhost:3000/callback", @"http://localhost:8080/callback", @"https://localhost:2583/oauth-demo/callback", @"http://localhost:2583/oauth-demo/callback", @"https://127.0.0.1:2583/oauth-demo/callback", @"http://127.0.0.1:2583/oauth-demo/callback", @"http://localhost:2583/?oauth_callback=1", @"http://127.0.0.1:2583/?oauth_callback=1", @"http://localhost:8080/?oauth_callback=1", @"http://127.0.0.1:8080/?oauth_callback=1"],
        @"grant_types": @"authorization_code,refresh_token",
        @"scope": @"atproto"
    };
    [self createClient:testClient error:error];

    NSDictionary *confidentialClient = @{
        @"client_id": @"test-client-confidential",
        @"client_secret": @"test-secret",
        @"redirect_uris": @[@"http://localhost:3000/callback"],
        @"grant_types": @"authorization_code,refresh_token",
        @"scope": @"atproto"
    };
    result = [self createClient:confidentialClient error:error];
    return;
    #endif
    }];
    return result;
}

- (NSArray<NSDictionary *> *)getAllOAuthClientsWithError:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT * FROM oauth_clients ORDER BY created_at DESC";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = nil;
        return;
    }

    NSMutableArray *clients = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        dict[@"client_id"] = @((const char *)sqlite3_column_text(stmt, 0));

        const char *secret = (const char *)sqlite3_column_text(stmt, 1);
        if (secret) dict[@"client_secret"] = @(secret);

        const char *redirectUrisStr = (const char *)sqlite3_column_text(stmt, 2);
        if (redirectUrisStr) {
            NSString *urisString = @(redirectUrisStr);
            NSArray *uris = [urisString componentsSeparatedByString:@" "];
            dict[@"redirect_uris"] = uris;
        } else {
            dict[@"redirect_uris"] = @[];
        }

        const char *grants = (const char *)sqlite3_column_text(stmt, 3);
        if (grants) dict[@"grant_types"] = @(grants);

        const char *scope = (const char *)sqlite3_column_text(stmt, 4);
        if (scope) dict[@"scope"] = @(scope);

        [clients addObject:dict];
    }

    result = clients;

    return;
    }];
    return result;
}

- (BOOL)deleteOAuthClientWithID:(NSString *)clientID error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"DELETE FROM oauth_clients WHERE client_id = ?";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    sqlite3_bind_text(stmt, 1, clientID.UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);
    if (rc != SQLITE_DONE) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    result = sqlite3_changes(_db) > 0;

    return;
    }];
    return result;
}

@end

#pragma mark - Records

@implementation PDSDatabase (Records)

- (nullable PDSDatabaseRecord *)getRecord:(NSString *)uri error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = [NSString stringWithFormat:@"SELECT %@ FROM records WHERE uri = ?", kRecordsColumns];

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = nil;
        return;
    }

    sqlite3_bind_text(stmt, 1, uri.UTF8String, -1, SQLITE_STATIC);

    PDSDatabaseRecord *record = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        record = [self recordFromStatement:stmt];
    }

    result = record;

    return;
    }];
    return result;
}

- (BOOL)saveRecord:(PDSDatabaseRecord *)record error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"INSERT OR REPLACE INTO records (uri, did, collection, rkey, cid, created_at) VALUES (?, ?, ?, ?, ?, ?)";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    sqlite3_bind_text(stmt, 1, record.uri.UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, record.did.UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 3, record.collection.UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 4, record.rkey.UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 5, record.cid.UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 6, [self iso8601StringFromDate:record.createdAt].UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        PDS_LOG_DB_ERROR(@"Failed to save record: %s (SQLite code: %d, URI: %@)",
                         sqlite3_errmsg(_db), rc, record.uri);
        if (error) {
            NSInteger errorCode = (rc == SQLITE_CONSTRAINT) ? PDSDatabaseErrorConstraintViolation : PDSDatabaseErrorQueryFailed;
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:errorCode];
        }
        result = NO;
        return;
    }

    result = YES;

    return;
    }];
    return result;
}

- (NSArray<PDSDatabaseRecord *> *)getRecordsForDid:(NSString *)did collection:(nullable NSString *)collection error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSMutableString *sql = [NSMutableString stringWithFormat:@"SELECT %@ FROM records WHERE did = ?", kRecordsColumns];
    NSMutableArray *params = [NSMutableArray arrayWithObject:did];

    if (collection.length > 0) {
        [sql appendString:@" AND collection = ?"];
        [params addObject:collection];
    }

    [sql appendString:@" ORDER BY created_at DESC"];

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = @[];
        return;
    }

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_STATIC);
    if (collection.length > 0) {
        sqlite3_bind_text(stmt, 2, collection.UTF8String, -1, SQLITE_STATIC);
    }

    NSMutableArray *records = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        PDSDatabaseRecord *record = [self recordFromStatement:stmt];
        if (record) {
            [records addObject:record];
        }
    }

    result = records;

    return;
    }];
    return result;
}

@end

#pragma mark - PDSDatabaseAccount

@implementation PDSDatabaseAccount
@end

#pragma mark - PDSDatabaseRepo

@implementation PDSDatabaseRepo
@end

#pragma mark - PDSDatabaseBlock

@implementation PDSDatabaseBlock
@end

#pragma mark - PDSDatabaseBlob

@implementation PDSDatabaseBlob
@end

#pragma mark - PDSDatabaseRecord

@implementation PDSDatabaseRecord
@end

#pragma mark - Moderation

@implementation PDSDatabase (Moderation)

- (BOOL)takeDownAccount:(NSString *)did reason:(NSString *)reason takedownRef:(NSString *)ref error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"INSERT OR REPLACE INTO admin_takedowns (id, subjectType, subjectId, reason, takedownRef, applied, createdBy, createdAt) VALUES (?, ?, ?, ?, ?, 1, 'admin', ?)";
    
    // Generate simple ID
    NSString *takedownId = [[NSUUID UUID] UUIDString];
    NSString *dateStr = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    
    NSArray *params = @[
        takedownId,
        @"account",
        did,
        reason ?: [NSNull null],
        ref ?: [NSNull null],
        dateStr
    ];
    
    result = [self executeParameterizedUpdate:sql params:params error:error];
    
    return;
    }];
    return result;
}

- (BOOL)reinstateAccount:(NSString *)did error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    // Mark takedown as applied=0
    NSString *sql = @"UPDATE admin_takedowns SET applied = 0 WHERE subjectId = ? AND subjectType = 'account'";
    result = [self executeParameterizedUpdate:sql params:@[did] error:error];
    return;
    }];
    return result;
}

- (BOOL)deactivateAccount:(NSString *)did error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    // Set account status to "deactivated" (user-initiated, reversible)
    NSString *sql = @"UPDATE accounts SET status = 'deactivated', deactivated_at = ?, updated_at = ? WHERE did = ?";
    NSString *dateStr = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    result = [self executeParameterizedUpdate:sql params:@[dateStr, @(now), did] error:error];
    return;
    }];
    return result;
}

- (BOOL)activateAccount:(NSString *)did error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    // Set account status back to "active" (reverses deactivation)
    NSString *sql = @"UPDATE accounts SET status = 'active', deactivated_at = NULL, updated_at = ? WHERE did = ?";
    NSNumber *now = @([[NSDate date] timeIntervalSince1970]);
    result = [self executeParameterizedUpdate:sql params:@[now, did] error:error];
    return;
    }];
    return result;
}

- (NSString *)accountStatusForDid:(NSString *)did error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    if (!did) {
        result = nil;
        return;
    }
    NSString *sql = @"SELECT status FROM accounts WHERE did = ?";
    NSArray<NSDictionary *> *rows = [self executeParameterizedQuery:sql params:@[did] error:error];
    if (rows.count == 0) {
        result = nil;
        return;
    }
    result = rows.firstObject[@"status"];
    return;
    }];
    return result;
}

- (BOOL)isAccountTakedownActive:(NSString *)did error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    if (!did) {
        result = NO;
        return;
    }
    NSString *sql = @"SELECT applied FROM admin_takedowns WHERE subjectId = ? AND subjectType = 'account' ORDER BY createdAt DESC LIMIT 1";
    NSArray<NSDictionary *> *rows = [self executeParameterizedQuery:sql params:@[did] error:error];
    if (rows.count == 0) {
        result = NO;
        return;
    }
    NSNumber *applied = rows.firstObject[@"applied"];
    result = applied ? applied.boolValue : NO;
    return;
    }];
    return result;
}

- (BOOL)createLabel:(NSDictionary *)label error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"INSERT INTO labels (src, uri, cid, val, neg, cts, exp) VALUES (?, ?, ?, ?, ?, ?, ?)";
    
    NSArray *params = @[
        label[@"src"] ?: [NSNull null],
        label[@"uri"] ?: [NSNull null],
        label[@"cid"] ?: [NSNull null],
        label[@"val"] ?: [NSNull null],
        label[@"neg"] ?: @0,
        label[@"cts"] ?: [NSNull null],
        label[@"exp"] ?: [NSNull null]
    ];
    
    result = [self executeParameterizedUpdate:sql params:params error:error];
    
    return;
    }];
    return result;
}

- (NSArray<NSDictionary *> *)getLabelsWithPatterns:(NSArray<NSString *> *)uriPatterns sources:(NSArray<NSString *> *)sources limit:(NSInteger)limit cursor:(NSString *)cursor error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    
    NSMutableString *sql = [@"SELECT * FROM labels WHERE 1=1" mutableCopy];
    NSMutableArray *params = [NSMutableArray array];
    
    if (sources && sources.count > 0) {
        [sql appendString:@" AND src IN ("];
        for (NSUInteger i = 0; i < sources.count; i++) {
            [sql appendString:i == 0 ? @"?" : @", ?"];
            [params addObject:sources[i]];
        }
        [sql appendString:@")"];
    }
    
    if (uriPatterns && uriPatterns.count > 0) {
        [sql appendString:@" AND ("];
        for (NSUInteger i = 0; i < uriPatterns.count; i++) {
            if (i > 0) [sql appendString:@" OR "];
            NSString *pat = uriPatterns[i];
            if ([pat containsString:@"*"]) {
                 [sql appendString:@"uri GLOB ?"];
            } else {
                 [sql appendString:@"uri = ?"];
            }
            [params addObject:pat];
        }
        [sql appendString:@")"];
    }
    
    if (cursor) {
        [sql appendString:@" AND id > ?"];
        [params addObject:cursor];
    }
    
    [sql appendString:@" ORDER BY id ASC LIMIT ?"];
    [params addObject:@(limit)];
    
    result = [self executeParameterizedQuery:sql params:params error:error];
    
    return;
    }];
    return result;
}

@end

#pragma mark - Admin Audit

@implementation PDSDatabase (AdminAudit)

- (BOOL)insertAuditLogEntry:(NSDictionary *)entry error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"INSERT INTO admin_audit_log (admin_did, action, subject_type, subject_id, details, ip_address, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)";
    
    NSString *dateStr = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    
    NSArray *params = @[
        entry[@"admin_did"] ?: [NSNull null],
        entry[@"action"] ?: [NSNull null],
        entry[@"subject_type"] ?: [NSNull null],
        entry[@"subject_id"] ?: [NSNull null],
        entry[@"details"] ?: [NSNull null],
        entry[@"ip_address"] ?: [NSNull null],
        dateStr
    ];
    
    result = [self executeParameterizedUpdate:sql params:params error:error];
    
    return;
    }];
    return result;
}

- (NSArray<NSDictionary *> *)queryAuditLog:(NSDictionary *)filters limit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSMutableString *sql = [@"SELECT * FROM admin_audit_log WHERE 1=1" mutableCopy];
    NSMutableArray *params = [NSMutableArray array];
    
    if (filters[@"admin_did"]) {
        [sql appendString:@" AND admin_did = ?"];
        [params addObject:filters[@"admin_did"]];
    }
    
    if (filters[@"action"]) {
        [sql appendString:@" AND action = ?"];
        [params addObject:filters[@"action"]];
    }
    
    if (filters[@"subject_type"]) {
        [sql appendString:@" AND subject_type = ?"];
        [params addObject:filters[@"subject_type"]];
    }
    
    if (filters[@"subject_id"]) {
        [sql appendString:@" AND subject_id = ?"];
        [params addObject:filters[@"subject_id"]];
    }
    
    if (filters[@"since"]) {
        [sql appendString:@" AND created_at >= ?"];
        [params addObject:filters[@"since"]];
    }
    
    if (filters[@"until"]) {
        [sql appendString:@" AND created_at <= ?"];
        [params addObject:filters[@"until"]];
    }
    
    if (cursor) {
        [sql appendString:@" AND id < ?"];
        [params addObject:cursor];
    }
    
    [sql appendString:@" ORDER BY id DESC LIMIT ?"];
    [params addObject:@(limit)];
    
    result = [self executeParameterizedQuery:sql params:params error:error];
    
    return;
    }];
    return result;
}

- (BOOL)deleteAuditLogsOlderThanDays:(NSInteger)days error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSDate *cutoffDate = [[NSDate date] dateByAddingTimeInterval:-((NSTimeInterval)days * 24 * 60 * 60)];
    NSString *cutoffStr = [[NSDateFormatter atproto_iso8601Formatter] stringFromDate:cutoffDate];
    
    NSString *sql = @"DELETE FROM admin_audit_log WHERE created_at < ?";
    result = [self executeParameterizedUpdate:sql params:@[cutoffStr] error:error];
    return;
    }];
    return result;
}

@end

#pragma mark - Reports

@implementation PDSDatabase (Reports)

- (NSString *)createReport:(NSDictionary *)report error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *reportId = [[NSUUID UUID] UUIDString];
    NSString *dateStr = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    
    NSString *sql = @"INSERT INTO reports (report_id, reason_type, reason, reported_by_did, subject_type, subject_did, subject_uri, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, 'open', ?)";
    
    NSArray *params = @[
        reportId,
        report[@"reason_type"] ?: [NSNull null],
        report[@"reason"] ?: [NSNull null],
        report[@"reported_by_did"] ?: [NSNull null],
        report[@"subject_type"] ?: [NSNull null],
        report[@"subject_did"] ?: [NSNull null],
        report[@"subject_uri"] ?: [NSNull null],
        dateStr
    ];
    
    if ([self executeParameterizedUpdate:sql params:params error:error]) {
        result = reportId;
        return;
    }
    result = nil;
    return;
    }];
    return result;
}

- (NSArray<NSDictionary *> *)queryReports:(NSDictionary *)filters limit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSMutableString *sql = [@"SELECT * FROM reports WHERE 1=1" mutableCopy];
    NSMutableArray *params = [NSMutableArray array];
    
    if (filters[@"status"]) {
        [sql appendString:@" AND status = ?"];
        [params addObject:filters[@"status"]];
    }
    
    if (filters[@"reason_type"]) {
        [sql appendString:@" AND reason_type = ?"];
        [params addObject:filters[@"reason_type"]];
    }
    
    if (filters[@"reported_by_did"]) {
        [sql appendString:@" AND reported_by_did = ?"];
        [params addObject:filters[@"reported_by_did"]];
    }
    
    if (filters[@"subject_did"]) {
        [sql appendString:@" AND subject_did = ?"];
        [params addObject:filters[@"subject_did"]];
    }
    
    if (filters[@"subject_type"]) {
        [sql appendString:@" AND subject_type = ?"];
        [params addObject:filters[@"subject_type"]];
    }
    
    if (cursor) {
        [sql appendString:@" AND id < ?"];
        [params addObject:cursor];
    }
    
    [sql appendString:@" ORDER BY id DESC LIMIT ?"];
    [params addObject:@(limit)];
    
    result = [self executeParameterizedQuery:sql params:params error:error];
    
    return;
    }];
    return result;
}

- (nullable NSDictionary *)getReportById:(NSString *)reportId error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT * FROM reports WHERE report_id = ?";
    NSArray<NSDictionary *> *rows = [self executeParameterizedQuery:sql params:@[reportId] error:error];
    result = rows.firstObject;
    return;
    }];
    return result;
}

- (BOOL)updateReportStatus:(NSString *)reportId status:(NSString *)status resolvedBy:(nullable NSString *)adminDid notes:(nullable NSString *)notes error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSMutableString *sql = [@"UPDATE reports SET status = ?" mutableCopy];
    NSMutableArray *params = [NSMutableArray arrayWithObjects:status, nil];
    
    if ([status isEqualToString:@"resolved"] || [status isEqualToString:@"dismissed"]) {
        [sql appendString:@", resolved_by_did = ?, resolved_at = ?, resolution_notes = ?"];
        NSString *dateStr = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
        [params addObjectsFromArray:@[adminDid ?: [NSNull null], dateStr, notes ?: [NSNull null]]];
    }
    
    [sql appendString:@" WHERE report_id = ?"];
    [params addObject:reportId];
    
    result = [self executeParameterizedUpdate:sql params:params error:error];
    
    return;
    }];
    return result;
}

@end

#pragma mark - Admin Config

@implementation PDSDatabase (AdminConfig)

- (nullable NSString *)getAdminConfigValue:(NSString *)key error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT value FROM admin_config WHERE key = ?";
    NSArray<NSDictionary *> *rows = [self executeParameterizedQuery:sql params:@[key] error:error];
    result = rows.firstObject[@"value"];
    return;
    }];
    return result;
}

- (BOOL)setAdminConfigValue:(NSString *)value forKey:(NSString *)key error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *dateStr = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    NSString *sql = @"INSERT OR REPLACE INTO admin_config (key, value, updated_at) VALUES (?, ?, ?)";
    result = [self executeParameterizedUpdate:sql params:@[key, value, dateStr] error:error];
    return;
    }];
    return result;
}

#pragma mark - VideoJobs

- (NSDictionary *)getVideoJobById:(NSString *)jobId error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT * FROM video_jobs WHERE job_id = ?";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = nil;
        return;
    }

    sqlite3_bind_text(stmt, 1, jobId.UTF8String, -1, SQLITE_STATIC);

    NSDictionary *job = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        job = [self dictionaryFromVideoJobsStatement:stmt];
    }

    result = job;
    return;
    }];
    return result;
}

- (BOOL)createVideoJobWithId:(NSString *)jobId
                         did:(NSString *)did
                      blobCid:(NSString *)blobCid
                    mimeType:(NSString *)mimeType
                    fileSize:(NSNumber *)fileSize
             serviceAuthToken:(nullable NSString *)token
                        error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    NSString *sql = @"INSERT INTO video_jobs (job_id, did, blob_cid, mime_type, file_size, service_auth_token, state, progress, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, 'PENDING', 0, ?, ?)";

    NSArray *params = @[
        jobId ?: [NSNull null],
        did ?: [NSNull null],
        blobCid ?: [NSNull null],
        mimeType ?: [NSNull null],
        fileSize ?: [NSNull null],
        token ?: [NSNull null],
        now,
        now
    ];

    result = [self executeParameterizedUpdate:sql params:params error:error];

    return;
    }];
    return result;
}

- (BOOL)updateVideoJobState:(NSString *)jobId
                       state:(NSString *)state
                    progress:(NSNumber *)progress
                     message:(NSString *)message
                       error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    NSString *sql = @"UPDATE video_jobs SET state = ?, progress = ?, message = ?, updated_at = ? WHERE job_id = ?";
    
    NSArray *params = @[
        state ?: [NSNull null],
        progress ?: @0,
        message ?: [NSNull null],
        now,
        jobId ?: [NSNull null]
    ];
    
    result = [self executeParameterizedUpdate:sql params:params error:error];
    
    return;
    }];
    return result;
}

- (BOOL)setAgeAssurance:(NSString *)assurance
             verifiedAt:(NSString *)verifiedAt
                forDid:(NSString *)did
                error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"UPDATE accounts SET age_assurance = ?, age_verified_at = ?, updated_at = ? WHERE did = ?";
    NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    NSArray *params = @[
        assurance ?: [NSNull null],
        verifiedAt ?: [NSNull null],
        now,
        did ?: [NSNull null]
    ];
    result = [self executeParameterizedUpdate:sql params:params error:error];
    return;
    }];
    return result;
}

- (NSDictionary *)dictionaryFromVideoJobsStatement:(sqlite3_stmt *)stmt {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    for (int i = 0; i < sqlite3_column_count(stmt); i++) {
        const char *name = sqlite3_column_name(stmt, i);
        if (!name) continue;
        
        NSString *key = @(name);
        int type = sqlite3_column_type(stmt, i);
        
        switch (type) {
            case SQLITE_INTEGER:
                dict[key] = @(sqlite3_column_int64(stmt, i));
                break;
            case SQLITE_FLOAT:
                dict[key] = @(sqlite3_column_double(stmt, i));
                break;
            case SQLITE_TEXT: {
                const char *text = (const char *)sqlite3_column_text(stmt, i);
                if (text) dict[key] = @(text);
                break;
            }
            case SQLITE_NULL:
            default:
                break;
        }
    }
    
    return dict;
}

- (BOOL)updateVideoJobResults:(NSString *)jobId
           processedBlobCid:(NSString *)processedBlobCid
          thumbnailBlobCid:(NSString *)thumbnailBlobCid
                     error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    NSString *sql = @"UPDATE video_jobs SET processed_blob_cid = ?, thumbnail_blob_cid = ?, state = 'COMPLETED', progress = 100, updated_at = ? WHERE job_id = ?";

    NSArray *params = @[
        processedBlobCid ?: [NSNull null],
        thumbnailBlobCid ?: [NSNull null],
        now,
        jobId ?: [NSNull null]
    ];

    result = [self executeParameterizedUpdate:sql params:params error:error];
    return;
    }];
    return result;
}

- (BOOL)incrementVideoJobRetry:(NSString *)jobId
                         error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    NSString *sql = @"UPDATE video_jobs SET retry_count = retry_count + 1, state = 'PENDING', error_message = NULL, updated_at = ? WHERE job_id = ?";

    NSArray *params = @[
        now,
        jobId ?: [NSNull null]
    ];

    result = [self executeParameterizedUpdate:sql params:params error:error];
    return;
    }];
    return result;
}

- (NSArray<NSDictionary *> *)listVideoJobsWithState:(NSString *)state
                                               limit:(NSUInteger)limit
                                              offset:(NSUInteger)offset
                                               error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql;
    if (state.length > 0) {
        sql = @"SELECT * FROM video_jobs WHERE state = ? ORDER BY created_at DESC LIMIT ? OFFSET ?";
    } else {
        sql = @"SELECT * FROM video_jobs ORDER BY created_at DESC LIMIT ? OFFSET ?";
    }

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        result = nil;
        return;
    }

    int paramIdx = 1;
    if (state.length > 0) {
        sqlite3_bind_text(stmt, paramIdx++, state.UTF8String, -1, SQLITE_STATIC);
    }
    sqlite3_bind_int64(stmt, paramIdx++, (sqlite3_int64)limit);
    sqlite3_bind_int64(stmt, paramIdx++, (sqlite3_int64)offset);

    NSMutableArray<NSDictionary *> *jobs = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        NSDictionary *job = [self dictionaryFromVideoJobsStatement:stmt];
        if (job) [jobs addObject:job];
    }

    result = jobs;
    return;
    }];
    return result;
}

#pragma mark - Sessions & Security

- (NSArray<NSDictionary *> *)listSessionsForDid:(NSString *)did error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT token, created_at, expires_at FROM refresh_tokens WHERE account_did = ? ORDER BY created_at DESC";
    result = [self executeParameterizedQuery:sql params:@[did] error:error];
    return;
    }];
    return result;
}

- (BOOL)storeRefreshToken:(NSString *)token forAccountDid:(NSString *)did expiresAt:(NSDate *)expiresAt error:(NSError **)error {
    if (!token || !did || !expiresAt) return NO;
    __block BOOL result = NO;
    [self safeExecuteSync:^{
        NSString *sql = @"INSERT OR REPLACE INTO refresh_tokens (token, account_did, created_at, expires_at) VALUES (?, ?, ?, ?)";
        NSTimeInterval now = [NSDate date].timeIntervalSince1970;
        NSTimeInterval expires = [expiresAt timeIntervalSince1970];
        result = [self executeParameterizedUpdate:sql params:@[token, did, @(now), @(expires)] error:error];
    }];
    return result;
}

- (nullable NSString *)accountDidForRefreshToken:(NSString *)token error:(NSError **)error {
    if (!token) return nil;
    __block NSString *did = nil;
    [self safeExecuteSync:^{
        NSString *sql = @"SELECT account_did FROM refresh_tokens WHERE token = ? AND expires_at > ?";
        NSTimeInterval now = [NSDate date].timeIntervalSince1970;
        NSArray *rows = [self executeParameterizedQuery:sql params:@[token, @(now)] error:error];
        if (rows.count > 0) {
            did = rows.firstObject[@"account_did"];
        }
    }];
    return did;
}

- (BOOL)revokeSession:(NSString *)token error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"DELETE FROM refresh_tokens WHERE token = ?";
    result = [self executeParameterizedUpdate:sql params:@[token] error:error];
    return;
    }];
    return result;
}

- (BOOL)revokeAllSessionsForDid:(NSString *)did error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"DELETE FROM refresh_tokens WHERE account_did = ?";
    result = [self executeParameterizedUpdate:sql params:@[did] error:error];
    return;
    }];
    return result;
}

- (NSArray<NSDictionary *> *)listAppPasswordsForDid:(NSString *)did error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT id, name, privileged, created_at FROM app_passwords WHERE account_did = ? ORDER BY created_at DESC";
    result = [self executeParameterizedQuery:sql params:@[did] error:error];
    return;
    }];
    return result;
}

- (BOOL)revokeAppPassword:(NSString *)passwordId forDid:(NSString *)did error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"DELETE FROM app_passwords WHERE id = ? AND account_did = ?";
    result = [self executeParameterizedUpdate:sql params:@[passwordId, did] error:error];
    return;
    }];
    return result;
}

@end
