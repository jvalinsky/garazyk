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

/**
 * @abstract Host connectivity status reported by the relay host status endpoint.
 */
typedef NS_ENUM(NSInteger, RelayHostStatus) {
    /** The upstream is connected and receiving events. */
    RelayHostStatusActive,
    /** The upstream is configured but not currently connected. */
    RelayHostStatusDisconnected,
    /** The upstream connection failed or reported an error. */
    RelayHostStatusError
};

/**
 * @abstract Receives upstream connection and event callbacks from the relay manager.
 */
@protocol RelayUpstreamManagerDelegate <NSObject>

/**
 * @abstract Called when an upstream emits a relay event.
 * @param manager The upstream manager receiving the event.
 * @param event The decoded upstream event payload.
 * @param url The upstream URL that emitted the event.
 */
- (void)upstreamManager:(RelayUpstreamManager *)manager didReceiveEvent:(id)event fromUpstream:(NSString *)url;

/**
 * @abstract Called after a connection to an upstream succeeds.
 * @param manager The upstream manager that established the connection.
 * @param url The upstream URL that connected.
 */
- (void)upstreamManager:(RelayUpstreamManager *)manager didConnectToUpstream:(NSString *)url;

/**
 * @abstract Called after an upstream disconnects.
 * @param manager The upstream manager observing the disconnect.
 * @param url The upstream URL that disconnected.
 * @param error The disconnect error, or nil for an intentional disconnect.
 */
- (void)upstreamManager:(RelayUpstreamManager *)manager didDisconnectFromUpstream:(NSString *)url error:(nullable NSError *)error;

/**
 * @abstract Called when an upstream reports a cursor.
 * @param manager The upstream manager receiving the cursor.
 * @param cursor The latest upstream sequence cursor.
 * @param url The upstream URL that reported the cursor.
 */
- (void)upstreamManager:(RelayUpstreamManager *)manager didReceiveCursor:(int64_t)cursor fromUpstream:(NSString *)url;
@end

/**
 * @abstract Manages relay subscriptions to upstream PDS instances.
 */
@interface RelayUpstreamManager : NSObject

/** Delegate notified about upstream events and connection state. */
@property (nonatomic, weak, nullable) id<RelayUpstreamManagerDelegate> delegate;
/** Maximum reconnection attempts per upstream before giving up. */
@property (nonatomic, assign, readonly) NSUInteger maxReconnectAttempts;
/** Base delay used when computing reconnect backoff. */
@property (nonatomic, assign, readonly) NSTimeInterval baseReconnectInterval;
/** Whether disconnected upstreams are reconnected automatically. */
@property (nonatomic, assign, readonly) BOOL autoReconnectEnabled;

/**
 * @abstract Creates a manager with an initial set of upstream URLs.
 * @param urls Upstream PDS service URLs to track.
 */
- (instancetype)initWithInitialURLs:(NSArray<NSString *> *)urls NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/** Adds an upstream URL to the managed set. */
- (void)addUpstream:(NSString *)url;
/** Removes an upstream URL from the managed set. */
- (void)removeUpstream:(NSString *)url;
/** Removes every configured upstream URL. */
- (void)removeAllUpstreams;

/** Returns upstream URLs that are currently connected. */
- (NSArray<NSString *> *)activeUpstreams;
/** Returns all configured upstream URLs. */
- (NSArray<NSString *> *)allUpstreams;

/** Starts connections to all configured upstreams. */
- (void)connectAll;
/** Disconnects all active upstream connections. */
- (void)disconnectAll;

/** Starts a connection to one configured upstream URL. */
- (void)connectToUpstream:(NSString *)url;
/** Disconnects one upstream URL. */
- (void)disconnectFromUpstream:(NSString *)url;

/**
 * @abstract Checks whether an upstream host can be reached.
 * @param hostname Host name to validate.
 * @param completion Block invoked with reachability status and any validation error.
 */
- (void)validateHost:(NSString *)hostname completion:(void (^)(BOOL reachable, NSError * _Nullable error))completion;

/** Pauses upstream connection activity without removing configuration. */
- (void)pause;
/** Resumes upstream connection activity after a pause. */
- (void)resume;

/** Returns YES when at least one upstream is connected. */
- (BOOL)isConnected;
/** Returns YES when the supplied upstream URL is connected. */
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
