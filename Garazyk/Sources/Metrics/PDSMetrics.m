#import "Metrics/PDSMetrics.h"

#ifdef __APPLE__
#import <mach/mach.h>
#else
#include <unistd.h>
#endif

static const double kHistogramBuckets[] = {
    0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0
};
static const NSUInteger kHistogramBucketCount = sizeof(kHistogramBuckets) / sizeof(kHistogramBuckets[0]);

@interface PDSMetrics () {
    dispatch_queue_t _metricsQueue;
    NSTimeInterval _serverStartTime;
    NSInteger _firehoseSubscribers;
    int64_t _firehoseSeq;
    NSInteger _repoCommitsTotal;
    NSInteger _activeAuthSessions;
}
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *httpRequestsByEndpoint;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *httpRequestsByStatus;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *httpRequestsByMethod;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *blobsByMimetype;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary<NSNumber *, NSNumber *> *> *histogramBuckets;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *histogramSums;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *histogramCounts;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *firehoseEventsByKind;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *rateLimitRejectionsByType;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *authFailuresByReason;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *oauthGrantsByType;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *quotaExceededByKind;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *accountBlobBytesByDid;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *accountRepoBytesByDid;
@end

@implementation PDSMetrics

+ (instancetype)sharedMetrics {
    static PDSMetrics *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PDSMetrics alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _metricsQueue = dispatch_queue_create("com.atproto.pds.metrics", DISPATCH_QUEUE_SERIAL);
        _serverStartTime = [[NSDate date] timeIntervalSince1970];
        _httpRequestsByEndpoint = [NSMutableDictionary dictionary];
        _httpRequestsByStatus = [NSMutableDictionary dictionary];
        _httpRequestsByMethod = [NSMutableDictionary dictionary];
        _blobsByMimetype = [NSMutableDictionary dictionary];
        _histogramBuckets = [NSMutableDictionary dictionary];
        _histogramSums = [NSMutableDictionary dictionary];
        _histogramCounts = [NSMutableDictionary dictionary];
        _repositoryCount = 0;
        _blobCount = 0;
        _blobStorageBytes = 0;
        _databaseSizeBytes = 0;
        _activeConnections = 0;
        _firehoseSubscribers = 0;
        _firehoseSeq = 0;
        _repoCommitsTotal = 0;
        _activeAuthSessions = 0;
        _firehoseEventsByKind = [NSMutableDictionary dictionary];
        _rateLimitRejectionsByType = [NSMutableDictionary dictionary];
        _authFailuresByReason = [NSMutableDictionary dictionary];
        _oauthGrantsByType = [NSMutableDictionary dictionary];
        _quotaExceededByKind = [NSMutableDictionary dictionary];
        _accountBlobBytesByDid = [NSMutableDictionary dictionary];
        _accountRepoBytesByDid = [NSMutableDictionary dictionary];
        _websocketBackpressureWarningsTotal = 0;
        _websocketBackpressureCriticalTotal = 0;
        _websocketQueueOverflowClosuresTotal = 0;
        _websocketConnectionsUnderBackpressure = 0;
    }
    return self;
}

- (void)dealloc {
#if !defined(__APPLE__)
    if (_metricsQueue) {
        dispatch_release(_metricsQueue);
        _metricsQueue = NULL;
    }
#endif
}

- (void)incrementHttpRequestsForMethod:(NSString *)method
                              endpoint:(NSString *)endpoint
                                status:(NSInteger)status {
    dispatch_sync(_metricsQueue, ^{
        NSString *methodKey = [NSString stringWithFormat:@"method_%@", method.lowercaseString];
        _httpRequestsByMethod[methodKey] = @(_httpRequestsByMethod[methodKey].integerValue + 1);

        NSString *endpointKey = [NSString stringWithFormat:@"endpoint_%@", endpoint];
        _httpRequestsByEndpoint[endpointKey] = @(_httpRequestsByEndpoint[endpointKey].integerValue + 1);

        NSString *statusKey = [NSString stringWithFormat:@"status_%ld", (long)status];
        _httpRequestsByStatus[statusKey] = @(_httpRequestsByStatus[statusKey].integerValue + 1);
    });
}

