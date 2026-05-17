// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file RelayEventBuffer.h

 @abstract Event buffer with configurable retention window for the relay.

 @discussion
    RelayEventBuffer stores events for the configurable backfill window.
    Default is 72 hours per Sync v1.1 spec.
    
    - Circular buffer with timestamp-based eviction
    - Thread-safe access
    - Efficient sequence-based retrieval for backfill

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Stores recent relay events for cursor and time-based replay.
 */
@interface RelayEventBuffer : NSObject

/** Retention window in seconds. */
@property (nonatomic, assign, readonly) NSUInteger retentionSeconds;
/** Maximum number of events retained before older entries are discarded. */
@property (nonatomic, assign, readonly) NSUInteger maxEvents;

/**
 * @abstract Creates an event buffer with the supplied retention window and capacity.
 * @param hours Number of hours to retain events.
 * @param maxEvents Maximum number of events to keep.
 */
- (instancetype)initWithRetentionHours:(NSUInteger)hours maxEvents:(NSUInteger)maxEvents NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithRetentionHours:(NSUInteger)hours NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

/**
 * @abstract Creates a buffer using the relay default retention policy.
 */
+ (instancetype)bufferWithDefaultRetention;

/**
 * @abstract Appends an event using the current time as its timestamp.
 * @param event The event object to retain.
 * @param seq The firehose sequence number for the event.
 */
- (void)appendEvent:(id)event seq:(int64_t)seq;

/**
 * @abstract Appends an event with an explicit timestamp.
 * @param event The event object to retain.
 * @param seq The firehose sequence number for the event.
 * @param timestamp The timestamp used for retention and range queries.
 */
- (void)appendEvent:(id)event seq:(int64_t)seq timestamp:(NSDate *)timestamp;

/**
 * @abstract Returns retained events with sequence numbers after a cursor.
 * @param cursor The exclusive lower sequence bound.
 * @param count Maximum number of events to return.
 */
- (nullable NSArray *)eventsAfterCursor:(int64_t)cursor count:(NSUInteger)count;

/**
 * @abstract Returns retained events whose timestamps fall within a range.
 * @param start Inclusive start timestamp.
 * @param end Inclusive end timestamp.
 */
- (nullable NSArray *)eventsInTimeRange:(NSDate *)start end:(NSDate *)end;

/** Returns the oldest retained sequence number. */
- (int64_t)oldestSequence;
/** Returns the newest retained sequence number. */
- (int64_t)newestSequence;
/** Returns the number of retained events. */
- (NSUInteger)eventCount;

/**
 * @abstract Removes events older than the configured retention window.
 */
- (void)pruneExpired;

/**
 * @abstract Removes all retained events.
 */
- (void)clear;

@end

NS_ASSUME_NONNULL_END
