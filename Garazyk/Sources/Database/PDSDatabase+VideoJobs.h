// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSDatabase.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Database operations for video job records.
 */
@interface PDSDatabase (VideoJobs)

- (nullable NSDictionary *)getVideoJobById:(NSString *)jobId error:(NSError **)error;
- (BOOL)createVideoJobWithId:(NSString *)jobId
                          did:(NSString *)did
                       blobCid:(NSString *)blobCid
                     mimeType:(nullable NSString *)mimeType
                      fileSize:(NSNumber *)fileSize
               serviceAuthToken:(nullable NSString *)token
                         error:(NSError **)error;
/**
 * @abstract Update video job state.
 * @param jobId Video job identifier.
 * @param state Job state filter.
 * @param progress Current video job progress.
 * @param message Status message for the job.
 * @param error Receives details when the operation fails.
 * @return YES when the operation succeeds; otherwise NO.
 */
- (BOOL)updateVideoJobState:(NSString *)jobId
                        state:(NSString *)state
                     progress:(NSNumber *)progress
                      message:(nullable NSString *)message
                        error:(NSError **)error;
/**
 * @abstract Update video job results.
 * @param jobId Video job identifier.
 * @param processedBlobCid CID of the processed video blob.
 * @param thumbnailBlobCid CID of the thumbnail blob.
 * @param error Receives details when the operation fails.
 * @return YES when the operation succeeds; otherwise NO.
 */
- (BOOL)updateVideoJobResults:(NSString *)jobId
           processedBlobCid:(NSString *)processedBlobCid
          thumbnailBlobCid:(NSString *)thumbnailBlobCid
                      error:(NSError **)error;
/**
 * @abstract Increment video job retry.
 * @param jobId Video job identifier.
 * @param error Receives details when the operation fails.
 * @return YES when the operation succeeds; otherwise NO.
 */
- (BOOL)incrementVideoJobRetry:(NSString *)jobId
                          error:(NSError **)error;
- (nullable NSArray<NSDictionary *> *)listVideoJobsWithState:(nullable NSString *)state
                                                        limit:(NSUInteger)limit
                                                       offset:(NSUInteger)offset
                                                        error:(NSError **)error;
/**
 * @abstract Set age assurance.
 * @param assurance Age assurance result to persist.
 * @param verifiedAt Verification timestamp.
 * @param did Actor DID for the request.
 * @param error Receives details when the operation fails.
 * @return YES when the operation succeeds; otherwise NO.
 */
- (BOOL)setAgeAssurance:(nullable NSString *)assurance
              verifiedAt:(nullable NSString *)verifiedAt
                 forDid:(NSString *)did
                  error:(NSError **)error;
/**
 * @abstract Parse limit.
 * @param limit Maximum number of records to return.
 * @param outLimit Receives the decoded limit.
 */
+ (void)parseLimit:(nullable NSString *)limit outLimit:(NSUInteger *)outLimit;

@end

NS_ASSUME_NONNULL_END