- (void)observeRequestLatency:(NSTimeInterval)seconds
                        method:(NSString *)method
                      endpoint:(NSString *)endpoint
                        status:(NSInteger)status {
    NSString *m = method.lowercaseString;
    NSString *ep = [endpoint stringByReplacingOccurrencesOfString:@"/xrpc/" withString:@""];
    NSString *key = [NSString stringWithFormat:@"%@|%@|%ld", m, ep, (long)status];

    dispatch_sync(_metricsQueue, ^{
        NSMutableDictionary<NSNumber *, NSNumber *> *buckets = _histogramBuckets[key];
        if (!buckets) {
            buckets = [NSMutableDictionary dictionaryWithCapacity:kHistogramBucketCount];
            for (NSUInteger i = 0; i < kHistogramBucketCount; i++) {
                buckets[@(kHistogramBuckets[i])] = @0;
            }
            _histogramBuckets[key] = buckets;
            _histogramSums[key] = @0.0;
            _histogramCounts[key] = @0;
        }

        for (NSUInteger i = 0; i < kHistogramBucketCount; i++) {
            NSNumber *threshold = @(kHistogramBuckets[i]);
            if (seconds <= kHistogramBuckets[i]) {
                buckets[threshold] = @(buckets[threshold].longLongValue + 1);
            }
        }

        _histogramSums[key] = @(_histogramSums[key].doubleValue + seconds);
        _histogramCounts[key] = @(_histogramCounts[key].longLongValue + 1);
    });
}

- (void)incrementRepositoryCount {
    dispatch_sync(_metricsQueue, ^{
        _repositoryCount++;
    });
}

- (void)incrementBlobCount {
    dispatch_sync(_metricsQueue, ^{
        _blobCount++;
    });
}

- (void)addBlobBytes:(unsigned long long)bytes {
    dispatch_sync(_metricsQueue, ^{
        _blobStorageBytes += bytes;
    });
}

- (void)setActiveConnections:(NSInteger)connections {
    dispatch_sync(_metricsQueue, ^{
        _activeConnections = connections;
    });
}

- (void)setDatabaseSize:(unsigned long long)bytes {
    dispatch_sync(_metricsQueue, ^{
        _databaseSizeBytes = bytes;
    });
}

- (void)setFirehoseSubscribers:(NSInteger)count {
    dispatch_sync(_metricsQueue, ^{
        _firehoseSubscribers = count;
    });
}

- (void)incrementFirehoseEvent:(NSString *)kind {
    dispatch_sync(_metricsQueue, ^{
        NSString *key = kind.lowercaseString;
        _firehoseEventsByKind[key] = @(_firehoseEventsByKind[key].integerValue + 1);
    });
}

- (void)setFirehoseSeq:(int64_t)seq {
    dispatch_sync(_metricsQueue, ^{
        _firehoseSeq = seq;
    });
}

- (void)incrementRateLimitRejection:(NSString *)type {
    dispatch_sync(_metricsQueue, ^{
        NSString *key = type.lowercaseString;
        _rateLimitRejectionsByType[key] = @(_rateLimitRejectionsByType[key].integerValue + 1);
    });
}

- (void)incrementRepoCommits {
    dispatch_sync(_metricsQueue, ^{
        _repoCommitsTotal++;
    });
}

- (void)incrementAuthFailure:(NSString *)reason {
    dispatch_sync(_metricsQueue, ^{
        NSString *key = reason.lowercaseString;
        _authFailuresByReason[key] = @(_authFailuresByReason[key].integerValue + 1);
    });
}

- (void)incrementOAuthTokenGrant:(NSString *)grantType {
    dispatch_sync(_metricsQueue, ^{
        NSString *key = grantType.lowercaseString;
        _oauthGrantsByType[key] = @(_oauthGrantsByType[key].integerValue + 1);
    });
}

- (void)setActiveAuthSessions:(NSInteger)count {
    dispatch_sync(_metricsQueue, ^{
        _activeAuthSessions = count;
    });
}

- (void)incrementQuotaExceeded:(NSString *)kind {
    dispatch_sync(_metricsQueue, ^{
        NSString *key = kind.lowercaseString;
        _quotaExceededByKind[key] = @(_quotaExceededByKind[key].integerValue + 1);
    });
}

- (void)setAccountBlobBytes:(unsigned long long)bytes forDid:(NSString *)did {
    dispatch_sync(_metricsQueue, ^{
        _accountBlobBytesByDid[did] = @(bytes);
    });
}

