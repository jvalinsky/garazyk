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

@interface RelayEventBuffer : NSObject

@property (nonatomic, assign, readonly) NSUInteger retentionSeconds;
@property (nonatomic, assign, readonly) NSUInteger maxEvents;

- (instancetype)initWithRetentionHours:(NSUInteger)hours maxEvents:(NSUInteger)maxEvents NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)appendEvent:(id)event seq:(int64_t)seq;
- (void)appendEvent:(id)event seq:(int64_t)seq timestamp:(NSDate *)timestamp;

- (nullable NSArray *)eventsAfterCursor:(int64_t)cursor count:(NSUInteger)count;
- (nullable NSArray *)eventsInTimeRange:(NSDate *)start end:(NSDate *)end;

- (int64_t)oldestSequence;
- (int64_t)newestSequence;
- (NSUInteger)eventCount;

- (void)pruneExpired;
- (void)clear;

@end

NS_ASSUME_NONNULL_END