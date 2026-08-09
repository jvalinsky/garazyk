// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoMediaServiceRuntime.h

 @abstract Unified orchestration system for AT Protocol media sidecar CDNs.
 */

#import <Foundation/Foundation.h>
#import "MediaCore/ATProtoMediaProcessor.h"
#import "MediaCore/ATProtoMediaServiceConfiguration.h"

NS_ASSUME_NONNULL_BEGIN

@class ATProtoHttpServer;
@class ATProtoMediaWorker;
@protocol PDSBlobProvider;

/**
 * @abstract Boots and manages a standalone media CDN service.
 *
 * @discussion Sets up an HTTP server, XRPC dispatcher, background worker,
 * blob storage, and admin endpoints. A new media service binary can be
 * constructed in under 50 lines by instantiating this runtime with a
 * domain-specific @c id&lt;ATProtoMediaProcessor&gt;.
 */
@interface ATProtoMediaServiceRuntime : NSObject

/// Service configuration.
@property (nonatomic, readonly) ATProtoMediaServiceConfiguration *configuration;

/// Domain-specific media processor.
@property (nonatomic, readonly) id<ATProtoMediaProcessor> processor;

/// The running HTTP server (nil before start).
@property (nonatomic, readonly, nullable) ATProtoHttpServer *httpServer;

/// The background job worker (nil before start).
@property (nonatomic, readonly, nullable) ATProtoMediaWorker *worker;

/**
 * @abstract Initializes the runtime with configuration, a processor, and a
 *    blob storage backend.
 *
 * @discussion The caller selects and constructs the blob provider (disk vs.
 *    S3-compatible cloud storage) — MediaCore only depends on the
 *    @c id&lt;PDSBlobProvider&gt; protocol, not on any concrete backend, which
 *    lives in ATProtoServices.
 */
- (instancetype)initWithConfiguration:(ATProtoMediaServiceConfiguration *)configuration
                            processor:(id<ATProtoMediaProcessor>)processor
                         blobProvider:(id<PDSBlobProvider>)blobProvider;

/**
 * @abstract Starts the HTTP server, worker, and all subsystems.
 *
 * @param error Receives failure details.
 * @return YES if the service started successfully.
 */
- (BOOL)startWithError:(NSError **)error;

/**
 * @abstract Stops the HTTP server and worker gracefully.
 */
- (void)stop;

@end

NS_ASSUME_NONNULL_END