- (void)setAccountRepoBytes:(unsigned long long)bytes forDid:(NSString *)did {
    dispatch_sync(_metricsQueue, ^{
        _accountRepoBytesByDid[did] = @(bytes);
    });
}

#pragma mark - WebSocket Backpressure Metrics

- (void)recordWebSocketBackpressureWarning {
    dispatch_sync(_metricsQueue, ^{
        self.websocketBackpressureWarningsTotal++;
    });
}

- (void)recordWebSocketBackpressureCritical {
    dispatch_sync(_metricsQueue, ^{
        self.websocketBackpressureCriticalTotal++;
    });
}

- (void)recordWebSocketQueueOverflowClosure {
    dispatch_sync(_metricsQueue, ^{
        self.websocketQueueOverflowClosuresTotal++;
    });
}

- (void)recordWebSocketBackpressureStateChange:(BOOL)isUnderBackpressure {
    dispatch_sync(_metricsQueue, ^{
        if (isUnderBackpressure) {
            self.websocketConnectionsUnderBackpressure++;
        } else {
            if (self.websocketConnectionsUnderBackpressure > 0) {
                self.websocketConnectionsUnderBackpressure--;
            }
        }
    });
}

- (unsigned long long)residentMemoryBytes {
    unsigned long long residentBytes = 0;
#ifdef __APPLE__
    struct mach_task_basic_info info;
    mach_msg_type_number_t infoCount = MACH_TASK_BASIC_INFO_COUNT;
    if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO,
                  (task_info_t)&info, &infoCount) == KERN_SUCCESS) {
        residentBytes = info.resident_size;
    }
#else
    FILE *f = fopen("/proc/self/statm", "r");
    if (f) {
        unsigned long pages = 0;
        if (fscanf(f, "%*lu %lu", &pages) == 1) {
            residentBytes = (unsigned long long)pages * sysconf(_SC_PAGESIZE);
        }
        fclose(f);
    }
#endif
    return residentBytes;
}

- (unsigned long long)totalSystemMemoryBytes {
#ifdef __APPLE__
    uint64_t mem = 0;
    size_t len = sizeof(mem);
    sysctlbyname("hw.memsize", &mem, &len, NULL, 0);
    return mem;
#else
    long pages = sysconf(_SC_PHYS_PAGES);
    long page_size = sysconf(_SC_PAGESIZE);
    return (unsigned long long)pages * page_size;
#endif
}

