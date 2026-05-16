// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Video/VideoJobStore.h"
#import "Video/VideoBlobUploader.h"
#import "Video/VideoAuthProvider.h"
#import "Video/VideoHLSGenerator.h"
#import "Blob/PDSBlobProvider.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Error domain for video worker operations.
 */
extern NSString * const ATProtoVideoWorkerErrorDomain;

/**
 * @abstract Error codes for video worker operations.
 */
typedef NS_ENUM(NSInteger, ATProtoVideoWorkerError) {
    ATProtoVideoWorkerErrorDatabaseUnavailable = 1,
    ATProtoVideoWorkerErrorBlobProviderUnavailable = 2,
    ATProtoVideoWorkerErrorProcessingFailed = 3,
};

/**
 * @abstract Current state of a video processing job.
 */
typedef NS_ENUM(NSInteger, ATProtoVideoJobState) {
    ATProtoVideoJobStatePending = 0,
    ATProtoVideoJobStateProcessing = 1,
    ATProtoVideoJobStateTranscoding = 2,
    ATProtoVideoJobStateGeneratingThumbnail = 3,
    ATProtoVideoJobStateCompleted = 4,
    ATProtoVideoJobStateFailed = 5,
};

/**
 * @abstract Coordinates background video processing, transcoding, and blob storage tasks.
 */
@interface ATProtoVideoWorker : NSObject

/**
 * @abstract Returns the singleton instance of the video worker.
 */
+ (instancetype)sharedWorker;

/**
 * @abstract Whether the worker process is active.
 */
@property (nonatomic, assign, getter=isEnabled) BOOL enabled;

/**
 * @abstract Interval at which to poll for new jobs.
 */
@property (nonatomic, assign) NSTimeInterval pollInterval;

/**
 * @abstract Maximum number of concurrent jobs allowed.
 */
@property (nonatomic, assign) NSInteger maxConcurrentJobs;

/**
 * @abstract Store for persisting job states.
 */
@property (nonatomic, strong, nullable) id<VideoJobStore> jobStore;

/**
 * @abstract Provider for uploading processed blobs.
 */
@property (nonatomic, strong, nullable) id<VideoBlobUploader> blobUploader;

/**
 * @abstract Backend blob storage provider.
 */
@property (nonatomic, strong, nullable) id<PDSBlobProvider> blobProvider;

/**
 * @abstract Authentication provider for accessing external services.
 */
@property (nonatomic, strong, nullable) id<VideoAuthProvider> authProvider;

/**
 * @abstract HLS generator configuration.
 */
@property (nonatomic, strong, nullable) ATProtoVideoHLSGenerator *hlsGenerator;

/**
 * @abstract Starts the background worker.
 */
- (void)start;

/**
 * @abstract Stops the background worker.
 */
- (void)stop;

/**
 * @abstract Processes a specific job by ID.
 * @param jobId The identifier of the job to process.
 */
- (void)processJob:(NSString *)jobId;

/**
 * @abstract Triggers a scan for pending jobs.
 */
- (void)processPendingJobs;

/**
 * @abstract Updates the status of a video job.
 * @param jobId The job identifier.
 * @param progress Integer percentage completed (0-100).
 * @param message Status update text.
 */
- (void)updateJobProgress:(NSString *)jobId
                progress:(NSInteger)progress
                 message:(NSString *)message;

@end

NS_ASSUME_NONNULL_END
