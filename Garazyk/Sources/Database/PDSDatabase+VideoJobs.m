// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase+VideoJobs.h"
#import "Database/PDSDatabase+Private.h"
#import <sqlite3.h>
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Database/Utils/ATProtoDatabaseUtilities.h"
#import "Core/NSDateFormatter+ATProto.h"

#pragma clang diagnostic ignored "-Wblock-capture-autoreleasing"

@implementation PDSDatabase (VideoJobs)

- (NSDictionary *)getVideoJobById:(NSString *)jobId error:(NSError **)error {
    NSString *sql = @"SELECT job_id, did, blob_cid, mime_type, file_size, service_auth_token, state, progress, message, processed_blob_cid, thumbnail_blob_cid, retry_count, error_message, created_at, updated_at FROM video_jobs WHERE job_id = ?";
    NSArray *rows = [self executeParameterizedQuery:sql params:@[jobId] error:error];
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

    return [self executeParameterizedUpdate:sql params:params error:error];
}

- (BOOL)updateVideoJobState:(NSString *)jobId
                        state:(NSString *)state
                     progress:(NSNumber *)progress
                      message:(NSString *)message
                        error:(NSError **)error {
    NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    NSString *sql = @"UPDATE video_jobs SET state = ?, progress = ?, message = ?, updated_at = ? WHERE job_id = ?";

    NSArray *params = @[
        state ?: [NSNull null],
        progress ?: @0,
        message ?: [NSNull null],
        now,
        jobId ?: [NSNull null]
    ];

    return [self executeParameterizedUpdate:sql params:params error:error];
}

- (BOOL)setAgeAssurance:(NSString *)assurance
              verifiedAt:(NSString *)verifiedAt
                 forDid:(NSString *)did
                 error:(NSError **)error {
    NSString *sql = @"UPDATE accounts SET age_assurance = ?, age_verified_at = ?, updated_at = ? WHERE did = ?";
    NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    NSArray *params = @[
        assurance ?: [NSNull null],
        verifiedAt ?: [NSNull null],
        now,
        did ?: [NSNull null]
    ];
    return [self executeParameterizedUpdate:sql params:params error:error];
}

- (BOOL)updateVideoJobResults:(NSString *)jobId
           processedBlobCid:(NSString *)processedBlobCid
          thumbnailBlobCid:(NSString *)thumbnailBlobCid
                      error:(NSError **)error {
    NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    NSString *sql = @"UPDATE video_jobs SET processed_blob_cid = ?, thumbnail_blob_cid = ?, state = 'COMPLETED', progress = 100, updated_at = ? WHERE job_id = ?";

    NSArray *params = @[
        processedBlobCid ?: [NSNull null],
        thumbnailBlobCid ?: [NSNull null],
        now,
        jobId ?: [NSNull null]
    ];

    return [self executeParameterizedUpdate:sql params:params error:error];
}

- (BOOL)incrementVideoJobRetry:(NSString *)jobId
                          error:(NSError **)error {
    NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    NSString *sql = @"UPDATE video_jobs SET retry_count = retry_count + 1, state = 'PENDING', error_message = NULL, updated_at = ? WHERE job_id = ?";
    NSArray *params = @[now, jobId ?: [NSNull null]];
    return [self executeParameterizedUpdate:sql params:params error:error];
}

- (NSArray<NSDictionary *> *)listVideoJobsWithState:(NSString *)state
                                                limit:(NSUInteger)limit
                                               offset:(NSUInteger)offset
                                                error:(NSError **)error {
    NSString *sql;
    NSArray *params;
    if (state.length > 0) {
        sql = @"SELECT job_id, did, blob_cid, mime_type, file_size, service_auth_token, state, progress, message, processed_blob_cid, thumbnail_blob_cid, retry_count, error_message, created_at, updated_at FROM video_jobs WHERE state = ? ORDER BY created_at DESC LIMIT ? OFFSET ?";
        params = @[state, @(limit), @(offset)];
    } else {
        sql = @"SELECT job_id, did, blob_cid, mime_type, file_size, service_auth_token, state, progress, message, processed_blob_cid, thumbnail_blob_cid, retry_count, error_message, created_at, updated_at FROM video_jobs ORDER BY created_at DESC LIMIT ? OFFSET ?";
        params = @[@(limit), @(offset)];
    }

    return [self executeParameterizedQuery:sql params:params error:error];
}

@end
