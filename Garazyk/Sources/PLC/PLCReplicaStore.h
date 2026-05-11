// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PLCReplicaStore.h

 @abstract Persistent store with sync state tracking for PLC replica.

 @discussion
    Extends PLCPersistentStore with sync state management for replica operation.
    Tracks cursor position, upstream URL, and last sync timestamp to enable
    resumable sync from upstream PLC directory.

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "PLC/PLCPersistentStore.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString * const PLCReplicaStoreErrorDomain;

typedef NS_ENUM(NSInteger, PLCReplicaStoreError) {
    PLCReplicaStoreErrorDatabaseClosed = 1,
    PLCReplicaStoreErrorInvalidValue = 2
};

@interface PLCReplicaStore : PLCPersistentStore

- (BOOL)updateSyncCursor:(NSInteger)cursor error:(NSError **)error;
- (NSInteger)lastSyncCursorWithError:(NSError **)error;

- (BOOL)updateLastSyncTimestamp:(NSDate *)timestamp error:(NSError **)error;
- (nullable NSDate *)lastSyncTimestampWithError:(NSError **)error;

- (BOOL)updateUpstreamURL:(NSString *)url error:(NSError **)error;
- (nullable NSString *)upstreamURLWithError:(NSError **)error;

- (BOOL)updateSyncState:(NSString *)state error:(NSError **)error;
- (nullable NSString *)syncStateWithError:(NSError **)error;

- (BOOL)updateLatestIngestedCursor:(NSInteger)cursor error:(NSError **)error;
- (NSInteger)latestIngestedCursorWithError:(NSError **)error;

- (NSUInteger)totalOperationCountWithError:(NSError **)error;
- (NSUInteger)uniqueDIDCountWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END