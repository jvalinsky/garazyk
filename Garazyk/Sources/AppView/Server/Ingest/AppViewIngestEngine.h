// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZAppViewIngestEngine.h

 @abstract Global ingest plane: consumes subscribeRepos from one or more relays,
 persists raw events idempotently, and dispatches to the materialization layer.

 @discussion The ingest engine owns the single global stream. It:
  1. Connects to each configured relay URL via ATProtoRelayClient.
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

@class ATProtoFirehoseCommitEvent;
@class ATProtoFirehoseIdentityEvent;
@class ATProtoFirehoseAccountEvent;
@class GZAppViewDatabase;
@class GZAppViewIngestEngine;
@class GZAppViewIngestEvent;
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
- (void)ingestEngine:(GZAppViewIngestEngine *)engine
   didReceiveCommit:(GZAppViewIngestEvent *)event;

/*!
 @method ingestEngine:didReceiveIdentityChange:

 @abstract Called for identity events (#identity type).
 */
- (void)ingestEngine:(GZAppViewIngestEngine *)engine
didReceiveIdentityChange:(GZAppViewIngestEvent *)event;

/*!
 @method ingestEngine:didReceiveAccountEvent:

 @abstract Called for account events (#account type, including takedowns).
 */
- (void)ingestEngine:(GZAppViewIngestEngine *)engine
didReceiveAccountEvent:(GZAppViewIngestEvent *)event;

/*!
 @method ingestEngine:didReconnectToRelay:atSeq:

 @abstract Called after each successful reconnect.
 */
- (void)ingestEngine:(GZAppViewIngestEngine *)engine
  didReconnectToRelay:(NSString *)relayURL
               atSeq:(int64_t)seq;

/*!
 @method ingestEngine:didDetectGapForDID:atSeq:

 @abstract Called when commit continuity is broken and the repo needs backfill repair.
 */
- (void)ingestEngine:(GZAppViewIngestEngine *)engine
  didDetectGapForDID:(NSString *)did
               atSeq:(int64_t)seq;

@end

/*!
 @interface GZAppViewIngestEvent

 @abstract A decoded ingest event ready for downstream processing.
 */
@interface GZAppViewIngestEvent : NSObject

/*! Global relay sequence number. */
@property (nonatomic, assign) int64_t seq;

/*! The relay URL this event came from. */
@property (nonatomic, copy)   NSString *relayURL;

/*! DID of the repository (nil for non-commit events). */
@property (nonatomic, copy, nullable) NSString *did;

/*! Commit revision string (nil for non-commit events). */
@property (nonatomic, copy, nullable) NSString *rev;

/*! Commit ATProtoCID string (nil for non-commit events). */
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
 @interface GZAppViewIngestEngine

 @abstract Manages realtime ingest from one or more subscribeRepos relay streams.
 */
@interface GZAppViewIngestEngine : NSObject

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

/*! Maximum pending event count before ingest pauses. Default 100,000. */
@property (nonatomic, assign) NSUInteger indexQueueHighWatermarkEvents;

/*! Maximum pending raw-envelope bytes before ingest pauses. Default 2 GiB. */
@property (nonatomic, assign) uint64_t indexQueueHighWatermarkBytes;

/*!
 @method initWithDatabase:relayURLs:

 @param database AppView database for checkpoints and event log.
 @param relayURLs Array of relay URLs to subscribe to (e.g. wss://bsky.network).
 */
- (instancetype)initWithDatabase:(GZAppViewDatabase *)database
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

/*!
 @method waitForIndexQueueDrainForTesting

 @abstract Blocks until queued event persistence and index processing are idle.

 @discussion Tests should call this before inspecting database state or closing
 the database.
 */
- (void)waitForIndexQueueDrainForTesting;

// ---------------------------------------------------------------------------
// Internal methods (for delegate callbacks)
// ---------------------------------------------------------------------------

- (void)_handleCommitEvent:(ATProtoFirehoseCommitEvent *)event fromRelay:(NSString *)relayURL;
- (void)_handleIdentityEvent:(ATProtoFirehoseIdentityEvent *)event fromRelay:(NSString *)relayURL;
/**
 * @abstract Handles an account event from the relay firehose.
 */
- (void)_handleAccountEvent:(ATProtoFirehoseAccountEvent *)event fromRelay:(NSString *)relayURL;
- (void)_relayConnection:(id)connection didConnectAtSeq:(int64_t)seq;

@end

NS_ASSUME_NONNULL_END
