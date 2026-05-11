// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PLCSyncClient.h

 @abstract HTTP client for syncing PLC operations from upstream directory.

 @discussion
    PLCSyncClient fetches PLC operations from an upstream PLC directory server
    for use in a read replica. It supports:
    - Paginated fetching via the /export endpoint
    - Cursor-based sync for resumable operations
    - Automatic retry with exponential backoff

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "PLC/PLCOperation.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString * const PLCSyncClientErrorDomain;

typedef NS_ENUM(NSInteger, PLCSyncClientError) {
    PLCSyncClientErrorInvalidURL = 1,
    PLCSyncClientErrorNetworkFailure = 2,
    PLCSyncClientErrorInvalidResponse = 3,
    PLCSyncClientErrorParseFailure = 4
};

@protocol PLCSyncClientDelegate <NSObject>
@optional
- (void)syncClient:(id)client didReceiveOperations:(NSArray<PLCOperation *> *)ops;
- (void)syncClient:(id)client didEncounterError:(NSError *)error;
@end

@interface PLCSyncClient : NSObject

@property (nonatomic, weak, nullable) id<PLCSyncClientDelegate> delegate;
@property (nonatomic, copy, readonly) NSString *upstreamURL;
@property (nonatomic, assign) NSTimeInterval timeout;
@property (nonatomic, assign) NSUInteger maxRetries;

- (instancetype)initWithUpstreamURL:(NSString *)upstreamURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)fetchOperationsAfterCursor:(NSInteger)cursor
                             count:(NSUInteger)count
                         completion:(void (^)(NSArray<PLCOperation *> * _Nullable ops, NSInteger nextCursor, NSError * _Nullable error))completion;

- (void)fetchOperationsAfterDate:(nullable NSDate *)afterDate
                           count:(NSUInteger)count
                       completion:(void (^)(NSArray<PLCOperation *> * _Nullable ops, NSDate * _Nullable nextAfter, NSError * _Nullable error))completion;

- (nullable NSArray<PLCOperation *> *)fetchOperationsAfterCursorSync:(NSInteger)cursor
                                                                count:(NSUInteger)count
                                                               error:(NSError **)error;

- (NSInteger)getLatestCursorWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END