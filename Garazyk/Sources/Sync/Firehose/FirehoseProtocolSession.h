// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Sync/Relay/EventFormatter.h"
#import "Sync/Firehose/Firehose.h"

NS_ASSUME_NONNULL_BEGIN

@interface FirehoseProtocolSession : NSObject

@property(nonatomic, strong, readonly) EventFormatter *eventFormatter;
@property(nonatomic, assign, readonly) NSUInteger sequenceNumber;

- (instancetype)initWithSequenceNumber:(NSUInteger)sequenceNumber;

- (NSData *)encodeCommitEvent:(FirehoseCommitEvent *)event;
- (NSData *)encodeIdentityEvent:(FirehoseIdentityEvent *)event;
- (NSData *)encodeAccountEvent:(FirehoseAccountEvent *)event;
- (NSData *)encodeSyncEvent:(FirehoseSyncEvent *)event;
- (NSData *)encodeInfoEvent:(FirehoseInfoEvent *)event;
- (NSData *)encodeErrorEvent:(FirehoseErrorEvent *)event;

- (NSUInteger)nextSequenceNumber;

@end

NS_ASSUME_NONNULL_END
