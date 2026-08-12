// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Video/AdminUI/JelczAdminEmbedContext.h"

@implementation GZJelczAdminEmbedContext

- (instancetype)initWithWorker:(id)worker
                      jobStore:(id)jobStore
                        config:(NSDictionary<NSString *, id> *)config
                     startTime:(NSDate *)startTime {
    self = [super init];
    if (self) {
        _worker = worker;
        _jobStore = jobStore;
        _config = [config copy] ?: @{};
        _startTime = startTime ?: [NSDate date];
    }
    return self;
}

- (NSTimeInterval)uptimeSeconds {
    return [[NSDate date] timeIntervalSinceDate:self.startTime];
}

@end
