// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoRelayUpstreamManager.h

 @abstract Manages connections to upstream PDS instances for the relay.

 @discussion
    ATProtoRelayUpstreamManager handles:
    - Connecting to multiple PDS instances
    - Tracking upstream health and connectivity
    - Automatic reconnection with exponential backoff
    - Load balancing across upstreams
    - Failover when upstream disconnects

    Sync v1.1: PDS instances announce themselves via requestCrawl

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import <stdint.h>
#import "Sync/Relay/RelayClient.h"
#import "Sync/Firehose/Firehose.h"
#import "Sync/Relay/RelayIngressPipeline.h"

NS_ASSUME_NONNULL_BEGIN

@class ATProtoRelayIngressConfiguration;

@class ATProtoRelayUpstreamManager;
@class ATProtoRelayMetrics;
@class ATProtoFirehoseRawEvent;

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
 * @abstract Explicit repository inventory state for an upstream PDS.
 */
typedef NS_ENUM(NSInteger, RelayCrawlState) {
    /** The upstream has no active or completed inventory crawl. */
    RelayCrawlStateNotRequested,
    /** A crawl was requested and is waiting for the upstream connection. */
    RelayCrawlStateRequested,
    /** The relay is fetching the upstream repository inventory. */
    RelayCrawlStateCrawling,
    /** The inventory fetch completed successfully. */
    RelayCrawlStateComplete,
    /** The inventory fetch failed or stopped because of invalid pagination. */
    RelayCrawlStateFailed
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
- (void)upstreamManager:(ATProtoRelayUpstreamManager *)manager didReceiveEvent:(id)event fromUpstream:(NSString *)url;

/**
 * @abstract Called after a connection to an upstream succeeds.
 * @param manager The upstream manager that established the connection.
 * @param url The upstream URL that connected.
 */
- (void)upstreamManager:(ATProtoRelayUpstreamManager *)manager didConnectToUpstream:(NSString *)url;

/**
 * @abstract Called after an upstream disconnects.
 * @param manager The upstream manager observing the disconnect.
 * @param url The upstream URL that disconnected.
 * @param error The disconnect error, or nil for an intentional disconnect.
 */
- (void)upstreamManager:(ATProtoRelayUpstreamManager *)manager didDisconnectFromUpstream:(NSString *)url error:(nullable NSError *)error;

/**
 * @abstract Called when an upstream reports a cursor.
 * @param manager The upstream manager receiving the cursor.
 * @param cursor The latest upstream sequence cursor.
 * @param url The upstream URL that reported the cursor.
 */
- (void)upstreamManager:(ATProtoRelayUpstreamManager *)manager didReceiveCursor:(int64_t)cursor fromUpstream:(NSString *)url;
@end

/**
 * @abstract Manages relay subscriptions to upstream PDS instances.
 */
@interface ATProtoRelayUpstreamManager : NSObject

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

/*! Returns the number of firehose events received from an upstream since process start. */
- (uint64_t)eventCountForUpstream:(NSString *)url;

/*! Returns firehose event counts grouped by protocol event kind. */
- (NSDictionary<NSString *, NSNumber *> *)eventCountsByKindForUpstream:(NSString *)url;

/*! Returns the most recent firehose event time, or nil before the first event. */
- (nullable NSDate *)lastEventAtForUpstream:(NSString *)url;

/*! Returns when the current upstream connection was established, if connected. */
- (nullable NSDate *)connectedAtForUpstream:(NSString *)url;

/*! Returns the current automatic reconnection attempt count. */
- (NSUInteger)reconnectAttemptsForUpstream:(NSString *)url;

#pragma mark - Repository Inventory Crawl State

/*! Records that the relay API received a requestCrawl for an upstream. */
- (void)markCrawlRequestedForUpstream:(NSString *)url;

/*! Records that a configured upstream is beginning inventory without requestCrawl. */
- (void)markInventoryRequestedForUpstream:(NSString *)url;

/*! Records that repository inventory fetching has started. */
- (NSUInteger)beginInventoryForUpstream:(NSString *)url;

/*! Records repositories loaded from one inventory page for a crawl generation. */
- (void)recordInventoryPageForUpstream:(NSString *)url
                          generation:(NSUInteger)generation
                           repoCount:(NSUInteger)repoCount;

/*! Records successful completion of repository inventory fetching for a generation. */
- (void)completeInventoryForUpstream:(NSString *)url
                         generation:(NSUInteger)generation
                          repoCount:(NSUInteger)repoCount;

/*! Records a failed repository inventory fetch for a generation. */
- (void)failInventoryForUpstream:(NSString *)url
                     generation:(NSUInteger)generation
                           error:(nullable NSString *)error;

/*! Returns upstream URLs that have been explicitly requested through requestCrawl. */
- (NSArray<NSString *> *)crawlRequestedUpstreams;

/*! Returns whether this upstream was explicitly requested through requestCrawl. */
- (BOOL)crawlWasRequestedForUpstream:(NSString *)url;

/*! Returns whether any inventory request is currently tracked for this upstream. */
- (BOOL)inventoryWasRequestedForUpstream:(NSString *)url;

/*! Returns the last crawl request time, or nil if no explicit request was recorded. */
- (nullable NSDate *)crawlRequestedAtForUpstream:(NSString *)url;

/*! Returns the current inventory crawl generation for an upstream. */
- (NSUInteger)crawlGenerationForUpstream:(NSString *)url;

/*! Returns the explicit inventory crawl state for an upstream. */
- (RelayCrawlState)crawlStateForUpstream:(NSString *)url;

/*! Returns the number of repositories loaded by the last successful inventory crawl. */
- (NSUInteger)crawlRepoCountForUpstream:(NSString *)url;

/*! Returns the last inventory error summary, if any. */
- (nullable NSString *)crawlErrorForUpstream:(NSString *)url;

/**
 * @abstract Installs the bounded ingress executor for upstream events.
 */
- (void)configureBoundedIngressWithConfiguration:(ATProtoRelayIngressConfiguration *)configuration
                                        metrics:(nullable ATProtoRelayMetrics *)metrics
                                   processBlock:(RelayIngressProcessBlock)processBlock;

/**
 * Active ingress pipeline, or nil when legacy ingress is selected.
 *
 * Declared @c atomic (not the codebase default @c nonatomic): this pointer
 * is written once at configuration time from whatever thread calls
 * -configureBoundedIngressWithConfiguration:metrics:processBlock: and read
 * on every admitted event inside -ingressGateForUpstream:'s block, which
 * runs synchronously on the WebSocket read thread (see ADR 0039). The gate
 * path must not dispatch_sync onto @c _managerQueue -- that queue also
 * serializes slow operations (connect/disconnect/HTTP validation) -- so the
 * compiler-synthesized atomic accessors are used instead to guarantee a
 * safe, non-torn pointer read without taking any lock that could be held by
 * a queue blocked on the read thread.
 */
@property (atomic, strong, readonly, nullable) ATProtoRelayIngressPipeline *ingressPipeline;

@end

NS_ASSUME_NONNULL_END
