// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "MediaCore/ATProtoMediaSQLiteStore.h"
#import "Database/Connection/ATProtoConnectionManagerSerial.h"
#import "Database/Utils/ATProtoDatabaseUtilities.h"
#import "Core/NSDateFormatter+ATProto.h"
#import <sqlite3.h>

NSString * const ATProtoMediaSQLiteStoreErrorDomain = @"com.atproto.mediacore.store";

@interface ATProtoMediaSQLiteStore ()
@property (nonatomic, strong) ATProtoConnectionManagerSerial *connectionManager;
@end

@implementation ATProtoMediaSQLiteStore

- (nullable instancetype)initWithDatabasePath:(NSString *)path
                                        error:(NSError **)error {
    self = [super init];
    if (self) {
        _connectionManager = [[ATProtoConnectionManagerSerial alloc] initWithLabel:@"com.atproto.mediacore.store"];
        if (![self openDatabaseWithPath:path error:error]) {
            return nil;
        }
    }
    return self;
}

- (BOOL)openDatabaseWithPath:(NSString *)path error:(NSError **)error {
    if (self.connectionManager.isOpen) {
        return YES;
    }

    NSString *dir = [path stringByDeletingLastPathComponent];
    if (dir.length > 0) {
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    }

    if (![self.connectionManager openWithPath:path
                                       config:ATProtoDBConfigDefault
                                        error:error]) {
        return NO;
    }

    if (![self createSchemaWithError:error]) {
        [self.connectionManager close];
        return NO;
    }
    return YES;
}

- (BOOL)openDatabaseWithError:(NSError **)error {
    // Schema is created during init, this is a no-op if already open.
    return self.connectionManager.isOpen;
}

- (void)closeDatabase {
    [self.connectionManager close];
}

- (BOOL)createSchemaWithError:(NSError **)error {
    const char *sql =
        "CREATE TABLE IF NOT EXISTS media_jobs ("
        "    job_id TEXT PRIMARY KEY,"
        "    did TEXT NOT NULL,"
        "    blob_cid TEXT NOT NULL,"
        "    mime_type TEXT NOT NULL,"
        "    file_size INTEGER NOT NULL,"
        "    service_auth_token TEXT,"
        "    state TEXT NOT NULL DEFAULT 'PENDING',"
        "    progress INTEGER NOT NULL DEFAULT 0,"
        "    message TEXT,"
        "    error_message TEXT,"
        "    retry_count INTEGER NOT NULL DEFAULT 0,"
        "    results_json TEXT,"
        "    created_at TEXT NOT NULL,"
        "    updated_at TEXT NOT NULL"
        ");"
        "CREATE INDEX IF NOT EXISTS idx_media_jobs_did ON media_jobs(did);"
        "CREATE INDEX IF NOT EXISTS idx_media_jobs_state ON media_jobs(state);"
        "CREATE INDEX IF NOT EXISTS idx_media_jobs_created ON media_jobs(created_at);";

    __block BOOL ok = NO;
    __block NSError *inner = nil;
    [self.connectionManager execute:^(sqlite3 *db) {
        char *errMsg = NULL;
        int rc = sqlite3_exec(db, sql, NULL, NULL, &errMsg);
        if (rc != SQLITE_OK) {
            NSString *msg = errMsg ? [NSString stringWithUTF8String:errMsg] : @"Schema creation failed";
            inner = [NSError errorWithDomain:ATProtoMediaSQLiteStoreErrorDomain
                                        code:rc
                                    userInfo:@{NSLocalizedDescriptionKey: msg}];
            if (errMsg) sqlite3_free(errMsg);
            return;
        }
        ok = YES;
    } error:&inner];

    if (!ok && error) *error = inner;
    return ok;
}

#pragma mark - ATProtoMediaJobStore

- (nullable NSDictionary<NSString *, id> *)getJobById:(NSString *)jobId error:(NSError **)error {
    __block NSDictionary *result = nil;
    __block NSError *inner = nil;
    [self.connectionManager execute:^(sqlite3 *db) {
        const char *sql = "SELECT * FROM media_jobs WHERE job_id = ?";
        sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) { inner = [self errorWithMessage:sqlite3_errmsg(db) code:rc]; return; }
        sqlite3_bind_text(stmt, 1, jobId.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            result = [self rowFromStatement:stmt];
        }
        sqlite3_finalize(stmt);
    } error:&inner];
    if (!result && error) *error = inner;
    return result;
}

