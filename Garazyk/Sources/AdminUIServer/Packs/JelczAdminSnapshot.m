// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/Packs/JelczAdminSnapshot.h"
#import "Video/JelczDatabase.h"

/// Maps persisted job state strings to admin UI state keys.
static NSDictionary<NSString *, NSString *> *sDbStateToUIState(void) {
    static NSDictionary<NSString *, NSString *> *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"PENDING": @"JOB_STATE_PENDING",
            @"PROCESSING": @"JOB_STATE_PROCESSING",
            @"TRANSCODING": @"JOB_STATE_TRANSCODING",
            @"GENERATING_THUMBNAIL": @"JOB_STATE_GENERATING_THUMBNAIL",
            @"COMPLETED": @"JOB_STATE_COMPLETED",
            @"FAILED": @"JOB_STATE_FAILED",
            @"JOB_STATE_PENDING": @"JOB_STATE_PENDING",
            @"JOB_STATE_PROCESSING": @"JOB_STATE_PROCESSING",
            @"JOB_STATE_TRANSCODING": @"JOB_STATE_TRANSCODING",
            @"JOB_STATE_GENERATING_THUMBNAIL": @"JOB_STATE_GENERATING_THUMBNAIL",
            @"JOB_STATE_COMPLETED": @"JOB_STATE_COMPLETED",
            @"JOB_STATE_FAILED": @"JOB_STATE_FAILED",
        };
    });
    return map;
}

static NSArray<NSString *> *sPersistedStates(void) {
    return @[@"PENDING", @"PROCESSING", @"COMPLETED", @"FAILED"];
}

static NSString *sTimestampFromJob(NSDictionary *job, NSString *camelKey) {
    id value = job[camelKey];
    if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
        return value;
    }
    if ([camelKey isEqualToString:@"createdAt"]) {
        value = job[@"created_at"];
    } else if ([camelKey isEqualToString:@"updatedAt"]) {
        value = job[@"updated_at"];
    }
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static NSArray<NSDictionary *> *sInvokeJobList(id jobStore, SEL selector, NSString *state) {
    if (![jobStore respondsToSelector:selector]) {
        return @[];
    }
    NSMethodSignature *sig = [jobStore methodSignatureForSelector:selector];
    if (!sig) {
        return @[];
    }
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setSelector:selector];
    [inv setTarget:jobStore];
    NSUInteger limit = 500;
    NSUInteger offset = 0;
    NSError *error = nil;
    [inv setArgument:&state atIndex:2];
    [inv setArgument:&limit atIndex:3];
    [inv setArgument:&offset atIndex:4];
    [inv setArgument:&error atIndex:5];
    [inv invoke];
    __unsafe_unretained NSArray *jobs = nil;
    [inv getReturnValue:&jobs];
    return jobs ?: @[];
}

static NSArray<NSDictionary *> *sJobsForPersistedState(id jobStore, NSString *dbState) {
    if (!jobStore) return @[];

    SEL mediaListSel = NSSelectorFromString(@"listJobsWithState:limit:offset:error:");
    if ([jobStore respondsToSelector:mediaListSel]) {
        return sInvokeJobList(jobStore, mediaListSel, dbState);
    }

    NSString *uiState = sDbStateToUIState()[dbState] ?: dbState;
    SEL legacyListSel = NSSelectorFromString(@"listVideoJobsWithState:limit:offset:error:");
    return sInvokeJobList(jobStore, legacyListSel, uiState);
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
            @"manifestBlobCid", @"processedBlobCid", @"thumbnailBlobCid",
            @"product", @"hasProofHint",
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
            @"caObjectStoreDirectory", @"rootDirectory",
            @"s3AccessKey", @"s3SecretKey", @"s3SecretAccessKey",
        ]];
    });
    return keys;
}

