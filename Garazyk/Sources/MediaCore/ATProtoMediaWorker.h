// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoMediaWorker.h

 @abstract Generic concurrent background worker for media processing jobs.
 */

#import <Foundation/Foundation.h>
#import "MediaCore/ATProtoMediaJobStore.h"
#import "MediaCore/ATProtoMediaProcessor.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString * const ATProtoMediaWorkerErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoMediaWorkerError) {
    ATProtoMediaWorkerErrorDatabaseUnavailable   = 1,
    ATProtoMediaWorkerErrorBlobProviderUnavailable = 2,
    ATProtoMediaWorkerErrorProcessingFailed      = 3,
};

@protocol PDSBlobProvider;

/**
 * @abstract Coordinates background media processing: downloading, processing, and uploading.
 *
 * @discussion The worker polls the job store for pending jobs, downloads the
 * source blob, invokes the domain-specific @c ATProtoMediaProcessor, and
 * uploads the outputs back to the PDS. It handles concurrency limits, retries,
 * and error state transitions through serial dispatch queues.
 */
@interface ATProtoMediaWorker : NSObject

/// Whether the worker is actively polling.
@property (nonatomic, assign, getter=isEnabled) BOOL enabled;

/// Polling interval for pending jobs (default 5.0).
@property (nonatomic, assign) NSTimeInterval pollInterval;

/// Maximum concurrent jobs (default 2).
@property (nonatomic, assign) NSInteger maxConcurrentJobs;

/// Job persistence store.
@property (nonatomic, strong, nullable) id<ATProtoMediaJobStore> jobStore;

/// Domain-specific media processor.
@property (nonatomic, strong, nullable) id<ATProtoMediaProcessor> processor;

/// Blob storage provider for reading source blobs.
@property (nonatomic, strong, nullable) id<PDSBlobProvider> blobProvider;

/// Starts the polling timer and enables job processing.
- (void)start;

/// Stops the polling timer and cancels active work.
- (void)stop;

/// Triggers an immediate scan for pending jobs.
- (void)processPendingJobs;

/// Processes a specific job by ID.
- (void)processJob:(NSString *)jobId;

@end

NS_ASSUME_NONNULL_END
