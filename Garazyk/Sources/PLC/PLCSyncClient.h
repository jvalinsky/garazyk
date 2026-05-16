// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file PLCSyncClient.h
 * @abstract HTTP client for syncing PLC operations from upstream directory.
 * @discussion PLCSyncClient fetches PLC operations from an upstream PLC directory server
 * for use in a read replica. It supports paginated fetching via the /export endpoint,
 * cursor-based sync for resumable operations, and automatic retry with exponential backoff.
 */

#import <Foundation/Foundation.h>
#import "PLC/PLCOperation.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Error domain for PLC sync client operations.
 */
extern NSString * const PLCSyncClientErrorDomain;

/**
 * @abstract Error codes for PLC sync operations.
 */
typedef NS_ENUM(NSInteger, PLCSyncClientError) {
    PLCSyncClientErrorInvalidURL = 1,
    PLCSyncClientErrorNetworkFailure = 2,
    PLCSyncClientErrorInvalidResponse = 3,
    PLCSyncClientErrorParseFailure = 4
};

/**
 * @abstract Delegate protocol for monitoring sync progress and errors.
 */
@protocol PLCSyncClientDelegate <NSObject>
@optional

/**
 * @abstract Invoked when operations are received.
 * @param client The calling sync client.
 * @param ops Array of received operations.
 */
- (void)syncClient:(id)client didReceiveOperations:(NSArray<PLCOperation *> *)ops;

/**
 * @abstract Invoked when a synchronization error occurs.
 * @param client The calling sync client.
 * @param error The encountered error.
 */
- (void)syncClient:(id)client didEncounterError:(NSError *)error;
@end

/**
 * @abstract Client for fetching PLC directory operations.
 */
@interface PLCSyncClient : NSObject

/** @abstract Delegate for sync notifications. */
@property (nonatomic, weak, nullable) id<PLCSyncClientDelegate> delegate;
/** @abstract URL of the upstream PLC directory. */
@property (nonatomic, copy, readonly) NSString *upstreamURL;
/** @abstract Network request timeout. */
@property (nonatomic, assign) NSTimeInterval timeout;
/** @abstract Maximum retry attempts for failed operations. */
@property (nonatomic, assign) NSUInteger maxRetries;

/**
 * @abstract Initializes a sync client with an upstream URL.
 * @param upstreamURL The URL of the upstream service.
 * @return An initialized sync client instance.
 */
- (instancetype)initWithUpstreamURL:(NSString *)upstreamURL NS_DESIGNATED_INITIALIZER;

/** @abstract Unavailable initializer. */
- (instancetype)init NS_UNAVAILABLE;

/**
 * @abstract Fetches operations after a specific cursor.
 * @param cursor The starting cursor index.
 * @param count Number of operations to fetch.
 * @param completion Completion block with operations and the next cursor index.
 */
- (void)fetchOperationsAfterCursor:(NSInteger)cursor
                             count:(NSUInteger)count
                         completion:(void (^)(NSArray<PLCOperation *> * _Nullable ops, NSInteger nextCursor, NSError * _Nullable error))completion;

/**
 * @abstract Fetches operations after a given date.
 * @param afterDate The start date (optional).
 * @param count Number of operations to fetch.
 * @param completion Completion block with operations and the next date cursor.
 */
- (void)fetchOperationsAfterDate:(nullable NSDate *)afterDate
                           count:(NSUInteger)count
                       completion:(void (^)(NSArray<PLCOperation *> * _Nullable ops, NSDate * _Nullable nextAfter, NSError * _Nullable error))completion;

/**
 * @abstract Synchronously fetches operations after a specific cursor.
 * @param cursor The starting cursor index.
 * @param count Number of operations to fetch.
 * @param error Receives failure details.
 * @return Array of operations, or nil on failure.
 */
- (nullable NSArray<PLCOperation *> *)fetchOperationsAfterCursorSync:(NSInteger)cursor
                                                                count:(NSUInteger)count
                                                               error:(NSError **)error;

/**
 * @abstract Retrieves the latest cursor from the upstream server.
 * @param error Receives failure details.
 * @return Latest cursor index, or -1 on failure.
 */
- (NSInteger)getLatestCursorWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END