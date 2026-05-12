// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Video/JelczDatabase.h"
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Debug/GZLogger.h"
#import "Compat/PDSTypes.h"
#import <sqlite3.h>

// Suppress -Wblock-capture-autoreleasing: all block captures in this file
// use dispatch_sync, which completes before the method returns.
#pragma clang diagnostic ignored "-Wblock-capture-autoreleasing"

NSString * const JelczDatabaseErrorDomain = @"com.atproto.jelcz.database";

static const char *kJelczDatabaseQueueKey = "kJelczDatabaseQueueKey";

@interface JelczDatabase ()
@property (nonatomic, readwrite) NSURL *databaseURL;
@property (nonatomic, readwrite) BOOL isOpen;
@property (nonatomic, assign) sqlite3 *db;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t dbQueue;
@end

@implementation JelczDatabase

- (nullable instancetype)initWithDatabasePath:(NSString *)path
                                       error:(NSError **)error {
    self = [super init];
    if (self) {
        _databaseURL = [NSURL fileURLWithPath:path];
        _dbQueue = dispatch_queue_create("com.atproto.jelcz.database", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_dbQueue, kJelczDatabaseQueueKey, (void *)kJelczDatabaseQueueKey, NULL);

        if (![self openDatabaseWithError:error]) {
            return nil;
        }
    }
    return self;
}

- (BOOL)openDatabaseWithError:(NSError **)error {
    if (self.isOpen) return YES;

    NSString *dir = self.databaseURL.URLByDeletingLastPathComponent.path;
    if (dir) {
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    }

    int rc = sqlite3_open_v2(self.databaseURL.path.UTF8String, &_db,
                              SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:JelczDatabaseErrorDomain
                                         code:rc
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithUTF8String:sqlite3_errmsg(_db)]}];
        }
        return NO;
    }

    // Enable WAL mode
    sqlite3_exec(_db, "PRAGMA journal_mode=WAL", NULL, NULL, NULL);
    sqlite3_exec(_db, "PRAGMA foreign_keys=ON", NULL, NULL, NULL);

    // Create schema
    if (![self createSchemaWithError:error]) {
        sqlite3_close(_db);
        _db = NULL;
        return NO;
    }

    self.isOpen = YES;
    return YES;
}

- (void)closeDatabase {
    if (!self.isOpen) return;
    sqlite3_close(_db);
    _db = NULL;
    self.isOpen = NO;
}

- (BOOL)createSchemaWithError:(NSError **)error {
    const char *sql =
        "CREATE TABLE IF NOT EXISTS video_jobs ("
        "    job_id TEXT PRIMARY KEY,"
        "    did TEXT NOT NULL,"
        "    blob_cid TEXT NOT NULL,"
        "    original_filename TEXT,"
        "    mime_type TEXT,"
        "    file_size INTEGER,"
        "    duration_seconds INTEGER,"
        "    width INTEGER,"
        "    height INTEGER,"
        "    state TEXT NOT NULL DEFAULT 'PENDING',"
        "    progress INTEGER DEFAULT 0,"
        "    message TEXT,"
        "    error_code TEXT,"
        "    error_message TEXT,"
        "    thumbnail_blob_cid TEXT,"
        "    processed_blob_cid TEXT,"
        "    service_auth_token TEXT,"
        "    created_at TEXT NOT NULL,"
        "    updated_at TEXT NOT NULL,"
        "    completed_at TEXT,"
        "    expires_at TEXT,"
        "    retry_count INTEGER DEFAULT 0"
        ");"
        "CREATE INDEX IF NOT EXISTS idx_video_jobs_did ON video_jobs(did);"
        "CREATE INDEX IF NOT EXISTS idx_video_jobs_state ON video_jobs(state);"
        "CREATE INDEX IF NOT EXISTS idx_video_jobs_created ON video_jobs(created_at);";

    char *errMsg = NULL;
    int rc = sqlite3_exec(_db, sql, NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:JelczDatabaseErrorDomain
                                         code:rc
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    errMsg ? [NSString stringWithUTF8String:errMsg] : @"Schema creation failed"}];
        }
        if (errMsg) sqlite3_free(errMsg);
        return NO;
    }
    return YES;
}

#pragma mark - VideoJobStore protocol

