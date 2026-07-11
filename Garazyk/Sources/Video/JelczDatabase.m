// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Video/JelczDatabase.h"
#import "Database/Connection/ATProtoConnectionManagerSerial.h"
#import "Database/Utils/ATProtoDatabaseQueryRunner.h"
#import "Database/Utils/ATProtoDatabaseUtilities.h"
#import "Core/NSDateFormatter+ATProto.h"

NSString * const JelczDatabaseErrorDomain = @"com.atproto.jelcz.database";

@interface JelczDatabase ()
@property (nonatomic, readwrite) NSURL *databaseURL;
@property (nonatomic, strong) ATProtoConnectionManagerSerial *connectionManager;
@property (nonatomic, strong) ATProtoDatabaseQueryRunner *queryRunner;
@end

@implementation JelczDatabase

- (nullable instancetype)initWithDatabasePath:(NSString *)path
                                       error:(NSError **)error {
    self = [super init];
    if (self) {
        _databaseURL = [NSURL fileURLWithPath:path];
        _connectionManager = [[ATProtoConnectionManagerSerial alloc] initWithLabel:@"com.atproto.jelcz.database"];

        if (![self openDatabaseWithError:error]) {
            return nil;
        }
    }
    return self;
}

- (BOOL)openDatabaseWithError:(NSError **)error {
    if (self.connectionManager.isOpen) {
        return YES;
    }

    NSString *dir = self.databaseURL.URLByDeletingLastPathComponent.path;
    if (dir.length > 0) {
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    }

    if (![self.connectionManager openWithPath:self.databaseURL.path
                                       config:ATProtoDBConfigDefault
                                        error:error]) {
        return NO;
    }

    self.queryRunner = [[ATProtoDatabaseQueryRunner alloc] initWithConnectionManager:self.connectionManager
                                                                        errorDomain:JelczDatabaseErrorDomain];

    if (![self createSchemaWithError:error]) {
        [self.connectionManager close];
        return NO;
    }

    return YES;
}

- (void)closeDatabase {
    [self.connectionManager close];
}

- (BOOL)createSchemaWithError:(NSError **)error {
    NSArray<NSString *> *statements = @[
        @"CREATE TABLE IF NOT EXISTS video_jobs ("
        @"    job_id TEXT PRIMARY KEY,"
        @"    did TEXT NOT NULL,"
        @"    blob_cid TEXT NOT NULL,"
        @"    original_filename TEXT,"
        @"    mime_type TEXT,"
        @"    file_size INTEGER,"
        @"    duration_seconds INTEGER,"
        @"    width INTEGER,"
        @"    height INTEGER,"
        @"    state TEXT NOT NULL DEFAULT 'PENDING',"
        @"    progress INTEGER DEFAULT 0,"
        @"    message TEXT,"
        @"    error_code TEXT,"
        @"    error_message TEXT,"
        @"    thumbnail_blob_cid TEXT,"
        @"    processed_blob_cid TEXT,"
        @"    service_auth_token TEXT,"
        @"    created_at TEXT NOT NULL,"
        @"    updated_at TEXT NOT NULL,"
        @"    completed_at TEXT,"
        @"    expires_at TEXT,"
        @"    retry_count INTEGER DEFAULT 0"
        @")",
        @"CREATE INDEX IF NOT EXISTS idx_video_jobs_did ON video_jobs(did)",
        @"CREATE INDEX IF NOT EXISTS idx_video_jobs_state ON video_jobs(state)",
        @"CREATE INDEX IF NOT EXISTS idx_video_jobs_created ON video_jobs(created_at)",
    ];

    for (NSString *sql in statements) {
        if ([self.queryRunner executeUpdate:sql params:nil error:error] < 0) {
            return NO;
        }
    }
    return YES;
}

#pragma mark - VideoJobStore protocol

- (nullable NSDictionary *)getVideoJobById:(NSString *)jobId
                                     error:(NSError **)error {
    NSArray<NSDictionary<NSString *, id> *> *rows =
        [self.queryRunner executeQuery:@"SELECT * FROM video_jobs WHERE job_id = ?"
                                params:@[jobId]
                                 error:error];
    if (!rows || rows.count == 0) {
        return nil;
    }
    return rows.firstObject;
}

