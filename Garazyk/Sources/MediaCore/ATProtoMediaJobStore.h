// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoMediaJobStore.h

 @abstract Persistence protocol for asynchronous media processing jobs.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract State of a media processing job.
 */
typedef NS_ENUM(NSInteger, ATProtoMediaJobState) {
    ATProtoMediaJobStatePending    = 0,
    ATProtoMediaJobStateProcessing = 1,
    ATProtoMediaJobStateCompleted  = 2,
    ATProtoMediaJobStateFailed     = 3,
};

/**
 * @abstract Defines the storage interface for managing media processing jobs.
 *
 * @discussion Implementations are expected to be thread-safe. The framework
 * serializes writes through the worker's dispatch queue, but callers may
 * interact with the store from admin endpoints concurrently.
 */
@protocol ATProtoMediaJobStore <NSObject>

@required

/**
 * @abstract Retrieves a job by its identifier.
 */
- (nullable NSDictionary<NSString *, id> *)getJobById:(NSString *)jobId
                                                error:(NSError **)error;

/**
 * @abstract Creates a new media processing job.
 */
- (BOOL)createJobWithId:(NSString *)jobId
                    did:(NSString *)did
                blobCid:(NSString *)blobCid
               mimeType:(NSString *)mimeType
               fileSize:(NSNumber *)fileSize
       serviceAuthToken:(nullable NSString *)token
                  error:(NSError **)error;

/**
 * @abstract Updates the state, progress, and message of a job.
 */
- (BOOL)updateJobState:(NSString *)jobId
                 state:(ATProtoMediaJobState)state
              progress:(NSInteger)progress
               message:(nullable NSString *)message
                 error:(NSError **)error;

/**
 * @abstract Stores final processing results for a completed job.
 *
 * @param results Dictionary with keys such as @"processedCid", @"thumbnailCid", @"metadata".
 */
- (BOOL)updateJobResults:(NSString *)jobId
                 results:(NSDictionary<NSString *, id> *)results
                   error:(NSError **)error;

/**
 * @abstract Increments the retry count and resets a failed job to pending.
 */
- (BOOL)incrementJobRetry:(NSString *)jobId error:(NSError **)error;

/**
 * @abstract Returns pending jobs ordered by creation date, up to the given limit.
 */
- (NSArray<NSDictionary<NSString *, id> *> *)queryPendingJobsWithLimit:(NSInteger)limit
                                                                 error:(NSError **)error;

/**
 * @abstract Lists jobs, optionally filtered by state, with pagination.
 */
- (NSArray<NSDictionary<NSString *, id> *> *)listJobsWithState:(nullable NSString *)state
                                                         limit:(NSUInteger)limit
                                                        offset:(NSUInteger)offset
                                                         error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
