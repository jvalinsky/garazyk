// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Sync/Relay/EventFormatter.h"
#import "Sync/Firehose/Firehose.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Declares the ATProtoFirehoseProtocolSession public API.
 */
@interface ATProtoFirehoseProtocolSession : NSObject

/**
 * @abstract Exposes the event formatter value.
 */
@property(nonatomic, strong, readonly) ATProtoEventFormatter *eventFormatter;
@property(nonatomic, assign, readonly) NSUInteger sequenceNumber;

- (instancetype)initWithSequenceNumber:(NSUInteger)sequenceNumber;

- (NSData *)encodeCommitEvent:(ATProtoFirehoseCommitEvent *)event;
- (NSData *)encodeIdentityEvent:(ATProtoFirehoseIdentityEvent *)event;
- (NSData *)encodeAccountEvent:(ATProtoFirehoseAccountEvent *)event;
- (NSData *)encodeSyncEvent:(ATProtoFirehoseSyncEvent *)event;
- (NSData *)encodeInfoEvent:(ATProtoFirehoseInfoEvent *)event;
- (NSData *)encodeErrorEvent:(ATProtoFirehoseErrorEvent *)event;

/**
 * @abstract Returns the next sequence number result.
 */
- (NSUInteger)nextSequenceNumber;

@end

NS_ASSUME_NONNULL_END
