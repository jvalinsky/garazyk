// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file PLCReplicaStore.h
 * @abstract Persistent store with sync state tracking for PLC replica.
 * @discussion Extends PLCPersistentStore with sync state management for replica operation.
 * Tracks cursor position, upstream URL, and last sync timestamp to enable resumable sync
 * from upstream PLC directory.
 */

#import <Foundation/Foundation.h>
#import "PLC/PLCPersistentStore.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Error domain for PLC replica store operations.
 */
extern NSString * const PLCReplicaStoreErrorDomain;

/**
 * @abstract Error codes for PLC replica store.
 */
typedef NS_ENUM(NSInteger, PLCReplicaStoreError) {
    PLCReplicaStoreErrorDatabaseClosed = 1,
    PLCReplicaStoreErrorInvalidValue = 2
};

/**
 * @abstract Manages persistent sync state and metadata for a PLC replica.
 */
@interface PLCReplicaStore : PLCPersistentStore

/**
 * @abstract Updates the sync cursor position.
 * @param cursor The new cursor index.
 * @param error Receives failure details.
 * @return YES if successful.
 */
- (BOOL)updateSyncCursor:(NSInteger)cursor error:(NSError **)error;

/**
 * @abstract Retrieves the last sync cursor position.
 * @param error Receives failure details.
 * @return Cursor index, or -1 on failure.
 */
- (NSInteger)lastSyncCursorWithError:(NSError **)error;

/**
 * @abstract Updates the last synchronization timestamp.
 * @param timestamp The new sync timestamp.
 * @param error Receives failure details.
 * @return YES if successful.
 */
- (BOOL)updateLastSyncTimestamp:(NSDate *)timestamp error:(NSError **)error;

/**
 * @abstract Retrieves the last synchronization timestamp.
 * @param error Receives failure details.
 * @return The last sync timestamp, or nil on failure.
 */
- (nullable NSDate *)lastSyncTimestampWithError:(NSError **)error;

/**
 * @abstract Updates the upstream URL for synchronization.
 * @param url The new upstream URL.
 * @param error Receives failure details.
 * @return YES if successful.
 */
- (BOOL)updateUpstreamURL:(NSString *)url error:(NSError **)error;

/**
 * @abstract Retrieves the current upstream URL.
 * @param error Receives failure details.
 * @return The upstream URL, or nil on failure.
 */
- (nullable NSString *)upstreamURLWithError:(NSError **)error;

/**
 * @abstract Updates the current sync state.
 * @param state The sync state string.
 * @param error Receives failure details.
 * @return YES if successful.
 */
- (BOOL)updateSyncState:(NSString *)state error:(NSError **)error;

/**
 * @abstract Retrieves the current sync state.
 * @param error Receives failure details.
 * @return The sync state, or nil on failure.
 */
- (nullable NSString *)syncStateWithError:(NSError **)error;

/**
 * @abstract Updates the latest ingested cursor.
 * @param cursor The new ingested cursor index.
 * @param error Receives failure details.
 * @return YES if successful.
 */
- (BOOL)updateLatestIngestedCursor:(NSInteger)cursor error:(NSError **)error;

/**
 * @abstract Retrieves the latest ingested cursor.
 * @param error Receives failure details.
 * @return Ingested cursor index, or -1 on failure.
 */
- (NSInteger)latestIngestedCursorWithError:(NSError **)error;

/**
 * @abstract Gets the total operation count.
 * @param error Receives failure details.
 * @return Operation count.
 */
- (NSUInteger)totalOperationCountWithError:(NSError **)error;

/**
 * @abstract Gets the count of unique DIDs tracked.
 * @param error Receives failure details.
 * @return DID count.
 */
- (NSUInteger)uniqueDIDCountWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END