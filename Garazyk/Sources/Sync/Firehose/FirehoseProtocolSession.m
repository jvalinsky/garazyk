#import "Sync/Firehose/FirehoseProtocolSession.h"
#import "Debug/PDSLogger.h"

@interface FirehoseProtocolSession ()
@property(nonatomic, strong, readwrite) EventFormatter *eventFormatter;
@property(nonatomic, assign, readwrite) NSUInteger sequenceNumber;
@end

@implementation FirehoseProtocolSession

- (instancetype)initWithSequenceNumber:(NSUInteger)sequenceNumber {
  self = [super init];
  if (self) {
    _sequenceNumber = sequenceNumber;
    _eventFormatter = [[EventFormatter alloc] init];
  }
  return self;
}

- (NSData *)encodeCommitEvent:(FirehoseCommitEvent *)event {
  NSUInteger seq;
  @synchronized(self) {
    _sequenceNumber++;
    seq = _sequenceNumber;
  }
  event.seq = seq;
  NSError *error = nil;
  NSData *data = [self.eventFormatter encodeCommitEvent:event error:&error];
  if (!data) {
    PDS_LOG_SYNC_ERROR(@"Failed to encode commit event: %@", error);
  }
  return data;
}

- (NSData *)encodeIdentityEvent:(FirehoseIdentityEvent *)event {
  NSUInteger seq;
  @synchronized(self) {
    _sequenceNumber++;
    seq = _sequenceNumber;
  }
  event.seq = seq;
  NSError *error = nil;
  NSData *data = [self.eventFormatter encodeIdentityEvent:event error:&error];
  if (!data) {
    PDS_LOG_SYNC_ERROR(@"Failed to encode identity event: %@", error);
  }
  return data;
}

- (NSData *)encodeAccountEvent:(FirehoseAccountEvent *)event {
  NSUInteger seq;
  @synchronized(self) {
    _sequenceNumber++;
    seq = _sequenceNumber;
  }
  event.seq = seq;
  NSError *error = nil;
  NSData *data = [self.eventFormatter encodeAccountEvent:event error:&error];
  if (!data) {
    PDS_LOG_SYNC_ERROR(@"Failed to encode account event: %@", error);
  }
  return data;
}

- (NSData *)encodeInfoEvent:(FirehoseInfoEvent *)event {
  NSUInteger seq;
  @synchronized(self) {
    _sequenceNumber++;
    seq = _sequenceNumber;
  }
  event.seq = seq;
  NSError *error = nil;
  NSData *data = [self.eventFormatter encodeInfoEvent:event error:&error];
  if (!data) {
    PDS_LOG_SYNC_ERROR(@"Failed to encode info event: %@", error);
  }
  return data;
}

- (NSData *)encodeErrorEvent:(FirehoseErrorEvent *)event {
  NSError *error = nil;
  NSData *data = [self.eventFormatter encodeErrorEvent:event error:&error];
  if (!data) {
    PDS_LOG_SYNC_ERROR(@"Failed to encode error event: %@", error);
  }
  return data;
}

- (NSUInteger)nextSequenceNumber {
  @synchronized(self) {
    _sequenceNumber++;
    return _sequenceNumber;
  }
}

@end
