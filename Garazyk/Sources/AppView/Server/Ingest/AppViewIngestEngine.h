// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AppViewIngestEngine.h

 @abstract Global ingest plane: consumes subscribeRepos from one or more relays,
 persists raw events idempotently, and dispatches to the materialization layer.

 @discussion The ingest engine owns the single global stream. It:
  1. Connects to each configured relay URL via RelayClient.
  2. Persists a raw event log entry per event (idempotent by did+rev+cid).
  3. Checkpoints the cursor every `checkpointIntervalMs` milliseconds.
  4. For commit events: checks repo sync status and either materializes
     immediately (synced) or enqueues a PendingDelta (processing).
  5. On reconnect, resumes from the persisted checkpoint.

 The engine emits events to the materialization delegates on a background
 serial queue. Callers must not block from delegate callbacks.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FirehoseCommitEvent;
@class FirehoseIdentityEvent;
@class AppViewDatabase;
@class AppViewIngestEngine;
@class AppViewIngestEvent;
/**
 * @abstract Defines the AppViewIndexer protocol contract.
 */
@protocol AppViewIndexer;

/*!
 @protocol AppViewIngestEngineDelegate

 @abstract Receives commit and identity events after idempotency filtering.
 */
@protocol AppViewIngestEngineDelegate <NSObject>
@optional

/*!
 @method ingestEngine:didReceiveCommit:

 @abstract Called for each unique commit event (did+rev+cid).
 May be called from a background queue — do not update UI directly.
 */
- (void)ingestEngine:(AppViewIngestEngine *)engine
   didReceiveCommit:(AppViewIngestEvent *)event;

/*!
 @method ingestEngine:didReceiveIdentityChange:

 @abstract Called for identity events (#identity type).
 */
- (void)ingestEngine:(AppViewIngestEngine *)engine
didReceiveIdentityChange:(AppViewIngestEvent *)event;

/*!
 @method ingestEngine:didReconnectToRelay:atSeq:

 @abstract Called after each successful reconnect.
 */
- (void)ingestEngine:(AppViewIngestEngine *)engine
  didReconnectToRelay:(NSString *)relayURL
               atSeq:(int64_t)seq;

@end

/*!
 @interface AppViewIngestEvent

 @abstract A decoded ingest event ready for downstream processing.
 */
@interface AppViewIngestEvent : NSObject

/*! Global relay sequence number. */
@property (nonatomic, assign) int64_t seq;

/*! The relay URL this event came from. */
@property (nonatomic, copy)   NSString *relayURL;

/*! DID of the repository (nil for non-commit events). */
@property (nonatomic, copy, nullable) NSString *did;

/*! Commit revision string (nil for non-commit events). */
@property (nonatomic, copy, nullable) NSString *rev;

/*! Commit CID string (nil for non-commit events). */
@property (nonatomic, copy, nullable) NSString *cid;

/*! Event type string: "#commit", "#identity", "#account", "#info". */
@property (nonatomic, copy)   NSString *eventType;

/*! Decoded ops from the commit (array of dicts with collection/rkey/action/record). */
@property (nonatomic, strong, nullable) NSArray<NSDictionary *> *ops;

/*! Raw CBOR envelope bytes. */
@property (nonatomic, strong) NSData *rawEnvelope;

/*! Time the event was received. */
@property (nonatomic, strong) NSDate *receivedAt;

@end

/*!
 @interface AppViewIngestEngine

 @abstract Manages realtime ingest from one or more subscribeRepos relay streams.
 */
@interface AppViewIngestEngine : NSObject

/*! Delegate for ingest events. */
@property (nonatomic, weak, nullable) id<AppViewIngestEngineDelegate> delegate;

/*! Milliseconds between cursor checkpoints. Defaults to 5000 (5 s). */
@property (nonatomic, assign) NSUInteger checkpointIntervalMs;

/*! Whether ingest is currently running. */
@property (nonatomic, readonly) BOOL isRunning;

/*! Current lag: relay head seq minus last checkpointed seq, per relay URL. */
@property (nonatomic, readonly) NSDictionary<NSString *, NSNumber *> *lagByRelay;

/*! Relay connectivity status: connected/disconnected/error per relay URL. */
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *relayHealth;

/*! Throughput metrics: events/sec per relay URL. */
@property (nonatomic, readonly) NSDictionary<NSString *, NSNumber *> *throughput;

/*! Heartbeat timeout for relay connections in seconds. Default 10.0. */
@property (nonatomic, assign) NSTimeInterval relayHeartbeatTimeout;

/*! Maximum lag (seq gap) before backpressure kicks in. Default 50000. */
@property (nonatomic, assign) int64_t maxLagForBackpressure;

/*!
 @method initWithDatabase:relayURLs:

 @param database AppView database for checkpoints and event log.
 @param relayURLs Array of relay URLs to subscribe to (e.g. wss://bsky.network).
 */
- (instancetype)initWithDatabase:(AppViewDatabase *)database
                       relayURLs:(NSArray<NSString *> *)relayURLs;

/*!
 @method start

 @abstract Begin consuming all configured relays from their last checkpoint.
 */
- (void)start;

/*!
 @method stop

 @abstract Gracefully disconnect from all relays and flush checkpoints.
 */
- (void)stop;

/*!
 @method flushCheckpoints

 @abstract Force a checkpoint write for all active relays. Safe to call at any time.
 */
- (void)flushCheckpoints;

// ---------------------------------------------------------------------------
// Internal methods (for delegate callbacks)
// ---------------------------------------------------------------------------

/**
 * @abstract Performs the _handleCommitEvent operation.
 */
- (void)_handleCommitEvent:(FirehoseCommitEvent *)event fromRelay:(NSString *)relayURL;
/**
 * @abstract Performs the _handleIdentityEvent operation.
 */
- (void)_handleIdentityEvent:(FirehoseIdentityEvent *)event fromRelay:(NSString *)relayURL;
/**
 * @abstract Performs the _relayConnection operation.
 */
- (void)_relayConnection:(id)connection didConnectAtSeq:(int64_t)seq;

@end

NS_ASSUME_NONNULL_END
