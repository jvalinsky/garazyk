// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Video/PDSLocalVideoJobStore.h"
#import "Database/PDSDatabase.h"
#import "Core/NSDateFormatter+ATProto.h"

@implementation PDSLocalVideoJobStore

- (instancetype)initWithDatabase:(PDSDatabase *)database {
    self = [super init];
    if (self) {
        _database = database;
    }
    return self;
}

- (nullable NSDictionary *)getVideoJobById:(NSString *)jobId
                                     error:(NSError **)error {
    return [self.database getVideoJobById:jobId error:error];
}

- (BOOL)createVideoJobWithId:(NSString *)jobId
                         did:(NSString *)did
                      blobCid:(NSString *)blobCid
                     mimeType:(NSString *)mimeType
                     fileSize:(NSNumber *)fileSize
              serviceAuthToken:(nullable NSString *)token
                        error:(NSError **)error {
    return [self.database createVideoJobWithId:jobId
                                           did:did
                                        blobCid:blobCid
                                       mimeType:mimeType
                                       fileSize:fileSize
                                serviceAuthToken:token
                                          error:error];
}

- (BOOL)updateVideoJobState:(NSString *)jobId
                      state:(NSString *)state
                   progress:(NSNumber *)progress
                    message:(nullable NSString *)message
                      error:(NSError **)error {
    return [self.database updateVideoJobState:jobId
                                         state:state
                                      progress:progress
                                       message:message
                                         error:error];
}

- (BOOL)updateVideoJobResults:(NSString *)jobId
              processedBlobCid:(nullable NSString *)processedBlobCid
             thumbnailBlobCid:(nullable NSString *)thumbnailBlobCid
                        error:(NSError **)error {
    return [self.database updateVideoJobResults:jobId
                          processedBlobCid:processedBlobCid
                         thumbnailBlobCid:thumbnailBlobCid
                                    error:error];
}

- (BOOL)incrementVideoJobRetry:(NSString *)jobId
                         error:(NSError **)error {
    return [self.database incrementVideoJobRetry:jobId error:error];
}

- (BOOL)updateVideoJobDimensions:(NSString *)jobId
                            width:(NSInteger)width
                           height:(NSInteger)height
                            error:(NSError **)error {
    NSString *sql = @"UPDATE video_jobs SET width = ?, height = ?, updated_at = ? WHERE job_id = ?";
    NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    return [self.database executeParameterizedUpdate:sql params:@[@(width), @(height), now, jobId] error:error];
}

- (BOOL)updateVideoJobDuration:(NSString *)jobId
                      seconds:(NSInteger)seconds
                         error:(NSError **)error {
    NSString *sql = @"UPDATE video_jobs SET duration_seconds = ?, updated_at = ? WHERE job_id = ?";
    NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    return [self.database executeParameterizedUpdate:sql params:@[@(seconds), now, jobId] error:error];
}

- (NSArray<NSDictionary *> *)queryPendingJobsWithLimit:(NSInteger)limit
                                                 error:(NSError **)error {
    NSString *sql = @"SELECT * FROM video_jobs WHERE state = 'PENDING' ORDER BY created_at ASC LIMIT ?";
    return [self.database executeParameterizedQuery:sql params:@[@(limit)] error:error];
}

@end
