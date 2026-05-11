// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
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
#import "Sync/Relay/RelayClient.h"

NS_ASSUME_NONNULL_BEGIN

@class RelayUpstreamManager;

/*! Host status for getHostStatus endpoint */
typedef NS_ENUM(NSInteger, RelayHostStatus) {
    RelayHostStatusActive,      // Connected and receiving events
    RelayHostStatusDisconnected, // Not connected
    RelayHostStatusError        // Connection error
};

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

- (void)validateHost:(NSString *)hostname completion:(void (^)(BOOL reachable, NSError * _Nullable error))completion;

- (void)pause;
- (void)resume;

- (BOOL)isConnected;
- (BOOL)isConnectedToUpstream:(NSString *)url;

#pragma mark - Host Status (for getHostStatus endpoint)

/*! Returns the current sequence for an upstream host. */
- (int64_t)seqForUpstream:(NSString *)url;

/*! Returns the host status for an upstream. */
- (RelayHostStatus)statusForUpstream:(NSString *)url;

/*! Returns the number of accounts being tracked for a host. */
- (NSUInteger)accountCountForUpstream:(NSString *)url;

/*! Updates account count for a host (called when repos are added/removed). */
- (void)setAccountCount:(NSUInteger)count forUpstream:(NSString *)url;

@end

NS_ASSUME_NONNULL_END