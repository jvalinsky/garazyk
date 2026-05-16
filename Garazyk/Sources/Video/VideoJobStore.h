// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Defines the storage interface for managing video processing jobs.
 */
@protocol VideoJobStore <NSObject>

/**
 * @abstract Retrieves a video job by its identifier.
 * @param jobId The unique identifier for the video job.
 * @param error Receives failure details.
 * @return Dictionary containing job data, or nil if not found.
 */
- (nullable NSDictionary *)getVideoJobById:(NSString *)jobId
                                     error:(NSError **)error;

/**
 * @abstract Creates a new video processing job.
 * @param jobId The job identifier.
 * @param did The creator's DID.
 * @param blobCid The original video blob CID.
 * @param mimeType The source video mime type.
 * @param fileSize The source file size in bytes.
 * @param token Optional auth token for service access.
 * @param error Receives failure details.
 * @return YES if successfully created.
 */
- (BOOL)createVideoJobWithId:(NSString *)jobId
                         did:(NSString *)did
                      blobCid:(NSString *)blobCid
                     mimeType:(NSString *)mimeType
                     fileSize:(NSNumber *)fileSize
              serviceAuthToken:(nullable NSString *)token
                        error:(NSError **)error;

/**
 * @abstract Updates the progress and state of a video job.
 * @param jobId The job identifier.
 * @param state The current state string (e.g. "processing").
 * @param progress Current completion percentage.
 * @param message Status message.
 * @param error Receives failure details.
 * @return YES if updated successfully.
 */
- (BOOL)updateVideoJobState:(NSString *)jobId
                      state:(NSString *)state
                   progress:(NSNumber *)progress
                    message:(nullable NSString *)message
                      error:(NSError **)error;

/**
 * @abstract Updates results for a completed video job.
 * @param jobId The job identifier.
 * @param processedBlobCid The final transcoded blob CID.
 * @param thumbnailBlobCid The generated thumbnail blob CID.
 * @param error Receives failure details.
 * @return YES if updated successfully.
 */
- (BOOL)updateVideoJobResults:(NSString *)jobId
              processedBlobCid:(nullable NSString *)processedBlobCid
             thumbnailBlobCid:(nullable NSString *)thumbnailBlobCid
                        error:(NSError **)error;

/**
 * @abstract Increments the retry count for a specific job.
 * @param jobId The job identifier.
 * @param error Receives failure details.
 * @return YES if incremented successfully.
 */
- (BOOL)incrementVideoJobRetry:(NSString *)jobId
                         error:(NSError **)error;

/**
 * @abstract Updates video dimension metadata.
 * @param jobId The job identifier.
 * @param width Video width.
 * @param height Video height.
 * @param error Receives failure details.
 * @return YES if updated successfully.
 */
- (BOOL)updateVideoJobDimensions:(NSString *)jobId
                            width:(NSInteger)width
                           height:(NSInteger)height
                            error:(NSError **)error;

/**
 * @abstract Updates video duration metadata.
 * @param jobId The job identifier.
 * @param seconds Duration in seconds.
 * @param error Receives failure details.
 * @return YES if updated successfully.
 */
- (BOOL)updateVideoJobDuration:(NSString *)jobId
                      seconds:(NSInteger)seconds
                         error:(NSError **)error;

/**
 * @abstract Retrieves pending jobs up to the specified limit.
 * @param limit Maximum number of jobs to fetch.
 * @param error Receives failure details.
 * @return Array of job dictionaries.
 */
- (NSArray<NSDictionary *> *)queryPendingJobsWithLimit:(NSInteger)limit
                                                 error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