- (NSString *)exportPrometheus {
    __block NSDictionary *methodsSnap;
    __block NSDictionary *endpointsSnap;
    __block NSDictionary *statusSnap;
    __block NSDictionary *histBucketsSnap;
    __block NSDictionary *histSumsSnap;
    __block NSDictionary *histCountsSnap;
    __block NSInteger repoCount;
    __block NSInteger blobCnt;
    __block unsigned long long blobBytes;
    __block unsigned long long dbBytes;
    __block NSInteger activConns;
    __block NSTimeInterval startTime;
    __block NSInteger firehoseSubs;
    __block int64_t firehoseSeqVal;
    __block NSInteger repoCommits;
    __block NSDictionary *firehoseEventsSnap;
    __block NSDictionary *rateLimitSnap;
    __block NSDictionary *authFailuresSnap;
    __block NSDictionary *oauthGrantsSnap;
    __block NSDictionary *quotaExceededSnap;
    __block NSDictionary *accountBlobBytesSnap;
    __block NSDictionary *accountRepoBytesSnap;
    __block NSInteger authSessions;
    __block NSInteger websocketBackpressureWarnings;
    __block NSInteger websocketBackpressureCriticals;
    __block NSInteger websocketQueueOverflows;
    __block NSInteger websocketConnectionsUnderBp;

    dispatch_sync(_metricsQueue, ^{
        methodsSnap = [_httpRequestsByMethod copy];
        endpointsSnap = [_httpRequestsByEndpoint copy];
        statusSnap = [_httpRequestsByStatus copy];
        repoCount = _repositoryCount;
        blobCnt = _blobCount;
        blobBytes = _blobStorageBytes;
        dbBytes = _databaseSizeBytes;
        activConns = _activeConnections;
        startTime = _serverStartTime;
        firehoseSubs = _firehoseSubscribers;
        firehoseSeqVal = _firehoseSeq;
        repoCommits = _repoCommitsTotal;
        firehoseEventsSnap = [_firehoseEventsByKind copy];
        rateLimitSnap = [_rateLimitRejectionsByType copy];
        authFailuresSnap = [_authFailuresByReason copy];
        oauthGrantsSnap = [_oauthGrantsByType copy];
        quotaExceededSnap = [_quotaExceededByKind copy];
        accountBlobBytesSnap = [_accountBlobBytesByDid copy];
        accountRepoBytesSnap = [_accountRepoBytesByDid copy];
        authSessions = _activeAuthSessions;
        websocketBackpressureWarnings = self.websocketBackpressureWarningsTotal;
        websocketBackpressureCriticals = self.websocketBackpressureCriticalTotal;
        websocketQueueOverflows = self.websocketQueueOverflowClosuresTotal;
        websocketConnectionsUnderBp = self.websocketConnectionsUnderBackpressure;

        NSMutableDictionary *bucketsCopy = [NSMutableDictionary dictionaryWithCapacity:_histogramBuckets.count];
        for (NSString *key in _histogramBuckets) {
            bucketsCopy[key] = [_histogramBuckets[key] copy];
        }
        histBucketsSnap = bucketsCopy;
        histSumsSnap = [_histogramSums copy];
        histCountsSnap = [_histogramCounts copy];
    });

    NSMutableString *output = [NSMutableString string];

    [output appendString:@"# HELP pds_http_requests_total Total HTTP requests\n"];
    [output appendString:@"# TYPE pds_http_requests_total counter\n"];

    for (NSString *key in methodsSnap) {
        NSString *method = [key stringByReplacingOccurrencesOfString:@"method_" withString:@""];
        [output appendFormat:@"pds_http_requests_total{method=\"%@\"} %@\n", method, methodsSnap[key]];
    }

    [output appendString:@"\n# HELP pds_http_requests_by_endpoint Total HTTP requests by endpoint\n"];
    [output appendString:@"# TYPE pds_http_requests_by_endpoint counter\n"];

    for (NSString *key in endpointsSnap) {
        NSString *endpoint = [key stringByReplacingOccurrencesOfString:@"endpoint_" withString:@""];
        endpoint = [endpoint stringByReplacingOccurrencesOfString:@"/xrpc/" withString:@""];
        [output appendFormat:@"pds_http_requests_by_endpoint{endpoint=\"%@\"} %@\n", endpoint, endpointsSnap[key]];
    }

    [output appendString:@"\n# HELP pds_http_responses_total Total HTTP responses by status code\n"];
    [output appendString:@"# TYPE pds_http_responses_total counter\n"];

    for (NSString *key in statusSnap) {
        NSString *status = [key stringByReplacingOccurrencesOfString:@"status_" withString:@""];
        [output appendFormat:@"pds_http_responses_total{status=\"%@\"} %@\n", status, statusSnap[key]];
    }

    [output appendString:@"\n# HELP pds_repository_count Total number of repositories\n"];
    [output appendString:@"# TYPE pds_repository_count gauge\n"];
    [output appendFormat:@"pds_repository_count %ld\n", (long)repoCount];

    [output appendString:@"\n# HELP pds_blob_count Total number of blobs\n"];
    [output appendString:@"# TYPE pds_blob_count gauge\n"];
    [output appendFormat:@"pds_blob_count %ld\n", (long)blobCnt];

    [output appendString:@"\n# HELP pds_blob_storage_bytes Total blob storage used\n"];
    [output appendString:@"# TYPE pds_blob_storage_bytes gauge\n"];
    [output appendFormat:@"pds_blob_storage_bytes %llu\n", blobBytes];

    [output appendString:@"\n# HELP pds_database_size_bytes Size of database file\n"];
    [output appendString:@"# TYPE pds_database_size_bytes gauge\n"];
    [output appendFormat:@"pds_database_size_bytes %llu\n", dbBytes];

    [output appendString:@"\n# HELP pds_active_connections Current active connections\n"];
    [output appendString:@"# TYPE pds_active_connections gauge\n"];
    [output appendFormat:@"pds_active_connections %ld\n", (long)activConns];

    [output appendString:@"\n# HELP pds_repo_commits_total Total repository commits\n"];
    [output appendString:@"# TYPE pds_repo_commits_total counter\n"];
    [output appendFormat:@"pds_repo_commits_total %ld\n", (long)repoCommits];

    [output appendString:@"\n# HELP pds_firehose_subscribers Current number of firehose subscribers\n"];
    [output appendString:@"# TYPE pds_firehose_subscribers gauge\n"];
    [output appendFormat:@"pds_firehose_subscribers %ld\n", (long)firehoseSubs];

    [output appendString:@"\n# HELP pds_firehose_seq Current firehose sequence number\n"];
    [output appendString:@"# TYPE pds_firehose_seq gauge\n"];
    [output appendFormat:@"pds_firehose_seq %lld\n", firehoseSeqVal];

    if (firehoseEventsSnap.count > 0) {
        [output appendString:@"\n# HELP pds_firehose_events_total Total firehose events by kind\n"];
        [output appendString:@"# TYPE pds_firehose_events_total counter\n"];
        for (NSString *kind in firehoseEventsSnap) {
            [output appendFormat:@"pds_firehose_events_total{kind=\"%@\"} %@\n", kind, firehoseEventsSnap[kind]];
        }
    }

    if (rateLimitSnap.count > 0) {
        [output appendString:@"\n# HELP pds_rate_limit_rejections_total Total rate limit rejections by type\n"];
        [output appendString:@"# TYPE pds_rate_limit_rejections_total counter\n"];
        for (NSString *type in rateLimitSnap) {
            [output appendFormat:@"pds_rate_limit_rejections_total{type=\"%@\"} %@\n", type, rateLimitSnap[type]];
        }
    }

    if (authFailuresSnap.count > 0) {
        [output appendString:@"\n# HELP pds_auth_failures_total Total auth failures by reason\n"];
        [output appendString:@"# TYPE pds_auth_failures_total counter\n"];
        for (NSString *reason in authFailuresSnap) {
            [output appendFormat:@"pds_auth_failures_total{reason=\"%@\"} %@\n", reason, authFailuresSnap[reason]];
        }
    }

    if (oauthGrantsSnap.count > 0) {
        [output appendString:@"\n# HELP pds_oauth_token_grants_total Total OAuth token grants by type\n"];
        [output appendString:@"# TYPE pds_oauth_token_grants_total counter\n"];
        for (NSString *grantType in oauthGrantsSnap) {
            [output appendFormat:@"pds_oauth_token_grants_total{grant_type=\"%@\"} %@\n", grantType, oauthGrantsSnap[grantType]];
        }
    }

    [output appendString:@"\n# HELP pds_auth_sessions_active Current active auth sessions\n"];
    [output appendString:@"# TYPE pds_auth_sessions_active gauge\n"];
    [output appendFormat:@"pds_auth_sessions_active %ld\n", (long)authSessions];

    [output appendString:@"\n# HELP pds_websocket_backpressure_warnings_total Total WebSocket backpressure warning events\n"];
    [output appendString:@"# TYPE pds_websocket_backpressure_warnings_total counter\n"];
    [output appendFormat:@"pds_websocket_backpressure_warnings_total %ld\n", (long)websocketBackpressureWarnings];

    [output appendString:@"\n# HELP pds_websocket_backpressure_critical_total Total WebSocket backpressure critical events\n"];
    [output appendString:@"# TYPE pds_websocket_backpressure_critical_total counter\n"];
    [output appendFormat:@"pds_websocket_backpressure_critical_total %ld\n", (long)websocketBackpressureCriticals];

    [output appendString:@"\n# HELP pds_websocket_queue_overflow_closures_total Total WebSocket queue overflow connection closures\n"];
    [output appendString:@"# TYPE pds_websocket_queue_overflow_closures_total counter\n"];
    [output appendFormat:@"pds_websocket_queue_overflow_closures_total %ld\n", (long)websocketQueueOverflows];

    [output appendString:@"\n# HELP pds_websocket_connections_under_backpressure Current WebSocket connections under backpressure\n"];
    [output appendString:@"# TYPE pds_websocket_connections_under_backpressure gauge\n"];
    [output appendFormat:@"pds_websocket_connections_under_backpressure %ld\n", (long)websocketConnectionsUnderBp];

    if (quotaExceededSnap.count > 0) {
        [output appendString:@"\n# HELP pds_account_quota_exceeded_total Total quota exceeded events by kind\n"];
        [output appendString:@"# TYPE pds_account_quota_exceeded_total counter\n"];
        for (NSString *kind in quotaExceededSnap) {
            [output appendFormat:@"pds_account_quota_exceeded_total{kind=\"%@\"} %@\n", kind, quotaExceededSnap[kind]];
        }
    }

    if (accountBlobBytesSnap.count > 0) {
        [output appendString:@"\n# HELP pds_account_blob_bytes Blob storage bytes per account\n"];
        [output appendString:@"# TYPE pds_account_blob_bytes gauge\n"];
        for (NSString *did in accountBlobBytesSnap) {
            [output appendFormat:@"pds_account_blob_bytes{did=\"%@\"} %@\n", did, accountBlobBytesSnap[did]];
        }
    }

    if (accountRepoBytesSnap.count > 0) {
        [output appendString:@"\n# HELP pds_account_repo_bytes Repo storage bytes per account\n"];
        [output appendString:@"# TYPE pds_account_repo_bytes gauge\n"];
        for (NSString *did in accountRepoBytesSnap) {
            [output appendFormat:@"pds_account_repo_bytes{did=\"%@\"} %@\n", did, accountRepoBytesSnap[did]];
        }
    }

    if (histBucketsSnap.count > 0) {
        [output appendString:@"\n# HELP pds_http_request_duration_seconds HTTP request latency in seconds\n"];
        [output appendString:@"# TYPE pds_http_request_duration_seconds histogram\n"];

        for (NSString *key in histBucketsSnap) {
            NSArray *parts = [key componentsSeparatedByString:@"|"];
            NSString *method = parts[0];
            NSString *endpoint = parts[1];
            NSString *status = parts[2];
            NSDictionary<NSNumber *, NSNumber *> *buckets = histBucketsSnap[key];
            long long count = [histCountsSnap[key] longLongValue];
            double sum = [histSumsSnap[key] doubleValue];

            for (NSUInteger i = 0; i < kHistogramBucketCount; i++) {
                NSNumber *threshold = @(kHistogramBuckets[i]);
                long long bucketVal = [buckets[threshold] longLongValue];
                [output appendFormat:
                    @"pds_http_request_duration_seconds_bucket{method=\"%@\",endpoint=\"%@\",status=\"%@\",le=\"%.3g\"} %lld\n",
                    method, endpoint, status, kHistogramBuckets[i], bucketVal];
            }
            [output appendFormat:
                @"pds_http_request_duration_seconds_bucket{method=\"%@\",endpoint=\"%@\",status=\"%@\",le=\"+Inf\"} %lld\n",
                method, endpoint, status, count];
            [output appendFormat:
                @"pds_http_request_duration_seconds_sum{method=\"%@\",endpoint=\"%@\",status=\"%@\"} %.6f\n",
                method, endpoint, status, sum];
            [output appendFormat:
                @"pds_http_request_duration_seconds_count{method=\"%@\",endpoint=\"%@\",status=\"%@\"} %lld\n",
                method, endpoint, status, count];
        }
    }

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];

    [output appendString:@"\n# HELP process_start_time_seconds Start time of the process since unix epoch in seconds\n"];
    [output appendString:@"# TYPE process_start_time_seconds gauge\n"];
    [output appendFormat:@"process_start_time_seconds %.0f\n", startTime];

    [output appendString:@"\n# HELP process_uptime_seconds Total time the process has been running in seconds\n"];
    [output appendString:@"# TYPE process_uptime_seconds gauge\n"];
    [output appendFormat:@"process_uptime_seconds %.0f\n", now - startTime];

    unsigned long long residentBytes = 0;
#ifdef __APPLE__
    struct mach_task_basic_info info;
    mach_msg_type_number_t infoCount = MACH_TASK_BASIC_INFO_COUNT;
    if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO,
                  (task_info_t)&info, &infoCount) == KERN_SUCCESS) {
        residentBytes = info.resident_size;
    }
#else
    FILE *f = fopen("/proc/self/statm", "r");
    if (f) {
        unsigned long pages = 0;
        if (fscanf(f, "%*lu %lu", &pages) == 1) {
            residentBytes = pages * sysconf(_SC_PAGESIZE);
        }
        fclose(f);
    }
#endif

    [output appendString:@"\n# HELP process_resident_memory_bytes Resident memory size in bytes\n"];
    [output appendString:@"# TYPE process_resident_memory_bytes gauge\n"];
    [output appendFormat:@"process_resident_memory_bytes %llu\n", residentBytes];

    return output;
}

@end