- (nullable NSDictionary *)getVideoJobById:(NSString *)jobId
                                     error:(NSError **)error {
    __block NSDictionary *result = nil;
    dispatch_sync(_dbQueue, ^{
        const char *sql = "SELECT * FROM video_jobs WHERE job_id = ?";
        sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:rc];
            return;
        }

        sqlite3_bind_text(stmt, 1, jobId.UTF8String, -1, SQLITE_TRANSIENT);

        if (sqlite3_step(stmt) == SQLITE_ROW) {
            result = [self rowFromStatement:stmt];
        }

        sqlite3_finalize(stmt);
    });
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
    dispatch_sync(_dbQueue, ^{
        NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
        const char *sql = "INSERT INTO video_jobs (job_id, did, blob_cid, mime_type, file_size, service_auth_token, state, progress, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, 'PENDING', 0, ?, ?)";

        sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:rc];
            return;
        }

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

        if (rc != SQLITE_DONE) {
            if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:rc];
            return;
        }

        result = YES;
    });
    return result;
}

- (BOOL)updateVideoJobState:(NSString *)jobId
                      state:(NSString *)state
                   progress:(NSNumber *)progress
                    message:(nullable NSString *)message
                      error:(NSError **)error {
    __block BOOL result = NO;
    dispatch_sync(_dbQueue, ^{
        NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
        const char *sql = "UPDATE video_jobs SET state = ?, progress = ?, message = ?, updated_at = ? WHERE job_id = ?";

        sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:rc];
            return;
        }

        sqlite3_bind_text(stmt, 1, state.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(stmt, 2, progress.integerValue);
        if (message) {
            sqlite3_bind_text(stmt, 3, message.UTF8String, -1, SQLITE_TRANSIENT);
        } else {
            sqlite3_bind_null(stmt, 3);
        }
        sqlite3_bind_text(stmt, 4, now.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 5, jobId.UTF8String, -1, SQLITE_TRANSIENT);

        rc = sqlite3_step(stmt);
        sqlite3_finalize(stmt);

        result = (rc == SQLITE_DONE);
        if (!result && error) {
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:rc];
        }
    });
    return result;
}

- (BOOL)updateVideoJobResults:(NSString *)jobId
              processedBlobCid:(nullable NSString *)processedBlobCid
             thumbnailBlobCid:(nullable NSString *)thumbnailBlobCid
                        error:(NSError **)error {
    __block BOOL result = NO;
    dispatch_sync(_dbQueue, ^{
        NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
        const char *sql = "UPDATE video_jobs SET processed_blob_cid = ?, thumbnail_blob_cid = ?, state = 'COMPLETED', progress = 100, updated_at = ? WHERE job_id = ?";

        sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:rc];
            return;
        }

        if (processedBlobCid) {
            sqlite3_bind_text(stmt, 1, processedBlobCid.UTF8String, -1, SQLITE_TRANSIENT);
        } else {
            sqlite3_bind_null(stmt, 1);
        }
        if (thumbnailBlobCid) {
            sqlite3_bind_text(stmt, 2, thumbnailBlobCid.UTF8String, -1, SQLITE_TRANSIENT);
        } else {
            sqlite3_bind_null(stmt, 2);
        }
        sqlite3_bind_text(stmt, 3, now.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 4, jobId.UTF8String, -1, SQLITE_TRANSIENT);

        rc = sqlite3_step(stmt);
        sqlite3_finalize(stmt);

        result = (rc == SQLITE_DONE);
        if (!result && error) {
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:rc];
        }
    });
    return result;
}

- (BOOL)incrementVideoJobRetry:(NSString *)jobId
                         error:(NSError **)error {
    __block BOOL result = NO;
    dispatch_sync(_dbQueue, ^{
        NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
        const char *sql = "UPDATE video_jobs SET retry_count = retry_count + 1, state = 'PENDING', error_message = NULL, updated_at = ? WHERE job_id = ?";

        sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:rc];
            return;
        }

        sqlite3_bind_text(stmt, 1, now.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, jobId.UTF8String, -1, SQLITE_TRANSIENT);

        rc = sqlite3_step(stmt);
        sqlite3_finalize(stmt);

        result = (rc == SQLITE_DONE);
        if (!result && error) {
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:rc];
        }
    });
    return result;
}

- (BOOL)updateVideoJobDimensions:(NSString *)jobId
                            width:(NSInteger)width
                           height:(NSInteger)height
                            error:(NSError **)error {
    __block BOOL result = NO;
    dispatch_sync(_dbQueue, ^{
        NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
        const char *sql = "UPDATE video_jobs SET width = ?, height = ?, updated_at = ? WHERE job_id = ?";

        sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:rc];
            return;
        }

        sqlite3_bind_int64(stmt, 1, width);
        sqlite3_bind_int64(stmt, 2, height);
        sqlite3_bind_text(stmt, 3, now.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 4, jobId.UTF8String, -1, SQLITE_TRANSIENT);

        rc = sqlite3_step(stmt);
        sqlite3_finalize(stmt);

        result = (rc == SQLITE_DONE);
        if (!result && error) {
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:rc];
        }
    });
    return result;
}

