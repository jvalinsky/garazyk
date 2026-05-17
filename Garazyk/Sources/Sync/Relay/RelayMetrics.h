// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file RelayMetrics.h

 @abstract Metrics collection for ATProto Relay (Sync v1.1)

 @discussion
    RelayMetrics tracks:
    - Upstream connections (PDS subscriptions)
    - Downstream connections (consumer subscriptions)
    - Events received, validated, forwarded, dropped
    - Validation failures by type
    - Sequence numbers and cursors

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import <stdint.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Collects counters and gauges for relay health and throughput.
 */
@interface RelayMetrics : NSObject

/**
 * @abstract Returns the process-wide relay metrics registry.
 */
+ (instancetype)sharedMetrics;

/** Increments the number of connected upstream PDS streams. */
- (void)recordUpstreamConnected;
/** Decrements the number of connected upstream PDS streams. */
- (void)recordUpstreamDisconnected;
/** Increments the number of connected downstream consumers. */
- (void)recordDownstreamConnected;
/** Decrements the number of connected downstream consumers. */
- (void)recordDownstreamDisconnected;

/** Records that an event was received from an upstream. */
- (void)recordEventReceived;
/** Records that an event passed validation. */
- (void)recordEventValidated;
/**
 * @abstract Records that an event failed validation.
 * @param reason Caller-facing failure category for metrics output.
 */
- (void)recordEventInvalidated:(NSString *)reason;
/** Records that an event was forwarded downstream. */
- (void)recordEventForwarded;
/** Records that an event was dropped. */
- (void)recordEventDropped;

/** Records a successful MST validation. */
- (void)recordMSTValidationSuccess;
/** Records a failed MST validation. */
- (void)recordMSTValidationFailure;
/** Records a successful repository signature validation. */
- (void)recordSignatureValidationSuccess;
/** Records a failed repository signature validation. */
- (void)recordSignatureValidationFailure;

/**
 * @abstract Records the latest observed firehose sequence.
 * @param seq The observed sequence number.
 */
- (void)recordSequence:(int64_t)seq;

/**
 * @abstract Sets the current relay sequence gauge.
 * @param seq The sequence number to expose as current.
 */
- (void)setCurrentSequence:(int64_t)seq;

/**
 * @abstract Records the duration of a backfill operation.
 * @param durationMs Duration in milliseconds.
 */
- (void)recordBackfillDuration:(NSTimeInterval)durationMs;

/** Records one upstream reconnection attempt. */
- (void)recordReconnectionCount;

/**
 * @abstract Renders all metrics using Prometheus exposition text.
 * @return A Prometheus-compatible metrics payload.
 */
- (NSString *)renderPrometheusMetrics;

/*!
 @method snapshotDictionary

 @abstract Returns a dictionary snapshot of all metrics for JSON API.

 @return Dictionary with all current metric values.
 */
- (NSDictionary *)snapshotDictionary;

/**
 * @abstract Exposes the upstream connections value.
 */
@property (nonatomic, readonly) int64_t upstreamConnections;
/** Number of connected downstream subscribers. */
@property (nonatomic, readonly) int64_t downstreamConnections;
/** Total events received from upstreams. */
@property (nonatomic, readonly) int64_t eventsReceived;
/** Total events that passed relay validation. */
@property (nonatomic, readonly) int64_t eventsValidated;
/** Total events that failed relay validation. */
@property (nonatomic, readonly) int64_t eventsInvalidated;
/** Total events forwarded to downstream subscribers. */
@property (nonatomic, readonly) int64_t eventsForwarded;
/** Total events dropped before forwarding. */
@property (nonatomic, readonly) int64_t eventsDropped;
/** Total successful MST validations. */
@property (nonatomic, readonly) int64_t mstValidationSuccess;
/** Total failed MST validations. */
@property (nonatomic, readonly) int64_t mstValidationFailure;
/** Total successful signature validations. */
@property (nonatomic, readonly) int64_t signatureValidationSuccess;
/** Total failed signature validations. */
@property (nonatomic, readonly) int64_t signatureValidationFailure;
/** Latest sequence exposed by the relay. */
@property (nonatomic, readonly) int64_t currentSequence;
/** Total upstream reconnection attempts. */
@property (nonatomic, readonly) int64_t reconnectionCount;

@end

NS_ASSUME_NONNULL_END
