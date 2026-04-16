/*!
 @file RelayDownstreamHandler.h

 @abstract Bridges upstream events to downstream WebSocket subscribers.

 @discussion
    RelayDownstreamHandler is the core of the relay pipeline:
    - Receives events from RelayUpstreamManager (upstream firehose)
    - Stores events in RelayEventBuffer for backfill support
    - Broadcasts events to downstream subscribers via SubscribeReposHandler
    - Supports cursor-based replay for new subscribers

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Sync/RelayUpstreamManager.h"

@class RelayEventBuffer;
@class SubscribeReposHandler;
@class RelayMetrics;
@class RelayRepoStateManager;

NS_ASSUME_NONNULL_BEGIN

/*!
 @class RelayDownstreamHandler

 @abstract Bridges upstream firehose events to downstream subscribers.

 @discussion Implements RelayUpstreamManagerDelegate to receive events from
 upstream PDS instances and broadcasts them to connected downstream clients.
 */
@interface RelayDownstreamHandler : NSObject <RelayUpstreamManagerDelegate>

/*!
 @property eventBuffer

 @abstract Buffer storing recent events for backfill.
 */
@property (nonatomic, readonly) RelayEventBuffer *eventBuffer;

/*!
 @property subscribeReposHandler

 @abstract Handler for downstream WebSocket connections.
 */
@property (nonatomic, readonly) SubscribeReposHandler *subscribeReposHandler;

/*!
 @property metrics

 @abstract Metrics tracker for relay statistics.
 */
@property (nonatomic, strong, nullable) RelayMetrics *metrics;

/*!
 @property repoStateManager

 @abstract Manages repository state for XRPC queries.
 */
@property (nonatomic, strong, readwrite, nullable) RelayRepoStateManager *repoStateManager;

/*!
 @method initWithEventBuffer:subscribeReposHandler:

 @abstract Initialize with required components.

 @param buffer Event buffer for storing recent events.
 @param handler SubscribeReposHandler for downstream connections.

 @return Initialized handler instance.
 */
- (instancetype)initWithEventBuffer:(RelayEventBuffer *)buffer
              subscribeReposHandler:(SubscribeReposHandler *)handler
    NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

#pragma mark - RelayUpstreamManagerDelegate

/*!
 @method upstreamManager:didReceiveEvent:fromUpstream:

 @abstract Called when an event is received from upstream.

 @param manager The upstream manager.
 @param event The firehose event (commit, identity, account, or error).
 @param url The upstream URL the event came from.
 */
- (void)upstreamManager:(RelayUpstreamManager *)manager
         didReceiveEvent:(id)event
           fromUpstream:(NSString *)url;

/*!
 @method upstreamManager:didConnectToUpstream:

 @abstract Called when connection to upstream is established.

 @param manager The upstream manager.
 @param url The upstream URL that connected.
 */
- (void)upstreamManager:(RelayUpstreamManager *)manager
    didConnectToUpstream:(NSString *)url;

/*!
 @method upstreamManager:didDisconnectFromUpstream:error:

 @abstract Called when connection to upstream is lost.

 @param manager The upstream manager.
 @param url The upstream URL that disconnected.
 @param error The error that caused disconnection, if any.
 */
- (void)upstreamManager:(RelayUpstreamManager *)manager
    didDisconnectFromUpstream:(NSString *)url
                        error:(nullable NSError *)error;

/*!
 @method upstreamManager:didReceiveCursor:fromUpstream:

 @abstract Called when cursor (sequence number) is received.

 @param manager The upstream manager.
 @param cursor The sequence number.
 @param url The upstream URL.
 */
- (void)upstreamManager:(RelayUpstreamManager *)manager
       didReceiveCursor:(int64_t)cursor
            fromUpstream:(NSString *)url;

#pragma mark - Downstream Management

/*!
 @method activeDownstreamCount

 @abstract Returns the number of active downstream connections.

 @return Count of connected downstream subscribers.
 */
- (NSUInteger)activeDownstreamCount;

@end

NS_ASSUME_NONNULL_END