- (BOOL)createVideoJobWithId:(NSString *)jobId
                         did:(NSString *)did
                     blobCid:(NSString *)blobCid
                    mimeType:(NSString *)mimeType
                    fileSize:(NSNumber *)fileSize
             serviceAuthToken:(nullable NSString *)token
                       error:(NSError **)error {
    NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    NSString *sql = @"INSERT INTO video_jobs (job_id, did, blob_cid, mime_type, file_size, service_auth_token, state, progress, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, 'PENDING', 0, ?, ?)";
    NSArray *params = @[jobId, did, blobCid, mimeType, @(fileSize.integerValue), token ?: [NSNull null], now, now];
    return [self.queryRunner executeUpdate:sql params:params error:error] >= 0;
}

// The single-row updates below intentionally do NOT map "no matching row" to an error:
// against a missing job the UPDATE affects 0 rows and returns YES. This preserves
// JelczDatabase's pre-migration contract (see JelczDatabaseTests) and is deliberately
// looser than ATProtoMediaSQLiteStore's 404-on-no-row behaviour.

- (BOOL)updateVideoJobState:(NSString *)jobId
                      state:(NSString *)state
                   progress:(NSNumber *)progress
                    message:(nullable NSString *)message
                      error:(NSError **)error {
    NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    NSString *sql = @"UPDATE video_jobs SET state = ?, progress = ?, message = ?, updated_at = ? WHERE job_id = ?";
    NSArray *params = @[state, @(progress.integerValue), message ?: [NSNull null], now, jobId];
    return [self.queryRunner executeUpdate:sql params:params error:error] >= 0;
}

- (BOOL)updateVideoJobResults:(NSString *)jobId
             processedBlobCid:(nullable NSString *)processedBlobCid
            thumbnailBlobCid:(nullable NSString *)thumbnailBlobCid
                       error:(NSError **)error {
    NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    NSString *sql = @"UPDATE video_jobs SET processed_blob_cid = ?, thumbnail_blob_cid = ?, state = 'COMPLETED', progress = 100, updated_at = ? WHERE job_id = ?";
    NSArray *params = @[processedBlobCid ?: [NSNull null], thumbnailBlobCid ?: [NSNull null], now, jobId];
    return [self.queryRunner executeUpdate:sql params:params error:error] >= 0;
}

- (BOOL)incrementVideoJobRetry:(NSString *)jobId
                         error:(NSError **)error {
    NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    NSString *sql = @"UPDATE video_jobs SET retry_count = retry_count + 1, state = 'PENDING', error_message = NULL, updated_at = ? WHERE job_id = ?";
    return [self.queryRunner executeUpdate:sql params:@[now, jobId] error:error] >= 0;
}

- (BOOL)updateVideoJobDimensions:(NSString *)jobId
                           width:(NSInteger)width
                          height:(NSInteger)height
                           error:(NSError **)error {
    NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    NSString *sql = @"UPDATE video_jobs SET width = ?, height = ?, updated_at = ? WHERE job_id = ?";
    NSArray *params = @[@(width), @(height), now, jobId];
    return [self.queryRunner executeUpdate:sql params:params error:error] >= 0;
}

- (BOOL)updateVideoJobDuration:(NSString *)jobId
                       seconds:(NSInteger)seconds
                         error:(NSError **)error {
    NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    NSString *sql = @"UPDATE video_jobs SET duration_seconds = ?, updated_at = ? WHERE job_id = ?";
    NSArray *params = @[@(seconds), now, jobId];
    return [self.queryRunner executeUpdate:sql params:params error:error] >= 0;
}

- (NSArray<NSDictionary *> *)queryPendingJobsWithLimit:(NSInteger)limit
                                                 error:(NSError **)error {
    NSArray<NSDictionary *> *rows =
        [self.queryRunner executeQuery:@"SELECT * FROM video_jobs WHERE state = 'PENDING' ORDER BY created_at ASC LIMIT ?"
                                params:@[@(limit)]
                                 error:error];
    return rows ?: @[];
}

- (NSArray<NSDictionary *> *)listVideoJobsWithState:(nullable NSString *)state
                                              limit:(NSUInteger)limit
                                             offset:(NSUInteger)offset
                                              error:(NSError **)error {
    NSString *sql;
    NSArray *params;
    if (state.length > 0) {
        sql = @"SELECT * FROM video_jobs WHERE state = ? ORDER BY created_at DESC LIMIT ? OFFSET ?";
        params = @[state, @(limit), @(offset)];
    } else {
        sql = @"SELECT * FROM video_jobs ORDER BY created_at DESC LIMIT ? OFFSET ?";
        params = @[@(limit), @(offset)];
    }
    NSArray<NSDictionary *> *rows =
        [self.queryRunner executeQuery:sql params:params error:error];
    return rows ?: @[];
}

@end
