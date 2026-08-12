// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/Packs/JelczAdminSnapshot.h"

/// Known video job state values (server-side enum strings).
static NSSet<NSString *> *sKnownStates(void) {
    static NSSet<NSString *> *states;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        states = [NSSet setWithArray:@[
            @"JOB_STATE_PENDING",
            @"JOB_STATE_PROCESSING",
            @"JOB_STATE_TRANSCODING",
            @"JOB_STATE_GENERATING_THUMBNAIL",
            @"JOB_STATE_COMPLETED",
            @"JOB_STATE_FAILED",
        ]];
    });
    return states;
}

/// Allowlisted keys for job-detail rendering. Everything else is redacted.
static NSSet<NSString *> *sJobDetailAllowlist(void) {
    static NSSet<NSString *> *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = [NSSet setWithArray:@[
            @"jobId", @"did", @"blobCid", @"state", @"progress",
            @"createdAt", @"updatedAt", @"width", @"height",
            @"duration", @"retryCount", @"stage", @"errorCategory",
            @"mimeType", @"fileSize",
        ]];
    });
    return keys;
}

/// Sensitive keys that must never appear in any rendered output.
static NSSet<NSString *> *sSensitiveKeys(void) {
    static NSSet<NSString *> *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = [NSSet setWithArray:@[
            @"service_auth_token", @"serviceAuthToken",
            @"pdsUrl", @"pdsAdminToken", @"pdsPassword",
            @"rawPath", @"outputPath", @"tempPath",
        ]];
    });
    return keys;
}

@implementation JelczAdminSnapshot {
    NSDictionary *_snapshot;
}

- (instancetype)initWithHealth:(NSDictionary *)health
                          jobs:(NSArray<NSDictionary *> *)jobs
                        quotas:(NSDictionary *)quotas {
    self = [super init];
    if (self) {
        [self buildSnapshotWithHealth:health ?: @{} jobs:jobs ?: @[] quotas:quotas ?: @{}];
    }
    return self;
}

- (void)buildSnapshotWithHealth:(NSDictionary *)health
                           jobs:(NSArray<NSDictionary *> *)jobs
                         quotas:(NSDictionary *)quotas {
    // --- Health ---
    NSString *status = [health[@"status"] isKindOfClass:[NSString class]] ? health[@"status"] : @"unknown";
    BOOL isReachable = [status isEqualToString:@"online"] || [status isEqualToString:@"ok"];
    _healthStatus = isReachable ? @"healthy" : @"unreachable";

    // --- Queue: per-state counts ---
    NSMutableDictionary *counts = [NSMutableDictionary dictionary];
    NSDate *oldestDate = nil;
    NSUInteger completed24h = 0, failed24h = 0;
    NSDate *now = [NSDate date];
    NSTimeInterval twentyFourHours = 24 * 60 * 60;

    for (NSDictionary *job in jobs) {
        NSString *state = [job[@"state"] isKindOfClass:[NSString class]] ? job[@"state"] : @"unknown";
        if (![sKnownStates() containsObject:state]) {
            state = @"unknown";
        }

        NSNumber *current = counts[state] ?: @0;
        counts[state] = @(current.integerValue + 1);

        // Track oldest job age
        NSString *created = [job[@"createdAt"] isKindOfClass:[NSString class]] ? job[@"createdAt"] : nil;
        if (created.length > 0) {
            // Try ISO 8601 parse; fall back to nil
            NSISO8601DateFormatter *fmt = [[NSISO8601DateFormatter alloc] init];
            NSDate *date = [fmt dateFromString:created];
            if (date && (!oldestDate || [date compare:oldestDate] == NSOrderedAscending)) {
                oldestDate = date;
            }
        }

        // Throughput (last 24h)
        if ([state isEqualToString:@"JOB_STATE_COMPLETED"] || [state isEqualToString:@"JOB_STATE_FAILED"]) {
            NSString *updated = [job[@"updatedAt"] isKindOfClass:[NSString class]] ? job[@"updatedAt"] : created;
            if (updated.length > 0) {
                NSISO8601DateFormatter *fmt = [[NSISO8601DateFormatter alloc] init];
                NSDate *date = [fmt dateFromString:updated];
                if (date && [now timeIntervalSinceDate:date] <= twentyFourHours) {
                    if ([state isEqualToString:@"JOB_STATE_COMPLETED"]) completed24h++;
                    else failed24h++;
                }
            }
        }
    }

    // Fill in zero for known states not present in the job list
    for (NSString *state in sKnownStates()) {
        if (!counts[state]) counts[state] = @0;
    }

    _totalJobs = jobs.count;
    _countsByState = [counts copy];

    // Oldest job age in seconds
    NSTimeInterval oldestAge = oldestDate ? [now timeIntervalSinceDate:oldestDate] : 0;

    // --- Worker (derived from health + queue) ---
    NSDictionary *worker = @{
        @"active": @(isReachable),
        @"activeJobs": counts[@"JOB_STATE_PROCESSING"] ?: @0,
        @"pendingJobs": counts[@"JOB_STATE_PENDING"] ?: @0,
        @"maxConcurrency": health[@"maxConcurrentJobs"] ?: @(1),
    };

    // --- Throughput ---
    NSDictionary *throughput = @{
        @"completed24h": @(completed24h),
        @"failed24h": @(failed24h),
    };

    // --- Storage (from health) ---
    NSString *storageBackend = [health[@"storageBackend"] isKindOfClass:[NSString class]]
        ? health[@"storageBackend"] : @"disk";
    NSDictionary *storage = @{
        @"tempBytes": health[@"tempStorageBytes"] ?: @0,
        @"outputBytes": health[@"outputStorageBytes"] ?: @0,
        @"backend": storageBackend,
    };

    // --- Config ---
    NSMutableDictionary *config = [NSMutableDictionary dictionary];
    NSDictionary *limits = [quotas[@"limits"] isKindOfClass:[NSDictionary class]]
        ? quotas[@"limits"] : quotas;
    if (limits[@"maxUploadSize"]) config[@"maxUploadSize"] = limits[@"maxUploadSize"];
    if (limits[@"maxDuration"]) config[@"maxDuration"] = limits[@"maxDuration"];
    if (limits[@"maxQuality"]) config[@"maxQuality"] = limits[@"maxQuality"];
    config[@"hlsVariants"] = health[@"hlsVariants"] ?: @(3);

    // --- PDS upload health ---
    NSString *pdsHealth = @"unknown";
    if (isReachable) {
        NSUInteger failures = [counts[@"JOB_STATE_FAILED"] unsignedIntegerValue];
        NSUInteger completed = [counts[@"JOB_STATE_COMPLETED"] unsignedIntegerValue];
        NSUInteger total = completed + failures;
        if (total > 0 && (double)failures / (double)total > 0.5) {
            pdsHealth = @"degraded";
        } else if (isReachable) {
            pdsHealth = @"healthy";
        }
    }

    _snapshot = @{
        @"health": _healthStatus,
        @"worker": worker,
        @"queue": @{
            @"countsByState": _countsByState,
            @"depth": @(_totalJobs),
            @"oldestAgeSeconds": @(oldestAge),
        },
        @"throughput": throughput,
        @"storage": storage,
        @"config": config,
        @"pdsUploadHealth": pdsHealth,
    };
}

+ (NSSet<NSString *> *)jobDetailAllowlist {
    return sJobDetailAllowlist();
}

+ (NSSet<NSString *> *)sensitiveKeys {
    return sSensitiveKeys();
}

- (NSDictionary *)snapshot {
    return _snapshot;
}

@end
