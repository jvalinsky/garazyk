// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@interface PDSDatabase (VideoJobs)

- (nullable NSDictionary *)getVideoJobById:(NSString *)jobId error:(NSError **)error;
- (BOOL)createVideoJobWithId:(NSString *)jobId
                          did:(NSString *)did
                       blobCid:(NSString *)blobCid
                     mimeType:(nullable NSString *)mimeType
                      fileSize:(NSNumber *)fileSize
               serviceAuthToken:(nullable NSString *)token
                         error:(NSError **)error;
- (BOOL)updateVideoJobState:(NSString *)jobId
                        state:(NSString *)state
                     progress:(NSNumber *)progress
                      message:(nullable NSString *)message
                        error:(NSError **)error;
- (BOOL)updateVideoJobResults:(NSString *)jobId
           processedBlobCid:(NSString *)processedBlobCid
          thumbnailBlobCid:(NSString *)thumbnailBlobCid
                      error:(NSError **)error;
- (BOOL)incrementVideoJobRetry:(NSString *)jobId
                          error:(NSError **)error;
- (nullable NSArray<NSDictionary *> *)listVideoJobsWithState:(nullable NSString *)state
                                                        limit:(NSUInteger)limit
                                                       offset:(NSUInteger)offset
                                                        error:(NSError **)error;
- (BOOL)setAgeAssurance:(nullable NSString *)assurance
              verifiedAt:(nullable NSString *)verifiedAt
                 forDid:(NSString *)did
                  error:(NSError **)error;
+ (void)parseLimit:(nullable NSString *)limit outLimit:(NSUInteger *)outLimit;

@end

NS_ASSUME_NONNULL_END
