// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file GZBeskidFirehoseInvalidator.h
 * @abstract Optional relay firehose subscription that evicts Beskid cache rows.
 */

#import <Foundation/Foundation.h>

@class GZBeskidConfiguration;
@class GZBeskidDatabase;
@class GZBeskidMetrics;
@class ATProtoFirehoseCommitEvent;
@class ATProtoFirehoseIdentityEvent;
@class ATProtoFirehoseAccountEvent;

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Subscribes to com.atproto.sync.subscribeRepos and applies early
 *           cache eviction. Inert when firehoseEnabled is NO.
 */
@interface GZBeskidFirehoseInvalidator : NSObject

@property (nonatomic, readonly, getter=isRunning) BOOL running;
@property (nonatomic, readonly, getter=isConnected) BOOL connected;
@property (nonatomic, readonly) int64_t currentCursor;

- (instancetype)initWithDatabase:(GZBeskidDatabase *)database
                         metrics:(GZBeskidMetrics *)metrics
                   configuration:(GZBeskidConfiguration *)configuration NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (BOOL)startWithError:(NSError **)error;
- (void)stop;

#pragma mark - Event handlers (testable)

- (void)handleCommitEvent:(ATProtoFirehoseCommitEvent *)event;
- (void)handleIdentityEvent:(ATProtoFirehoseIdentityEvent *)event;
- (void)handleAccountEvent:(ATProtoFirehoseAccountEvent *)event;

@end

NS_ASSUME_NONNULL_END