- (BOOL)createJobWithId:(NSString *)jobId
                    did:(NSString *)did
                blobCid:(NSString *)blobCid
               mimeType:(NSString *)mimeType
               fileSize:(NSNumber *)fileSize
       serviceAuthToken:(nullable NSString *)token
                  error:(NSError **)error {
    __block BOOL ok = NO;
    __block NSError *inner = nil;
    [self.connectionManager execute:^(sqlite3 *db) {
        NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
        const char *sql = "INSERT INTO media_jobs (job_id, did, blob_cid, mime_type, file_size, service_auth_token, state, progress, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, 'PENDING', 0, ?, ?)";
        sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) { inner = [self errorWithMessage:sqlite3_errmsg(db) code:rc]; return; }
        sqlite3_bind_text(stmt, 1, jobId.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, did.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, blobCid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 4, mimeType.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(stmt, 5, fileSize.integerValue);
        if (token) {
            sqlite3_bind_text(stmt, 6, token.UTF8String, -1, SQLITE_TRANSIENT);
        } else {
            sqlite3_bind_null(stmt, 6);
        }
        sqlite3_bind_text(stmt, 7, now.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 8, now.UTF8String, -1, SQLITE_TRANSIENT);
        rc = sqlite3_step(stmt);
        sqlite3_finalize(stmt);
        if (rc != SQLITE_DONE) { inner = [self errorWithMessage:sqlite3_errmsg(db) code:rc]; return; }
        ok = YES;
    } error:&inner];
    if (!ok && error) *error = inner;
    return ok;
}

- (BOOL)updateJobState:(NSString *)jobId
                 state:(ATProtoMediaJobState)state
              progress:(NSInteger)progress
               message:(nullable NSString *)message
                 error:(NSError **)error {
    __block BOOL ok = NO;
    __block NSError *inner = nil;
    [self.connectionManager execute:^(sqlite3 *db) {
        NSString *stateStr = [self stringForState:state];
        NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
        const char *sql = "UPDATE media_jobs SET state = ?, progress = ?, message = ?, updated_at = ? WHERE job_id = ?";
        sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) { inner = [self errorWithMessage:sqlite3_errmsg(db) code:rc]; return; }
        sqlite3_bind_text(stmt, 1, stateStr.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(stmt, 2, progress);
        if (message) {
            sqlite3_bind_text(stmt, 3, message.UTF8String, -1, SQLITE_TRANSIENT);
        } else {
            sqlite3_bind_null(stmt, 3);
        }
        sqlite3_bind_text(stmt, 4, now.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 5, jobId.UTF8String, -1, SQLITE_TRANSIENT);
        rc = sqlite3_step(stmt);
        sqlite3_finalize(stmt);
        ok = (rc == SQLITE_DONE);
        if (!ok) inner = [self errorWithMessage:sqlite3_errmsg(db) code:rc];
    } error:&inner];
    if (!ok && error) *error = inner;
    return ok;
}

- (BOOL)updateJobResults:(NSString *)jobId
                 results:(NSDictionary<NSString *, id> *)results
                   error:(NSError **)error {
    __block BOOL ok = NO;
    __block NSError *inner = nil;
    [self.connectionManager execute:^(sqlite3 *db) {
        NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
        NSData *jsonData = nil;
        if (results) {
            jsonData = [NSJSONSerialization dataWithJSONObject:results options:0 error:nil];
        }
        NSString *jsonStr = jsonData ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] : nil;
        const char *sql = "UPDATE media_jobs SET results_json = ?, state = 'COMPLETED', progress = 100, updated_at = ? WHERE job_id = ?";
        sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) { inner = [self errorWithMessage:sqlite3_errmsg(db) code:rc]; return; }
        if (jsonStr) {
            sqlite3_bind_text(stmt, 1, jsonStr.UTF8String, -1, SQLITE_TRANSIENT);
        } else {
            sqlite3_bind_null(stmt, 1);
        }
        sqlite3_bind_text(stmt, 2, now.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, jobId.UTF8String, -1, SQLITE_TRANSIENT);
        rc = sqlite3_step(stmt);
        sqlite3_finalize(stmt);
        ok = (rc == SQLITE_DONE);
        if (!ok) inner = [self errorWithMessage:sqlite3_errmsg(db) code:rc];
    } error:&inner];
    if (!ok && error) *error = inner;
    return ok;
}

