// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol VideoJobStore <NSObject>

- (nullable NSDictionary *)getVideoJobById:(NSString *)jobId
                                     error:(NSError **)error;

- (BOOL)createVideoJobWithId:(NSString *)jobId
                         did:(NSString *)did
                      blobCid:(NSString *)blobCid
                     mimeType:(NSString *)mimeType
                     fileSize:(NSNumber *)fileSize
              serviceAuthToken:(nullable NSString *)token
                        error:(NSError **)error;

- (BOOL)updateVideoJobState:(NSString *)jobId
                      state:(NSString *)state
                   progress:(NSNumber *)progress
                    message:(nullable NSString *)message
                      error:(NSError **)error;

- (BOOL)updateVideoJobResults:(NSString *)jobId
              processedBlobCid:(nullable NSString *)processedBlobCid
             thumbnailBlobCid:(nullable NSString *)thumbnailBlobCid
                        error:(NSError **)error;

- (BOOL)incrementVideoJobRetry:(NSString *)jobId
                         error:(NSError **)error;

- (BOOL)updateVideoJobDimensions:(NSString *)jobId
                            width:(NSInteger)width
                           height:(NSInteger)height
                            error:(NSError **)error;

- (BOOL)updateVideoJobDuration:(NSString *)jobId
                      seconds:(NSInteger)seconds
                         error:(NSError **)error;

- (NSArray<NSDictionary *> *)queryPendingJobsWithLimit:(NSInteger)limit
                                                 error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
