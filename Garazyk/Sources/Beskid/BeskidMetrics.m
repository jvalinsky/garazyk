// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Beskid/BeskidMetrics.h"

static const NSUInteger kMaxUpstreamHosts = 32;

@interface GZBeskidMetrics () {
@package
    dispatch_queue_t _queue;
    // record cache
    int64_t _recordHits, _recordMisses, _recordExpiredReads, _recordWrites, _recordDeletes;
    // identity cache
    int64_t _identityHits, _identityMisses, _identityExpiredReads, _identityWrites;
    // rate limiting
    int64_t _rateLimitRejects;
    // upstream (aggregate)
    int64_t _upstreamRequests, _upstreamSuccesses, _upstreamFailures, _upstreamTotalLatencyMs;
    // entry gauges
    int64_t _recordEntries, _identityEntries;
    // expiry bounding
    int64_t _recordMinExpiryAt, _identityMinExpiryAt;
    // uptime
    CFAbsoluteTime _startTime;
    // per-host upstream
    NSMutableArray<NSString *> *_upstreamHostKeys;
    NSMutableDictionary<NSString *, NSMutableDictionary *> *_upstreamHosts;
}
@end

@implementation GZBeskidMetrics

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("blue.microcosm.beskid.metrics", DISPATCH_QUEUE_SERIAL);
        _startTime = CFAbsoluteTimeGetCurrent();
        _upstreamHostKeys = [NSMutableArray array];
        _upstreamHosts = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark - Record cache

- (void)recordRecordHit {
    dispatch_sync(_queue, ^{ ++_recordHits; });
}
- (void)recordRecordMiss {
    dispatch_sync(_queue, ^{ ++_recordMisses; });
}
- (void)recordRecordExpiredRead {
    dispatch_sync(_queue, ^{
        ++self->_recordExpiredReads;
        if (self->_recordEntries > 0) self->_recordEntries--;
    });
}
- (void)recordRecordWriteWithExpiresAt:(int64_t)expiresAt {
    dispatch_sync(_queue, ^{
        ++self->_recordWrites;
        ++self->_recordEntries;
        if (self->_recordMinExpiryAt == 0 || expiresAt < self->_recordMinExpiryAt) {
            self->_recordMinExpiryAt = expiresAt;
        }
    });
}
- (void)recordRecordDelete {
    dispatch_sync(_queue, ^{
        ++self->_recordDeletes;
        if (self->_recordEntries > 0) self->_recordEntries--;
    });
}

#pragma mark - Identity cache

- (void)recordIdentityHit {
    dispatch_sync(_queue, ^{ ++self->_identityHits; });
}
- (void)recordIdentityMiss {
    dispatch_sync(_queue, ^{ ++self->_identityMisses; });
}
- (void)recordIdentityExpiredRead {
    dispatch_sync(_queue, ^{
        ++self->_identityExpiredReads;
        if (self->_identityEntries > 0) self->_identityEntries--;
    });
}
- (void)recordIdentityWriteWithExpiresAt:(int64_t)expiresAt {
    dispatch_sync(_queue, ^{
        ++self->_identityWrites;
        ++self->_identityEntries;
        if (self->_identityMinExpiryAt == 0 || expiresAt < self->_identityMinExpiryAt) {
            self->_identityMinExpiryAt = expiresAt;
        }
    });
}

#pragma mark - Rate limiting

- (void)recordRateLimitReject {
    dispatch_sync(_queue, ^{ ++_rateLimitRejects; });
}

#pragma mark - Upstream

- (void)recordUpstreamRequestToHost:(NSString *)host {
    NSString *key = host.lowercaseString;
    dispatch_sync(_queue, ^{
        ++self->_upstreamRequests;
        NSMutableDictionary *entry = self->_upstreamHosts[key];
        if (!entry) {
            // bounded: when full, evict the oldest-inserted host
            while (self->_upstreamHostKeys.count >= kMaxUpstreamHosts) {
                NSString *oldest = self->_upstreamHostKeys.firstObject;
                [self->_upstreamHostKeys removeObjectAtIndex:0];
                [self->_upstreamHosts removeObjectForKey:oldest];
            }
            [self->_upstreamHostKeys addObject:key];
            entry = [NSMutableDictionary dictionaryWithDictionary:@{
                @"host": host,
                @"requests": @0, @"successes": @0, @"failures": @0,
                @"totalLatencyMs": @0, @"lastSuccessAt": [NSNull null],
            }];
            self->_upstreamHosts[key] = entry;
        }
        int64_t req = [entry[@"requests"] longLongValue] + 1;
        entry[@"requests"] = @(req);
    });
}
- (void)recordUpstreamSuccessToHost:(NSString *)host latencyMillis:(int64_t)latencyMs {
    NSString *key = host.lowercaseString;
    dispatch_sync(_queue, ^{
        ++self->_upstreamSuccesses;
        self->_upstreamTotalLatencyMs += latencyMs;
        NSMutableDictionary *entry = self->_upstreamHosts[key];
        if (entry) {
            int64_t s = [entry[@"successes"] longLongValue] + 1;
            int64_t t = [entry[@"totalLatencyMs"] longLongValue] + latencyMs;
            entry[@"successes"] = @(s);
            entry[@"totalLatencyMs"] = @(t);
            entry[@"lastSuccessAt"] = [NSISO8601DateFormatter.new stringFromDate:NSDate.date];
        }
    });
}
- (void)recordUpstreamFailureToHost:(NSString *)host {
    NSString *key = host.lowercaseString;
    dispatch_sync(_queue, ^{
        ++self->_upstreamFailures;
        NSMutableDictionary *entry = self->_upstreamHosts[key];
        if (entry) {
            int64_t f = [entry[@"failures"] longLongValue] + 1;
            entry[@"failures"] = @(f);
        }
    });
}