- (BOOL)incrementJobRetry:(NSString *)jobId error:(NSError **)error {
    __block BOOL ok = NO;
    __block NSError *inner = nil;
    [self.connectionManager execute:^(sqlite3 *db) {
        NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
        const char *sql = "UPDATE media_jobs SET retry_count = retry_count + 1, state = 'PENDING', error_message = NULL, updated_at = ? WHERE job_id = ?";
        sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) { inner = [self errorWithMessage:sqlite3_errmsg(db) code:rc]; return; }
        sqlite3_bind_text(stmt, 1, now.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, jobId.UTF8String, -1, SQLITE_TRANSIENT);
        rc = sqlite3_step(stmt);
        sqlite3_finalize(stmt);
        ok = (rc == SQLITE_DONE);
        if (!ok) inner = [self errorWithMessage:sqlite3_errmsg(db) code:rc];
    } error:&inner];
    if (!ok && error) *error = inner;
    return ok;
}

- (NSArray<NSDictionary<NSString *, id> *> *)queryPendingJobsWithLimit:(NSInteger)limit
                                                                 error:(NSError **)error {
    __block NSArray *result = @[];
    __block NSError *inner = nil;
    [self.connectionManager execute:^(sqlite3 *db) {
        const char *sql = "SELECT * FROM media_jobs WHERE state = 'PENDING' ORDER BY created_at ASC LIMIT ?";
        sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) { inner = [self errorWithMessage:sqlite3_errmsg(db) code:rc]; return; }
        sqlite3_bind_int64(stmt, 1, limit);
        NSMutableArray *rows = [NSMutableArray array];
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            [rows addObject:[self rowFromStatement:stmt]];
        }
        sqlite3_finalize(stmt);
        result = rows;
    } error:&inner];
    if (result.count == 0 && error && inner) *error = inner;
    return result;
}

- (NSArray<NSDictionary<NSString *, id> *> *)listJobsWithState:(nullable NSString *)state
                                                         limit:(NSUInteger)limit
                                                        offset:(NSUInteger)offset
                                                         error:(NSError **)error {
    __block NSArray *result = @[];
    __block NSError *inner = nil;
    [self.connectionManager execute:^(sqlite3 *db) {
        sqlite3_stmt *stmt = NULL;
        int rc = SQLITE_OK;
        if (state.length > 0) {
            const char *sql = "SELECT * FROM media_jobs WHERE state = ? ORDER BY created_at DESC LIMIT ? OFFSET ?";
            rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
            if (rc != SQLITE_OK) { inner = [self errorWithMessage:sqlite3_errmsg(db) code:rc]; return; }
            sqlite3_bind_text(stmt, 1, state.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int64(stmt, 2, (int64_t)limit);
            sqlite3_bind_int64(stmt, 3, (int64_t)offset);
        } else {
            const char *sql = "SELECT * FROM media_jobs ORDER BY created_at DESC LIMIT ? OFFSET ?";
            rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
            if (rc != SQLITE_OK) { inner = [self errorWithMessage:sqlite3_errmsg(db) code:rc]; return; }
            sqlite3_bind_int64(stmt, 1, (int64_t)limit);
            sqlite3_bind_int64(stmt, 2, (int64_t)offset);
        }
        NSMutableArray *rows = [NSMutableArray array];
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            [rows addObject:[self rowFromStatement:stmt]];
        }
        sqlite3_finalize(stmt);
        result = rows;
    } error:&inner];
    if (result.count == 0 && error && inner) *error = inner;
    return result;
}

#pragma mark - Helpers

- (NSString *)stringForState:(ATProtoMediaJobState)state {
    switch (state) {
        case ATProtoMediaJobStatePending:    return @"PENDING";
        case ATProtoMediaJobStateProcessing: return @"PROCESSING";
        case ATProtoMediaJobStateCompleted:  return @"COMPLETED";
        case ATProtoMediaJobStateFailed:     return @"FAILED";
    }
}

- (NSDictionary *)rowFromStatement:(sqlite3_stmt *)stmt {
    NSMutableDictionary *row = [NSMutableDictionary dictionary];
    int cols = sqlite3_column_count(stmt);
    for (int i = 0; i < cols; i++) {
        const char *name = sqlite3_column_name(stmt, i);
        NSString *colName = [NSString stringWithUTF8String:name];
        row[colName] = ATProtoDBColumnValue(stmt, i) ?: [NSNull null];
    }
    return row;
}

- (NSError *)errorWithMessage:(const char *)message code:(int)code {
    return ATProtoDBError(ATProtoMediaSQLiteStoreErrorDomain,
                          message ? @(message) : @"Unknown error", code);
}

@end