/// Maps free-form job errors to short operator categories (never raw paths).
static NSString *sSanitizeErrorCategory(NSString *errorCode, NSString *errorMessage) {
    if (errorCode.length > 0) {
        return errorCode;
    }
    if (errorMessage.length == 0) return nil;
    NSString *lower = errorMessage.lowercaseString;
    if ([lower containsString:@"pds"] || [lower containsString:@"upload"]) return @"pds-upload";
    if ([lower containsString:@"ffmpeg"] || [lower containsString:@"transcod"]) return @"transcode";
    if ([lower containsString:@"thumbnail"]) return @"thumbnail";
    if ([lower containsString:@"manifest"] || [lower containsString:@"masl"]) return @"ca-manifest";
    if ([lower containsString:@"muxl"]) return @"muxl";
    if ([lower containsString:@"disk"] || [lower containsString:@"space"] || [lower containsString:@"enospc"]) return @"storage";
    if ([lower containsString:@"timeout"]) return @"timeout";
    if ([lower containsString:@"denied"] || [lower containsString:@"auth"]) return @"auth";
    // Truncate and strip path-looking tokens.
    NSMutableString *safe = [NSMutableString string];
    NSArray *parts = [errorMessage componentsSeparatedByCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    for (NSString *part in parts) {
        if ([part containsString:@"/"] || [part containsString:@"\\"]) continue;
        if (safe.length > 0) [safe appendString:@" "];
        [safe appendString:part];
        if (safe.length >= 72) break;
    }
    if (safe.length == 0) return @"failed";
    if (safe.length > 72) return [[safe substringToIndex:72] stringByAppendingString:@"…"];
    return [safe copy];
}

static NSString *sProductForRow(NSDictionary *row, NSDictionary *metadata) {
    NSString *manifest = row[@"manifest_blob_cid"] ?: row[@"manifestBlobCid"];
    if ([manifest isKindOfClass:[NSString class]] && manifest.length > 0) {
        return @"CA VOD";
    }
    if ([metadata[@"vodManifestResourceCIDs"] isKindOfClass:[NSDictionary class]] ||
        [metadata[@"manifestBlobCid"] isKindOfClass:[NSString class]]) {
        return @"CA VOD";
    }
    if ([metadata[@"muxlPresentation"] boolValue] || metadata[@"muxlPackagePath"]) {
        return @"MUXL";
    }
    NSString *state = [row[@"state"] isKindOfClass:[NSString class]] ? row[@"state"] : @"";
    if ([state containsString:@"COMPLETED"] || [state isEqualToString:@"COMPLETED"]) {
        return @"HLS";
    }
    return @"—";
}

@implementation GZJelczAdminSnapshot {
    NSDictionary *_snapshot;
}

+ (nullable NSDictionary *)jobDTOForId:(NSString *)jobId jobStore:(id)jobStore {
    if (jobId.length == 0 || !jobStore) return nil;
    SEL sel = NSSelectorFromString(@"getJobById:error:");
    if (![jobStore respondsToSelector:sel]) {
        sel = NSSelectorFromString(@"getVideoJobById:error:");
    }
    if (![jobStore respondsToSelector:sel]) return nil;
    NSDictionary *row = nil;
    NSMethodSignature *sig = [jobStore methodSignatureForSelector:sel];
    if (!sig) return nil;
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setSelector:sel];
    [inv setTarget:jobStore];
    NSError *error = nil;
    [inv setArgument:&jobId atIndex:2];
    [inv setArgument:&error atIndex:3];
    [inv invoke];
    __unsafe_unretained NSDictionary *result = nil;
    [inv getReturnValue:&result];
    row = result;
    if (!row) return nil;
    return [self allowlistedJobDTOFromDatabaseRow:row];
}

+ (NSArray<NSDictionary *> *)recentJobDTOsFromStore:(id)jobStore
                                              limit:(NSUInteger)limit
                                        stateFilter:(NSString *)stateFilter {
    if (!jobStore || limit == 0) return @[];
    NSString *dbFilter = nil;
    if (stateFilter.length > 0) {
        NSDictionary *uiToDb = @{
            @"JOB_STATE_PENDING": @"PENDING",
            @"JOB_STATE_PROCESSING": @"PROCESSING",
            @"JOB_STATE_COMPLETED": @"COMPLETED",
            @"JOB_STATE_FAILED": @"FAILED",
        };
        dbFilter = uiToDb[stateFilter] ?: stateFilter;
    }
    NSArray *rows = sInvokeJobList(jobStore,
                                   NSSelectorFromString(@"listJobsWithState:limit:offset:error:"),
                                   dbFilter ?: @"");
    if (rows.count == 0 && dbFilter.length > 0) {
        rows = sInvokeJobList(jobStore,
                              NSSelectorFromString(@"listVideoJobsWithState:limit:offset:error:"),
                              stateFilter);
    } else if (rows.count == 0 && dbFilter.length == 0) {
        rows = sInvokeJobList(jobStore,
                              NSSelectorFromString(@"listJobsWithState:limit:offset:error:"),
                              @"");
    }
    NSMutableArray *dtos = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSDictionary *row in rows) {
        [dtos addObject:[self allowlistedJobDTOFromDatabaseRow:row]];
        if (dtos.count >= limit) break;
    }
    return dtos;
}

