/*!
 @file RelayUpstreamManager.h

 @abstract Manages connections to upstream PDS instances for the relay.

 @discussion
    RelayUpstreamManager handles:
    - Connecting to multiple PDS instances
    - Tracking upstream health and connectivity
    - Automatic reconnection with exponential backoff
    - Load balancing across upstreams
    - Failover when upstream disconnects

    Sync v1.1: PDS instances announce themselves via requestCrawl

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Sync/RelayClient.h"

NS_ASSUME_NONNULL_BEGIN

@class RelayUpstreamManager;

@protocol RelayUpstreamManagerDelegate <NSObject>
- (void)upstreamManager:(RelayUpstreamManager *)manager didReceiveEvent:(id)event fromUpstream:(NSString *)url;
- (void)upstreamManager:(RelayUpstreamManager *)manager didConnectToUpstream:(NSString *)url;
- (void)upstreamManager:(RelayUpstreamManager *)manager didDisconnectFromUpstream:(NSString *)url error:(nullable NSError *)error;
- (void)upstreamManager:(RelayUpstreamManager *)manager didReceiveCursor:(int64_t)cursor fromUpstream:(NSString *)url;
@end

@interface RelayUpstreamManager : NSObject

@property (nonatomic, weak, nullable) id<RelayUpstreamManagerDelegate> delegate;
@property (nonatomic, assign, readonly) NSUInteger maxReconnectAttempts;
@property (nonatomic, assign, readonly) NSTimeInterval baseReconnectInterval;
@property (nonatomic, assign, readonly) BOOL autoReconnectEnabled;

- (instancetype)initWithInitialURLs:(NSArray<NSString *> *)urls NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)addUpstream:(NSString *)url;
- (void)removeUpstream:(NSString *)url;
- (void)removeAllUpstreams;

- (NSArray<NSString *> *)activeUpstreams;
- (NSArray<NSString *> *)allUpstreams;

- (void)connectAll;
- (void)disconnectAll;

- (void)connectToUpstream:(NSString *)url;
- (void)disconnectFromUpstream:(NSString *)url;

- (void)pause;
- (void)resume;

- (BOOL)isConnected;
- (BOOL)isConnectedToUpstream:(NSString *)url;

@end

NS_ASSUME_NONNULL_END