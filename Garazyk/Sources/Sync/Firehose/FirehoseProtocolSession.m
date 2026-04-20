#import "Sync/Firehose/FirehoseProtocolSession.h"
#import "Debug/PDSLogger.h"

@interface FirehoseProtocolSession ()
@property(nonatomic, strong, readwrite) EventFormatter *eventFormatter;
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
  self.sequenceNumber++;
  event.seq = self.sequenceNumber;
  NSError *error = nil;
  NSData *data = [self.eventFormatter encodeCommitEvent:event error:&error];
  if (!data) {
    PDS_LOG_SYNC_ERROR(@"Failed to encode commit event: %@", error);
  }
  return data;
}

- (NSData *)encodeIdentityEvent:(FirehoseIdentityEvent *)event {
  self.sequenceNumber++;
  event.seq = self.sequenceNumber;
  NSError *error = nil;
  NSData *data = [self.eventFormatter encodeIdentityEvent:event error:&error];
  if (!data) {
    PDS_LOG_SYNC_ERROR(@"Failed to encode identity event: %@", error);
  }
  return data;
}

- (NSData *)encodeAccountEvent:(FirehoseAccountEvent *)event {
  self.sequenceNumber++;
  event.seq = self.sequenceNumber;
  NSError *error = nil;
  NSData *data = [self.eventFormatter encodeAccountEvent:event error:&error];
  if (!data) {
    PDS_LOG_SYNC_ERROR(@"Failed to encode account event: %@", error);
  }
  return data;
}

- (NSData *)encodeInfoEvent:(FirehoseInfoEvent *)event {
  self.sequenceNumber++;
  // Info events don't strictly require seq in some lexicons, but we increment anyway if it's there
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

@end
