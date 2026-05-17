// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Sync/Relay/EventFormatter.h"
#import "Sync/Firehose/Firehose.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Declares the FirehoseProtocolSession public API.
 */
@interface FirehoseProtocolSession : NSObject

/**
 * @abstract Exposes the event formatter value.
 */
@property(nonatomic, strong, readonly) EventFormatter *eventFormatter;
@property(nonatomic, assign, readonly) NSUInteger sequenceNumber;

/**
 * @abstract Performs the initWithSequenceNumber operation.
 */
- (instancetype)initWithSequenceNumber:(NSUInteger)sequenceNumber;

/**
 * @abstract Performs the encodeCommitEvent operation.
 */
- (NSData *)encodeCommitEvent:(FirehoseCommitEvent *)event;
/**
 * @abstract Performs the encodeIdentityEvent operation.
 */
- (NSData *)encodeIdentityEvent:(FirehoseIdentityEvent *)event;
/**
 * @abstract Performs the encodeAccountEvent operation.
 */
- (NSData *)encodeAccountEvent:(FirehoseAccountEvent *)event;
/**
 * @abstract Performs the encodeSyncEvent operation.
 */
- (NSData *)encodeSyncEvent:(FirehoseSyncEvent *)event;
/**
 * @abstract Performs the encodeInfoEvent operation.
 */
- (NSData *)encodeInfoEvent:(FirehoseInfoEvent *)event;
/**
 * @abstract Performs the encodeErrorEvent operation.
 */
- (NSData *)encodeErrorEvent:(FirehoseErrorEvent *)event;

/**
 * @abstract Returns the next sequence number result.
 */
- (NSUInteger)nextSequenceNumber;

@end

NS_ASSUME_NONNULL_END
