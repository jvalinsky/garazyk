// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoRelayDownstreamHandler.h

 @abstract Bridges upstream events to downstream WebSocket subscribers.

 @discussion
    ATProtoRelayDownstreamHandler is the core of the relay pipeline:
    - Receives events from ATProtoRelayUpstreamManager (upstream firehose)
    - Stores events in ATProtoRelayEventBuffer for backfill support
    - Broadcasts events to downstream subscribers via ATProtoSubscribeReposHandler
    - Supports cursor-based replay for new subscribers

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Sync/Relay/RelayUpstreamManager.h"
#import "Sync/Relay/RelayConfiguration.h"
#import "Sync/Firehose/Firehose.h"

@class ATProtoRelayEventBuffer;
@class ATProtoSubscribeReposHandler;
@class ATProtoRelayMetrics;
@class ATProtoRelayRepoStateManager;
@class ATProtoRelayEventValidator;
@class ATProtoFirehoseCommitEvent;
@class ATProtoFirehoseRawEvent;

#import "Sync/Relay/RelayIngressPipeline.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @class ATProtoRelayDownstreamHandler

 @abstract Bridges upstream firehose events to downstream subscribers.

 @discussion Implements RelayUpstreamManagerDelegate to receive events from
 upstream PDS instances and broadcasts them to connected downstream clients.
 */
@interface ATProtoRelayDownstreamHandler : NSObject <RelayUpstreamManagerDelegate>

/*!
 @property eventBuffer

 @abstract Buffer storing recent events for backfill.
 */
@property (nonatomic, readonly) ATProtoRelayEventBuffer *eventBuffer;

/*!
 @property subscribeReposHandler

 @abstract Handler for downstream WebSocket connections.
 */
@property (nonatomic, readonly) ATProtoSubscribeReposHandler *subscribeReposHandler;

/*!
 @property metrics

 @abstract Metrics tracker for relay statistics.
 */
@property (nonatomic, strong, nullable) ATProtoRelayMetrics *metrics;

/*!
 @property repoStateManager

 @abstract Manages repository state for XRPC queries.
 */
@property (nonatomic, strong, readwrite, nullable) ATProtoRelayRepoStateManager *repoStateManager;

/*!
 @property eventValidator

 @abstract Optional event validator for schema, ATProtoMST, and signature checks.
 */
@property (nonatomic, strong, readwrite, nullable) ATProtoRelayEventValidator *eventValidator;

/**
 * @abstract Controls whether repository continuity failures are forwarded.
 *
 * Defaults to ``RelayValidationModeLogOnly`` so an unknown or legacy
 * baseline cannot suppress an entire upstream firehose.
 */
@property (nonatomic, assign) RelayValidationMode chainValidationMode;

/*!
 @method initWithEventBuffer:subscribeReposHandler:

 @abstract Initialize with required components.

 @param buffer Event buffer for storing recent events.
 @param handler ATProtoSubscribeReposHandler for downstream connections.

 @return Initialized handler instance.
 */
- (instancetype)initWithEventBuffer:(ATProtoRelayEventBuffer *)buffer
              subscribeReposHandler:(ATProtoSubscribeReposHandler *)handler
    NS_DESIGNATED_INITIALIZER;

/**
 * @abstract Returns the operation result.
 */
- (instancetype)init NS_UNAVAILABLE;

#pragma mark - RelayUpstreamManagerDelegate

/*!
 @method upstreamManager:didReceiveEvent:fromUpstream:

 @abstract Called when an event is received from upstream.

 @param manager The upstream manager.
 @param event The firehose event (commit, identity, account, or error).
 @param url The upstream URL the event came from.
 */
- (void)upstreamManager:(ATProtoRelayUpstreamManager *)manager
         didReceiveEvent:(id)event
           fromUpstream:(NSString *)url;

/*!
 @method upstreamManager:didConnectToUpstream:

 @abstract Called when connection to upstream is established.

 @param manager The upstream manager.
 @param url The upstream URL that connected.
 */
- (void)upstreamManager:(ATProtoRelayUpstreamManager *)manager
    didConnectToUpstream:(NSString *)url;

/*!
 @method upstreamManager:didDisconnectFromUpstream:error:

 @abstract Called when connection to upstream is lost.

 @param manager The upstream manager.
 @param url The upstream URL that disconnected.
 @param error The error that caused disconnection, if any.
 */
- (void)upstreamManager:(ATProtoRelayUpstreamManager *)manager
    didDisconnectFromUpstream:(NSString *)url
                        error:(nullable NSError *)error;

/*!
 @method upstreamManager:didReceiveCursor:fromUpstream:

 @abstract Called when cursor (sequence number) is received.

 @param manager The upstream manager.
 @param cursor The sequence number.
 @param url The upstream URL.
 */
- (void)upstreamManager:(ATProtoRelayUpstreamManager *)manager
       didReceiveCursor:(int64_t)cursor
            fromUpstream:(NSString *)url;

#pragma mark - Downstream Management

/*!
 @method activeDownstreamCount

 @abstract Returns the number of active downstream connections.

 @return Count of connected downstream subscribers.
 */
- (NSUInteger)activeDownstreamCount;

/*!
 @method verifyChainForCommitEvent:

 @abstract Validates the commit envelope and checks ``since``/``prevData``
           against the stored revision and ATProtoMST data root.

 @discussion In log-only mode, a mismatch is recorded and the structurally
             valid event becomes the new baseline. In strict mode, mismatches
             are rejected without advancing repository state.
 */
- (BOOL)verifyChainForCommitEvent:(ATProtoFirehoseCommitEvent *)event;

/**
 * @abstract Processes one upstream event on an ingress shard or legacy queue.
 */
- (void)processUpstreamEvent:(id)event
                 fromUpstream:(NSString *)url
                     sequence:(int64_t)sequence
                   completion:(nullable RelayIngressProcessCompletion)completion;

@end

NS_ASSUME_NONNULL_END
