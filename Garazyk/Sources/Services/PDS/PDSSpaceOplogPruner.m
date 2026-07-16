// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Services/PDS/PDSSpaceOplogPruner.h"

#import "Compat/PDSTypes.h"
#import "Services/PDS/PDSSpaceStore.h"

static const NSTimeInterval PDSSpaceOplogPrunerMinimumInterval = 300.0;

@interface PDSSpaceOplogPruner ()
@property(nonatomic, strong) PDSSpaceStore *spaceStore;
@property(nonatomic, assign) NSUInteger retentionRevisions;
@property(nonatomic, assign) NSTimeInterval interval;
@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t queue;
@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG, nullable) dispatch_source_t timer;
@property(nonatomic, assign) BOOL stopped;
@end

@implementation PDSSpaceOplogPruner

- (instancetype)initWithSpaceStore:(PDSSpaceStore *)spaceStore
                retentionRevisions:(NSUInteger)retentionRevisions
      intervalInSeconds:(NSTimeInterval)interval {
  self = [super init];
  if (!self) return nil;
  _spaceStore = spaceStore;
  _retentionRevisions = retentionRevisions;
  _interval = MAX(interval, PDSSpaceOplogPrunerMinimumInterval);
  _queue = dispatch_queue_create("com.garazyk.pds.permissioned-spaces.oplog-prune", DISPATCH_QUEUE_SERIAL);
  _stopped = YES;
  return self;
}

- (void)start {
  dispatch_async(self.queue, ^{
    if (!self.stopped) return;
    if (self.retentionRevisions == 0) return;
    self.stopped = NO;
    dispatch_async(self.queue, ^{ [self pruneOnQueue]; });
    self.timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue);
    uint64_t intervalNanos = (uint64_t)(self.interval * (NSTimeInterval)NSEC_PER_SEC);
    dispatch_source_set_timer(self.timer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)intervalNanos),
                              intervalNanos,
                              (uint64_t)(5 * NSEC_PER_SEC));
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(self.timer, ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (strongSelf && !strongSelf.stopped) [strongSelf pruneOnQueue];
    });
    dispatch_resume(self.timer);
  });
}

- (void)stop {
  dispatch_sync(self.queue, ^{
    self.stopped = YES;
    if (self.timer) {
      dispatch_source_cancel(self.timer);
      self.timer = nil;
    }
  });
}

- (void)pruneNow {
  dispatch_async(self.queue, ^{ [self pruneOnQueue]; });
}

- (void)pruneOnQueue {
  if (self.stopped || self.retentionRevisions == 0) return;
  [self.spaceStore pruneAllOplogsKeepingRevisions:self.retentionRevisions error:nil];
}

@end