#pragma mark - Gauges

- (void)seedEntryGaugesWithRecordCount:(NSUInteger)recordCount identityCount:(NSUInteger)identityCount {
    dispatch_sync(_queue, ^{
        self->_recordEntries = (int64_t)recordCount;
        self->_identityEntries = (int64_t)identityCount;
    });
}

#pragma mark - Snapshot

static double hitRatio(int64_t hits, int64_t misses, int64_t expired) {
    int64_t total = hits + misses + expired;
    return total > 0 ? (double)hits / (double)total : 0.0;
}

static NSDictionary *familySnapshot(NSString *name, int64_t entries,
                                     int64_t hits, int64_t misses, int64_t expired,
                                     int64_t writes, int64_t deletes,
                                     int64_t minExpiry) {
    double ratio = hitRatio(hits, misses, expired);
    NSNumber *soonest = minExpiry > 0 ? @(minExpiry) : [NSNull null];
    return @{
        @"family": name,
        @"entries": @(entries), @"hits": @(hits), @"misses": @(misses),
        @"expired": @(expired), @"writes": @(writes), @"deletes": @(deletes),
        @"hitRatio": @(ratio), @"soonestExpiry": soonest,
    };
}

- (NSDictionary<NSString *, id> *)snapshotDictionary {
    __block NSDictionary *result = nil;
    dispatch_sync(_queue, ^{
        int64_t uptime = (int64_t)(CFAbsoluteTimeGetCurrent() - self->_startTime);

        NSDictionary *recordFam = familySnapshot(@"records",
            self->_recordEntries, self->_recordHits, self->_recordMisses,
            self->_recordExpiredReads, self->_recordWrites, self->_recordDeletes,
            self->_recordMinExpiryAt);
        NSDictionary *identityFam = familySnapshot(@"identities",
            self->_identityEntries, self->_identityHits, self->_identityMisses,
            self->_identityExpiredReads, self->_identityWrites, 0, // no identity deletes
            self->_identityMinExpiryAt);

        int64_t overallEntries = self->_recordEntries + self->_identityEntries;
        int64_t overallHits = self->_recordHits + self->_identityHits;
        int64_t overallMisses = self->_recordMisses + self->_identityMisses;
        int64_t overallExpired = self->_recordExpiredReads + self->_identityExpiredReads;
        int64_t overallWrites = self->_recordWrites + self->_identityWrites;
        int64_t overallDeletes = self->_recordDeletes;
        NSDictionary *overallFam = familySnapshot(@"overall",
            overallEntries, overallHits, overallMisses, overallExpired,
            overallWrites, overallDeletes, 0);

        NSMutableArray *upstreams = [NSMutableArray arrayWithCapacity:self->_upstreamHostKeys.count];
        for (NSString *key in self->_upstreamHostKeys) {
            NSDictionary *entry = self->_upstreamHosts[key];
            int64_t req = [entry[@"requests"] longLongValue];
            int64_t suc = [entry[@"successes"] longLongValue];
            int64_t tLat = [entry[@"totalLatencyMs"] longLongValue];
            [upstreams addObject:@{
                @"host": entry[@"host"],
                @"requests": @(req),
                @"successes": @(suc),
                @"failures": entry[@"failures"],
                @"averageLatencyMilliseconds": suc > 0 ? @(tLat / suc) : [NSNull null],
                @"lastSuccessAt": entry[@"lastSuccessAt"],
            }];
        }

        result = @{
            @"uptimeSeconds": @(uptime),
            @"record": recordFam,
            @"identity": identityFam,
            @"overall": overallFam,
            @"upstreams": upstreams,
            @"rateLimitRejects": @(self->_rateLimitRejects),
        };
    });
    return result;
}

@end
