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
@class ATProtoCAObjectStore;
@class ATProtoCAWatchService;
@class ATProtoCAObjectLifecycle;
@class ATProtoCARASLWellKnown;
@class ATProtoCAMirrorResolver;
@class ATProtoXrpcDispatcher;
@protocol PDSBlobProvider;
@protocol ATProtoCAMediaDenylist;
@protocol ATProtoCAMirrorFetching;

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
 Content-addressed object store for VOD watch serving (WS12).

 When set together with @c configuration.enableContentAddressedManifest, the
 runtime registers MASL-backed @c /watch/* routes.
 */
@property (nonatomic, strong, nullable) ATProtoCAObjectStore *caObjectStore;

/// Optional moderation denylist consulted before streaming CA bytes.
@property (nonatomic, strong, nullable) id<ATProtoCAMediaDenylist> caMediaDenylist;

/**
 Optional mirror fetcher injected by the composition root (jelcz). Used only
 when @c configuration.enableCAMirrorFetch is YES.
 */
@property (nonatomic, strong, nullable) id<ATProtoCAMirrorFetching> caMirrorFetcher;

/// Active CA watch service after start (nil when CA routes are disabled).
@property (nonatomic, strong, readonly, nullable) ATProtoCAWatchService *caWatchService;

/// Active CA RASL well-known service after start (nil without a CA store).
@property (nonatomic, strong, readonly, nullable) ATProtoCARASLWellKnown *caRASLWellKnown;

/// Active mirror resolver after start (nil when mirror fetch is off).
@property (nonatomic, strong, readonly, nullable) ATProtoCAMirrorResolver *caMirrorResolver;

/// Manifest refcount / reclaim controller (nil when CA store is unset).
@property (nonatomic, strong, readonly, nullable) ATProtoCAObjectLifecycle *caObjectLifecycle;

/**
 Optional composition-root hook invoked after the media XRPC pack registers.

 Used by jelcz to attach Streamplace getVideoBlob compat without MediaCore
 knowing Streamplace NSIDs. Invoked once during @c startWithError:.
 */
@property (nonatomic, copy, nullable) void (^additionalXrpcSetup)(ATProtoXrpcDispatcher *dispatcher);

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