- (BOOL)updateVideoJobDuration:(NSString *)jobId
                      seconds:(NSInteger)seconds
                         error:(NSError **)error {
    __block BOOL result = NO;
    dispatch_sync(_dbQueue, ^{
        NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
        const char *sql = "UPDATE video_jobs SET duration_seconds = ?, updated_at = ? WHERE job_id = ?";

        sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:rc];
            return;
        }

        sqlite3_bind_int64(stmt, 1, seconds);
        sqlite3_bind_text(stmt, 2, now.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, jobId.UTF8String, -1, SQLITE_TRANSIENT);

        rc = sqlite3_step(stmt);
        sqlite3_finalize(stmt);

        result = (rc == SQLITE_DONE);
        if (!result && error) {
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:rc];
        }
    });
    return result;
}

- (NSArray<NSDictionary *> *)queryPendingJobsWithLimit:(NSInteger)limit
                                                 error:(NSError **)error {
    __block NSArray<NSDictionary *> *result = @[];
    dispatch_sync(_dbQueue, ^{
        const char *sql = "SELECT * FROM video_jobs WHERE state = 'PENDING' ORDER BY created_at ASC LIMIT ?";
        sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:rc];
            return;
        }

        sqlite3_bind_int64(stmt, 1, limit);

        NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            [rows addObject:[self rowFromStatement:stmt]];
        }

        sqlite3_finalize(stmt);
        result = rows;
    });
    return result;
}

- (NSArray<NSDictionary *> *)listVideoJobsWithState:(nullable NSString *)state
                                               limit:(NSUInteger)limit
                                              offset:(NSUInteger)offset
                                               error:(NSError **)error {
    __block NSArray<NSDictionary *> *result = @[];
    dispatch_sync(_dbQueue, ^{
        const char *sql = nil;
        sqlite3_stmt *stmt = NULL;
        int rc;

        if (state.length > 0) {
            sql = "SELECT * FROM video_jobs WHERE state = ? ORDER BY created_at DESC LIMIT ? OFFSET ?";
            rc = sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL);
            if (rc != SQLITE_OK) {
                if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:rc];
                return;
            }
            sqlite3_bind_text(stmt, 1, state.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int64(stmt, 2, (int64_t)limit);
            sqlite3_bind_int64(stmt, 3, (int64_t)offset);
        } else {
            sql = "SELECT * FROM video_jobs ORDER BY created_at DESC LIMIT ? OFFSET ?";
            rc = sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL);
            if (rc != SQLITE_OK) {
                if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:rc];
                return;
            }
            sqlite3_bind_int64(stmt, 1, (int64_t)limit);
            sqlite3_bind_int64(stmt, 2, (int64_t)offset);
        }

        NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            [rows addObject:[self rowFromStatement:stmt]];
        }

        sqlite3_finalize(stmt);
        result = rows;
    });
    return result;
}

#pragma mark - Helpers

- (NSDictionary *)rowFromStatement:(sqlite3_stmt *)stmt {
    NSMutableDictionary *row = [NSMutableDictionary dictionary];
    int cols = sqlite3_column_count(stmt);
    for (int i = 0; i < cols; i++) {
        const char *name = sqlite3_column_name(stmt, i);
        NSString *colName = [NSString stringWithUTF8String:name];
        id value = [NSNull null];

        int type = sqlite3_column_type(stmt, i);
        switch (type) {
            case SQLITE_TEXT:
                value = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, i)];
                break;
            case SQLITE_INTEGER:
                value = @(sqlite3_column_int64(stmt, i));
                break;
            case SQLITE_FLOAT:
                value = @(sqlite3_column_double(stmt, i));
                break;
            case SQLITE_NULL:
                value = [NSNull null];
                break;
            default:
                value = [NSNull null];
                break;
        }

        row[colName] = value;
    }
    return row;
}

- (NSError *)errorWithMessage:(const char *)message code:(int)code {
    return [NSError errorWithDomain:JelczDatabaseErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey:
                                          message ? [NSString stringWithUTF8String:message] : @"Unknown database error"}];
}

@end
