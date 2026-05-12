// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Sync/Firehose/FirehoseProtocolSession.h"
#import "Debug/GZLogger.h"

@interface FirehoseProtocolSession () {
    dispatch_queue_t _sequenceQueue;
}
@property(nonatomic, strong, readwrite) EventFormatter *eventFormatter;
@property(nonatomic, assign, readwrite) NSUInteger sequenceNumber;
@end

@implementation FirehoseProtocolSession

- (instancetype)initWithSequenceNumber:(NSUInteger)sequenceNumber {
  self = [super init];
  if (self) {
    _sequenceNumber = sequenceNumber;
    _eventFormatter = [[EventFormatter alloc] init];
    _sequenceQueue = dispatch_queue_create("com.atproto.firehose.sequence", DISPATCH_QUEUE_SERIAL);
  }
  return self;
}

- (NSData *)encodeCommitEvent:(FirehoseCommitEvent *)event {
   __block NSUInteger seq;
   dispatch_sync(_sequenceQueue, ^{
     _sequenceNumber++;
     seq = _sequenceNumber;
   });
  event.seq = seq;
  NSError *error = nil;
  NSData *data = [self.eventFormatter encodeCommitEvent:event error:&error];
  if (!data) {
    GZ_LOG_SYNC_ERROR(@"Failed to encode commit event: %@", error);
  }
  return data;
}

- (NSData *)encodeIdentityEvent:(FirehoseIdentityEvent *)event {
   __block NSUInteger seq;
   dispatch_sync(_sequenceQueue, ^{
     _sequenceNumber++;
     seq = _sequenceNumber;
   });
  event.seq = seq;
  NSError *error = nil;
  NSData *data = [self.eventFormatter encodeIdentityEvent:event error:&error];
  if (!data) {
    GZ_LOG_SYNC_ERROR(@"Failed to encode identity event: %@", error);
  }
  return data;
}

- (NSData *)encodeAccountEvent:(FirehoseAccountEvent *)event {
   __block NSUInteger seq;
   dispatch_sync(_sequenceQueue, ^{
     _sequenceNumber++;
     seq = _sequenceNumber;
   });
  event.seq = seq;
  NSError *error = nil;
  NSData *data = [self.eventFormatter encodeAccountEvent:event error:&error];
  if (!data) {
    GZ_LOG_SYNC_ERROR(@"Failed to encode account event: %@", error);
  }
  return data;
}

- (NSData *)encodeSyncEvent:(FirehoseSyncEvent *)event {
   __block NSUInteger seq;
   dispatch_sync(_sequenceQueue, ^{
     _sequenceNumber++;
     seq = _sequenceNumber;
   });
  event.seq = seq;
  NSError *error = nil;
  NSData *data = [self.eventFormatter encodeSyncEvent:event error:&error];
  if (!data) {
    GZ_LOG_SYNC_ERROR(@"Failed to encode sync event: %@", error);
  }
  return data;
}

- (NSData *)encodeInfoEvent:(FirehoseInfoEvent *)event {
  NSError *error = nil;
  NSData *data = [self.eventFormatter encodeInfoEvent:event error:&error];
  if (!data) {
    GZ_LOG_SYNC_ERROR(@"Failed to encode info event: %@", error);
  }
  return data;
}

- (NSData *)encodeErrorEvent:(FirehoseErrorEvent *)event {
  NSError *error = nil;
  NSData *data = [self.eventFormatter encodeErrorEvent:event error:&error];
  if (!data) {
    GZ_LOG_SYNC_ERROR(@"Failed to encode error event: %@", error);
  }
  return data;
}

- (NSUInteger)nextSequenceNumber {
  __block NSUInteger seq;
  dispatch_sync(_sequenceQueue, ^{
    _sequenceNumber++;
    seq = _sequenceNumber;
  });
  return seq;
}

@end