+ (NSDictionary *)allowlistedJobDTOFromDatabaseRow:(NSDictionary *)row {
    if (!row) return @{};
    NSMutableDictionary *dto = [NSMutableDictionary dictionary];
    dto[@"jobId"] = row[@"job_id"] ?: row[@"jobId"] ?: @"";
    dto[@"did"] = row[@"did"] ?: @"";
    if (row[@"blob_cid"]) dto[@"blobCid"] = row[@"blob_cid"];
    if (row[@"blobCid"]) dto[@"blobCid"] = row[@"blobCid"];

    NSString *state = [row[@"state"] isKindOfClass:[NSString class]] ? row[@"state"] : @"";
    dto[@"state"] = sDbStateToUIState()[state] ?: state;
    if (row[@"progress"]) dto[@"progress"] = row[@"progress"];
    if (sTimestampFromJob(row, @"createdAt")) dto[@"createdAt"] = sTimestampFromJob(row, @"createdAt");
    if (sTimestampFromJob(row, @"updatedAt")) dto[@"updatedAt"] = sTimestampFromJob(row, @"updatedAt");
    if (row[@"mime_type"]) dto[@"mimeType"] = row[@"mime_type"];
    if (row[@"file_size"]) dto[@"fileSize"] = row[@"file_size"];
    if (row[@"retry_count"]) dto[@"retryCount"] = row[@"retry_count"];

    NSString *errorCode = [row[@"error_code"] isKindOfClass:[NSString class]] ? row[@"error_code"] : nil;
    NSString *errorMessage = [row[@"error_message"] isKindOfClass:[NSString class]] ? row[@"error_message"] : nil;
    NSString *category = sSanitizeErrorCategory(errorCode, errorMessage);
    if (category.length > 0) dto[@"errorCategory"] = category;

    NSString *message = [row[@"message"] isKindOfClass:[NSString class]] ? row[@"message"] : nil;
    if (message.length > 0) {
        // Stage labels only — never absolute paths.
        if (![message containsString:@"/"] && ![message containsString:@"\\"]) {
            dto[@"stage"] = message.length > 64 ? [[message substringToIndex:64] stringByAppendingString:@"…"] : message;
        } else {
            dto[@"stage"] = @"processing";
        }
    }

    NSDictionary *metadata = nil;
    NSString *resultsJson = [row[@"results_json"] isKindOfClass:[NSString class]] ? row[@"results_json"] : nil;
    if (resultsJson.length > 0) {
        NSData *data = [resultsJson dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *results = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        metadata = [results[@"metadata"] isKindOfClass:[NSDictionary class]] ? results[@"metadata"] : nil;
        if (metadata[@"width"]) dto[@"width"] = metadata[@"width"];
        if (metadata[@"height"]) dto[@"height"] = metadata[@"height"];
        if (metadata[@"duration"]) dto[@"duration"] = metadata[@"duration"];
    }

    if (row[@"width"]) dto[@"width"] = row[@"width"];
    if (row[@"height"]) dto[@"height"] = row[@"height"];
    if (row[@"duration_seconds"]) dto[@"duration"] = row[@"duration_seconds"];

    NSString *manifest = row[@"manifest_blob_cid"] ?: row[@"manifestBlobCid"] ?: metadata[@"manifestBlobCid"];
    if ([manifest isKindOfClass:[NSString class]] && manifest.length > 0) {
        dto[@"manifestBlobCid"] = manifest;
    }
    NSString *processed = row[@"processed_blob_cid"] ?: row[@"processedBlobCid"];
    if ([processed isKindOfClass:[NSString class]] && processed.length > 0) {
        dto[@"processedBlobCid"] = processed;
    }
    NSString *thumb = row[@"thumbnail_blob_cid"] ?: row[@"thumbnailBlobCid"];
    if ([thumb isKindOfClass:[NSString class]] && thumb.length > 0) {
        dto[@"thumbnailBlobCid"] = thumb;
    }
    dto[@"product"] = sProductForRow(row, metadata ?: @{});
    if ([metadata[@"vodManifestResourceCIDs"] isKindOfClass:[NSDictionary class]]) {
        dto[@"hasProofHint"] = @"yes";
    }

    return dto;
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

- (instancetype)initWithWorker:(id)worker
                      jobStore:(id)jobStore
                        config:(NSDictionary *)config
                  uptimeSeconds:(NSTimeInterval)uptimeSeconds {
    self = [super init];
    if (self) {
        [self buildEmbeddedSnapshotWithWorker:worker jobStore:jobStore config:config ?: @{} uptimeSeconds:uptimeSeconds];
    }
    return self;
}

static id sSafeValueForKey(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *ex) {
        return nil;
    }
}

/// Build a snapshot from direct worker + database access (embedded mode).
- (void)buildEmbeddedSnapshotWithWorker:(id)worker
                               jobStore:(id)jobStore
                                 config:(NSDictionary *)config
                           uptimeSeconds:(NSTimeInterval)uptimeSeconds {
    // Worker state via safe KVC (MediaWorker and VideoWorker differ).
    id enabledValue = sSafeValueForKey(worker, @"enabled");
    BOOL enabled = enabledValue ? [enabledValue boolValue] : (worker != nil);
    NSInteger maxConcurrency = [sSafeValueForKey(worker, @"maxConcurrentJobs") integerValue];
    if (maxConcurrency <= 0) maxConcurrency = 1;

    _healthStatus = enabled ? @"healthy" : @"degraded";

    NSMutableDictionary *counts = [NSMutableDictionary dictionary];
    NSDate *oldestDate = nil;
    NSUInteger completed24h = 0, failed24h = 0;
    NSDate *now = [NSDate date];
    NSTimeInterval twentyFourHours = 24 * 60 * 60;
    NSUInteger total = 0;

    // Prefer cheap GROUP BY counts when the store offers them.
    SEL countSel = NSSelectorFromString(@"jobCountsByStateWithError:");
    NSDictionary<NSString *, NSNumber *> *dbCounts = nil;
    if (jobStore && [jobStore respondsToSelector:countSel]) {
        NSMethodSignature *sig = [jobStore methodSignatureForSelector:countSel];
        if (sig) {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setSelector:countSel];
            [inv setTarget:jobStore];
            NSError *error = nil;
            [inv setArgument:&error atIndex:2];
            [inv invoke];
            __unsafe_unretained NSDictionary *result = nil;
            [inv getReturnValue:&result];
            dbCounts = result;
        }
    }

    if (dbCounts.count > 0) {
        for (NSString *dbState in dbCounts) {
            NSString *uiState = sDbStateToUIState()[dbState] ?: dbState;
            NSUInteger n = [dbCounts[dbState] unsignedIntegerValue];
            counts[uiState] = @([counts[uiState] unsignedIntegerValue] + n);
            total += n;
        }
        // Oldest age / 24h throughput still need a bounded scan of active + recent terminal jobs.
        for (NSString *dbState in @[@"PENDING", @"PROCESSING", @"FAILED", @"COMPLETED"]) {
            NSArray *jobs = sJobsForPersistedState(jobStore, dbState);
            NSUInteger cap = [dbState isEqualToString:@"PENDING"] || [dbState isEqualToString:@"PROCESSING"] ? 50 : 25;
            NSUInteger i = 0;
            for (NSDictionary *job in jobs) {
                if (i++ >= cap) break;
                NSString *created = sTimestampFromJob(job, @"createdAt");
                if (created.length > 0) {
                    NSISO8601DateFormatter *fmt = [[NSISO8601DateFormatter alloc] init];
                    NSDate *date = [fmt dateFromString:created];
                    if (date && (!oldestDate || [date compare:oldestDate] == NSOrderedAscending)) {
                        oldestDate = date;
                    }
                }
                NSString *uiState = sDbStateToUIState()[dbState] ?: dbState;
                if ([uiState isEqualToString:@"JOB_STATE_COMPLETED"] || [uiState isEqualToString:@"JOB_STATE_FAILED"]) {
                    NSString *updated = sTimestampFromJob(job, @"updatedAt") ?: created;
                    if (updated.length > 0) {
                        NSISO8601DateFormatter *fmt = [[NSISO8601DateFormatter alloc] init];
                        NSDate *date = [fmt dateFromString:updated];
                        if (date && [now timeIntervalSinceDate:date] <= twentyFourHours) {
                            if ([uiState isEqualToString:@"JOB_STATE_COMPLETED"]) completed24h++;
                            else failed24h++;
                        }
                    }
                }
            }
        }
    } else {
        for (NSString *dbState in sPersistedStates()) {
            NSArray *jobs = sJobsForPersistedState(jobStore, dbState);
            NSString *uiState = sDbStateToUIState()[dbState] ?: dbState;
            counts[uiState] = @(jobs.count);
            total += jobs.count;

            for (NSDictionary *job in jobs) {
                NSString *created = sTimestampFromJob(job, @"createdAt");
                if (created.length > 0) {
                    NSISO8601DateFormatter *fmt = [[NSISO8601DateFormatter alloc] init];
                    NSDate *date = [fmt dateFromString:created];
                    if (date && (!oldestDate || [date compare:oldestDate] == NSOrderedAscending)) {
                        oldestDate = date;
                    }
                }
                if ([uiState isEqualToString:@"JOB_STATE_COMPLETED"] || [uiState isEqualToString:@"JOB_STATE_FAILED"]) {
                    NSString *updated = sTimestampFromJob(job, @"updatedAt") ?: created;
                    if (updated.length > 0) {
                        NSISO8601DateFormatter *fmt = [[NSISO8601DateFormatter alloc] init];
                        NSDate *date = [fmt dateFromString:updated];
                        if (date && [now timeIntervalSinceDate:date] <= twentyFourHours) {
                            if ([uiState isEqualToString:@"JOB_STATE_COMPLETED"]) completed24h++;
                            else failed24h++;
                        }
                    }
                }
            }
        }
    }

    for (NSString *uiState in sDbStateToUIState().allValues) {
        if (!counts[uiState]) counts[uiState] = @0;
    }

    _totalJobs = total;
    _countsByState = [counts copy];
    NSTimeInterval oldestAge = oldestDate ? [now timeIntervalSinceDate:oldestDate] : 0;

    // Worker
    NSDictionary *workerDict = @{
        @"active": @(enabled),
        @"activeJobs": counts[@"JOB_STATE_PROCESSING"] ?: @0,
        @"pendingJobs": counts[@"JOB_STATE_PENDING"] ?: @0,
        @"maxConcurrency": @(maxConcurrency),
    };

    // Throughput
    NSDictionary *throughput = @{
        @"completed24h": @(completed24h),
        @"failed24h": @(failed24h),
    };

    // Storage (from config) — never include filesystem paths.
    NSString *backend = config[@"storageBackend"] ?: @"disk";
    NSDictionary *storage = @{
        @"tempBytes": config[@"tempStorageBytes"] ?: @0,
        @"outputBytes": config[@"outputStorageBytes"] ?: @0,
        @"backend": backend,
    };

    // Config
    NSMutableDictionary *cfg = [NSMutableDictionary dictionary];
    if (config[@"maxUploadSize"]) cfg[@"maxUploadSize"] = config[@"maxUploadSize"];
    if (config[@"maxDuration"]) cfg[@"maxDuration"] = config[@"maxDuration"];
    cfg[@"hlsVariants"] = config[@"hlsVariants"] ?: @(3);

    // Distribution posture (ADR 0036 / WS10 MUXL) — flags only, no secrets/paths.
    BOOL caManifest = NO;
    BOOL muxl = NO;
    BOOL caStoreConfigured = NO;
    BOOL sweepEnabled = NO;
    BOOL mirrorFetch = [config[@"enableCAMirrorFetch"] boolValue];
    NSUInteger mirrorProviderCount = [config[@"caMirrorProviderCount"] unsignedIntegerValue];
    NSString *watchMode = @"filesystem-hls";
    caManifest = [sSafeValueForKey(worker, @"enableContentAddressedManifest") boolValue];
    muxl = [sSafeValueForKey(worker, @"enableMUXLPresentation") boolValue];
    caStoreConfigured = sSafeValueForKey(worker, @"caObjectStore") != nil;
    id lifecycle = sSafeValueForKey(worker, @"caObjectLifecycle");
    if (lifecycle) {
        sweepEnabled = [sSafeValueForKey(lifecycle, @"sweepEnabled") boolValue];
    }
    if ([config[@"enableContentAddressedManifest"] respondsToSelector:@selector(boolValue)]) {
        caManifest = caManifest || [config[@"enableContentAddressedManifest"] boolValue];
    }
    if ([config[@"enableMUXLPresentation"] respondsToSelector:@selector(boolValue)]) {
        muxl = muxl || [config[@"enableMUXLPresentation"] boolValue];
    }
    if ([config[@"caObjectStoreConfigured"] respondsToSelector:@selector(boolValue)]) {
        caStoreConfigured = caStoreConfigured || [config[@"caObjectStoreConfigured"] boolValue];
    }
    if ([config[@"caObjectSweepEnabled"] respondsToSelector:@selector(boolValue)]) {
        sweepEnabled = sweepEnabled || [config[@"caObjectSweepEnabled"] boolValue];
    }
    if (caManifest && caStoreConfigured) {
        watchMode = @"masl-ca";
    }

    NSDictionary *distribution = @{
        @"caManifestEnabled": @(caManifest),
        @"caStoreConfigured": @(caStoreConfigured),
        @"muxlPresentationEnabled": @(muxl),
        @"watchMode": watchMode,
        @"sweepEnabled": @(sweepEnabled),
        @"mirrorFetchEnabled": @(mirrorFetch),
        @"mirrorProviderCount": @(mirrorProviderCount),
        @"summary": caManifest
            ? @"Content-addressed VOD: MASL /watch + optional Bao proofs"
            : @"Classic filesystem HLS /watch (CA manifest off)",
    };

    // PDS upload health (best-effort; anonymous uploads skip PDS)
    NSString *pdsHealth = enabled ? @"healthy" : @"unknown";
    if (enabled) {
        NSUInteger failures = [counts[@"JOB_STATE_FAILED"] unsignedIntegerValue];
        NSUInteger completed = [counts[@"JOB_STATE_COMPLETED"] unsignedIntegerValue];
        NSUInteger finished = completed + failures;
        if (finished > 0 && (double)failures / (double)finished > 0.5) {
            pdsHealth = @"degraded";
        }
    }

    _snapshot = @{
        @"health": _healthStatus,
        @"uptimeSeconds": @(uptimeSeconds),
        @"worker": workerDict,
        @"queue": @{
            @"countsByState": _countsByState,
            @"depth": @(_totalJobs),
            @"oldestAgeSeconds": @(oldestAge),
        },
        @"throughput": throughput,
        @"storage": storage,
        @"config": cfg,
        @"distribution": distribution,
        @"pdsUploadHealth": pdsHealth,
    };
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
        if (![sDbStateToUIState().allValues containsObject:state] && ![state isEqualToString:@"unknown"]) {
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
    for (NSString *uiState in sDbStateToUIState().allValues) {
        if (!counts[uiState]) counts[uiState] = @0;
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
        @"distribution": @{
            @"caManifestEnabled": @NO,
            @"caStoreConfigured": @NO,
            @"muxlPresentationEnabled": @NO,
            @"watchMode": @"unknown",
            @"sweepEnabled": @NO,
            @"mirrorFetchEnabled": @NO,
            @"mirrorProviderCount": @0,
            @"summary": @"Remote snapshot — distribution flags unavailable",
        },
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
