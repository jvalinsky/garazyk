// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Services/PDS/PDSCollectionMembershipPruner.h"

#import "Compat/PDSTypes.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/Pool/DatabasePool.h"
#import "Debug/GZLogger.h"

static const NSTimeInterval kMinimumPruneInterval = 300.0;

@interface PDSCollectionMembershipPruner ()
@property (nonatomic, strong) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, strong) PDSDatabasePool *userDatabasePool;
@property (nonatomic, assign) NSTimeInterval interval;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t queue;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG, nullable) dispatch_source_t timer;
@property (nonatomic, assign) BOOL stopped;
@end

@implementation PDSCollectionMembershipPruner

- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases
                       userDatabasePool:(PDSDatabasePool *)userDatabasePool
                      intervalInSeconds:(NSTimeInterval)interval {
    self = [super init];
    if (!self) return nil;
    _serviceDatabases = serviceDatabases;
    _userDatabasePool = userDatabasePool;
    _interval = MAX(interval, kMinimumPruneInterval);
    _queue = dispatch_queue_create("com.garazyk.pds.collection-membership-prune", DISPATCH_QUEUE_SERIAL);
    _stopped = YES;
    return self;
}

- (void)start {
    dispatch_async(self.queue, ^{
        if (!self.stopped) return;
        self.stopped = NO;
        // Run an initial prune immediately.
        dispatch_async(self.queue, ^{ [self pruneOnQueueIgnoringStopped:NO]; });
        self.timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue);
        uint64_t intervalNanos = (uint64_t)(self.interval * (NSTimeInterval)NSEC_PER_SEC);
        dispatch_source_set_timer(self.timer,
                                  dispatch_time(DISPATCH_TIME_NOW, (int64_t)intervalNanos),
                                  intervalNanos,
                                  (uint64_t)(5 * NSEC_PER_SEC));
        __weak typeof(self) weakSelf = self;
        dispatch_source_set_event_handler(self.timer, ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf && !strongSelf.stopped) [strongSelf pruneOnQueueIgnoringStopped:NO];
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
    dispatch_async(self.queue, ^{ [self pruneOnQueueIgnoringStopped:YES]; });
}

- (void)pruneOnQueueIgnoringStopped:(BOOL)ignoreStopped {
    if (self.stopped && !ignoreStopped) return;
    NSInteger removed = [self.serviceDatabases pruneStaleCollectionMembershipsWithUserDatabasePool:self.userDatabasePool
                                                                                             error:nil];
    if (removed > 0) {
        GZ_LOG_INFO_C(@"ServiceDB", @"Collection membership pruner removed %ld stale entries", (long)removed);
    }
}

@end
