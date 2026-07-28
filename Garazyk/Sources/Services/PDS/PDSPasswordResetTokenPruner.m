// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Services/PDS/PDSPasswordResetTokenPruner.h"

#import "Compat/PDSTypes.h"
#import "Database/Service/ServiceDatabases.h"
#import "Debug/GZLogger.h"

static const NSTimeInterval kMinimumPruneInterval = 300.0;

@interface PDSPasswordResetTokenPruner ()
@property (nonatomic, strong) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, assign) NSTimeInterval interval;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t queue;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG, nullable) dispatch_source_t timer;
@property (nonatomic, assign) BOOL stopped;
@end

@implementation PDSPasswordResetTokenPruner

- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases
                       intervalInSeconds:(NSTimeInterval)interval {
    self = [super init];
    if (!self) return nil;
    _serviceDatabases = serviceDatabases;
    _interval = MAX(interval, kMinimumPruneInterval);
    _queue = dispatch_queue_create("com.garazyk.pds.password-reset-token-prune", DISPATCH_QUEUE_SERIAL);
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

    NSDate *cutoff = [NSDate date];
    NSError *passwordError = nil;
    NSInteger passwordRemoved =
        [self.serviceDatabases pruneExpiredPasswordResetTokensBefore:cutoff
                                                               error:&passwordError];
    if (passwordRemoved < 0) {
        GZ_LOG_INFO_C(@"ServiceDB", @"Password-reset token pruner failed: %@",
                      passwordError.localizedDescription ?: @"unknown database error");
    } else if (passwordRemoved > 0) {
        GZ_LOG_INFO_C(@"ServiceDB",
                      @"Token pruner removed %ld expired password-reset tokens",
                      (long)passwordRemoved);
    }

    NSError *emailError = nil;
    NSInteger emailRemoved =
        [self.serviceDatabases pruneExpiredEmailConfirmationTokensBefore:cutoff
                                                                   error:&emailError];
    if (emailRemoved < 0) {
        GZ_LOG_INFO_C(@"ServiceDB", @"Email-confirmation token pruner failed: %@",
                      emailError.localizedDescription ?: @"unknown database error");
    } else if (emailRemoved > 0) {
        GZ_LOG_INFO_C(@"ServiceDB",
                      @"Token pruner removed %ld expired email-confirmation tokens",
                      (long)emailRemoved);
    }
}

@end
