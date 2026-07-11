// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "MediaCore/ATProtoMediaSQLiteStore.h"
#import "Database/Connection/ATProtoConnectionManagerSerial.h"
#import "Database/Utils/ATProtoDatabaseQueryRunner.h"
#import "Database/Utils/ATProtoDatabaseUtilities.h"
#import "Core/NSDateFormatter+ATProto.h"

NSString * const ATProtoMediaSQLiteStoreErrorDomain = @"com.atproto.mediacore.store";
static const NSInteger ATProtoMediaSQLiteStoreErrorNoRow = 404;

@interface ATProtoMediaSQLiteStore ()
@property (nonatomic, strong) ATProtoConnectionManagerSerial *connectionManager;
@property (nonatomic, strong) ATProtoDatabaseQueryRunner *queryRunner;
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

    self.queryRunner = [[ATProtoDatabaseQueryRunner alloc] initWithConnectionManager:self.connectionManager
                                                                         errorDomain:ATProtoMediaSQLiteStoreErrorDomain];

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
    NSArray<NSString *> *statements = @[
        @"CREATE TABLE IF NOT EXISTS media_jobs ("
        @"    job_id TEXT PRIMARY KEY,"
        @"    did TEXT NOT NULL,"
        @"    blob_cid TEXT NOT NULL,"
        @"    mime_type TEXT NOT NULL,"
        @"    file_size INTEGER NOT NULL,"
        @"    service_auth_token TEXT,"
        @"    state TEXT NOT NULL DEFAULT 'PENDING',"
        @"    progress INTEGER NOT NULL DEFAULT 0,"
        @"    message TEXT,"
        @"    error_message TEXT,"
        @"    retry_count INTEGER NOT NULL DEFAULT 0,"
        @"    results_json TEXT,"
        @"    created_at TEXT NOT NULL,"
        @"    updated_at TEXT NOT NULL"
        @")",
        @"CREATE INDEX IF NOT EXISTS idx_media_jobs_did ON media_jobs(did)",
        @"CREATE INDEX IF NOT EXISTS idx_media_jobs_state ON media_jobs(state)",
        @"CREATE INDEX IF NOT EXISTS idx_media_jobs_created ON media_jobs(created_at)",
    ];

    for (NSString *sql in statements) {
        if ([self.queryRunner executeUpdate:sql params:nil error:error] < 0) {
            return NO;
        }
    }
    return YES;
}

#pragma mark - ATProtoMediaJobStore

- (nullable NSDictionary<NSString *, id> *)getJobById:(NSString *)jobId error:(NSError **)error {
    NSArray<NSDictionary<NSString *, id> *> *rows =
        [self.queryRunner executeQuery:@"SELECT * FROM media_jobs WHERE job_id = ?"
                                params:@[jobId]
                                 error:error];
    if (!rows || rows.count == 0) {
        return nil;
    }
    return rows.firstObject;
}

- (BOOL)createJobWithId:(NSString *)jobId
                    did:(NSString *)did
                blobCid:(NSString *)blobCid
               mimeType:(NSString *)mimeType
               fileSize:(NSNumber *)fileSize
       serviceAuthToken:(nullable NSString *)token
                  error:(NSError **)error {
    NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    NSString *sql = @"INSERT INTO media_jobs (job_id, did, blob_cid, mime_type, file_size, service_auth_token, state, progress, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, 'PENDING', 0, ?, ?)";
    NSArray *params = @[jobId, did, blobCid, mimeType, fileSize, token ?: [NSNull null], now, now];
    return [self.queryRunner executeUpdate:sql params:params error:error] >= 0;
}

- (BOOL)updateJobState:(NSString *)jobId
                 state:(ATProtoMediaJobState)state
              progress:(NSInteger)progress
               message:(nullable NSString *)message
                 error:(NSError **)error {
    NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    NSString *sql = @"UPDATE media_jobs SET state = ?, progress = ?, message = ?, updated_at = ? WHERE job_id = ?";
    NSArray *params = @[[self stringForState:state], @(progress), message ?: [NSNull null], now, jobId];
    return [self applyUpdate:sql params:params error:error];
}

- (BOOL)updateJobResults:(NSString *)jobId
                 results:(NSDictionary<NSString *, id> *)results
                   error:(NSError **)error {
    NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    NSString *jsonStr = nil;
    if (results) {
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:results options:0 error:nil];
        if (jsonData) {
            jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        }
    }
    NSString *sql = @"UPDATE media_jobs SET results_json = ?, state = 'COMPLETED', progress = 100, updated_at = ? WHERE job_id = ?";
    NSArray *params = @[jsonStr ?: [NSNull null], now, jobId];
    return [self applyUpdate:sql params:params error:error];
}

- (BOOL)incrementJobRetry:(NSString *)jobId error:(NSError **)error {
    NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    NSString *sql = @"UPDATE media_jobs SET retry_count = retry_count + 1, state = 'PENDING', error_message = NULL, updated_at = ? WHERE job_id = ?";
    return [self applyUpdate:sql params:@[now, jobId] error:error];
}

- (NSArray<NSDictionary<NSString *, id> *> *)queryPendingJobsWithLimit:(NSInteger)limit
                                                                 error:(NSError **)error {
    NSArray<NSDictionary<NSString *, id> *> *rows =
        [self.queryRunner executeQuery:@"SELECT * FROM media_jobs WHERE state = 'PENDING' ORDER BY created_at ASC LIMIT ?"
                                params:@[@(limit)]
                                 error:error];
    return rows ?: @[];
}

- (NSArray<NSDictionary<NSString *, id> *> *)listJobsWithState:(nullable NSString *)state
                                                         limit:(NSUInteger)limit
                                                        offset:(NSUInteger)offset
                                                         error:(NSError **)error {
    NSString *sql;
    NSArray *params;
    if (state.length > 0) {
        sql = @"SELECT * FROM media_jobs WHERE state = ? ORDER BY created_at DESC LIMIT ? OFFSET ?";
        params = @[state, @(limit), @(offset)];
    } else {
        sql = @"SELECT * FROM media_jobs ORDER BY created_at DESC LIMIT ? OFFSET ?";
        params = @[@(limit), @(offset)];
    }
    NSArray<NSDictionary<NSString *, id> *> *rows =
        [self.queryRunner executeQuery:sql params:params error:error];
    return rows ?: @[];
}

#pragma mark - Helpers

/// Applies a single-row update, mapping "no matching row" to the store's 404 error to
/// preserve the pre-migration contract.
- (BOOL)applyUpdate:(NSString *)sql params:(NSArray *)params error:(NSError **)error {
    NSInteger changed = [self.queryRunner executeUpdate:sql params:params error:error];
    if (changed < 0) {
        return NO;
    }
    if (changed == 0) {
        if (error) {
            *error = ATProtoDBError(ATProtoMediaSQLiteStoreErrorDomain,
                                    @"No matching row",
                                    ATProtoMediaSQLiteStoreErrorNoRow);
        }
        return NO;
    }
    return YES;
}

- (NSString *)stringForState:(ATProtoMediaJobState)state {
    switch (state) {
        case ATProtoMediaJobStatePending:    return @"PENDING";
        case ATProtoMediaJobStateProcessing: return @"PROCESSING";
        case ATProtoMediaJobStateCompleted:  return @"COMPLETED";
        case ATProtoMediaJobStateFailed:     return @"FAILED";
    }
}

@end
