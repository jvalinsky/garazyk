// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase+VideoJobs.h"
#import "Database/PDSDatabase+Private.h"
#import <sqlite3.h>
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Core/NSDateFormatter+ATProto.h"

#pragma clang diagnostic ignored "-Wblock-capture-autoreleasing"

@implementation PDSDatabase (VideoJobs)

+ (void)parseLimit:(NSString *)limit outLimit:(NSUInteger *)outLimit {
    if (outLimit == nil) return;
    if (limit) {
        NSUInteger parsed = [[NSString stringWithFormat:@"%@", limit] integerValue];
        *outLimit = parsed > 0 ? MIN(parsed, 100) : 50;
    } else {
        *outLimit = 50;
    }
}

- (NSDictionary *)getVideoJobById:(NSString *)jobId error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT * FROM video_jobs WHERE job_id = ?";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
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
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
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

@end
