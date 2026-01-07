#import "Metrics/PDSMetrics.h"
#import <os/lock.h>

@interface PDSMetrics ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *httpRequestsByEndpoint;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *httpRequestsByStatus;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *httpRequestsByMethod;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *blobsByMimetype;
@property (nonatomic, assign) os_unfair_lock lock;
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
        _lock = OS_UNFAIR_LOCK_INIT;
        _httpRequestsByEndpoint = [NSMutableDictionary dictionary];
        _httpRequestsByStatus = [NSMutableDictionary dictionary];
        _httpRequestsByMethod = [NSMutableDictionary dictionary];
        _blobsByMimetype = [NSMutableDictionary dictionary];
        _repositoryCount = 0;
        _blobCount = 0;
        _blobStorageBytes = 0;
        _databaseSizeBytes = 0;
        _activeConnections = 0;
    }
    return self;
}

- (void)incrementHttpRequestsForMethod:(NSString *)method
                             endpoint:(NSString *)endpoint
                               status:(NSInteger)status {
    os_unfair_lock_lock(&_lock);

    NSString *methodKey = [NSString stringWithFormat:@"method_%@", method.lowercaseString];
    _httpRequestsByMethod[methodKey] = @(_httpRequestsByMethod[methodKey].integerValue + 1);

    NSString *endpointKey = [NSString stringWithFormat:@"endpoint_%@", endpoint];
    _httpRequestsByEndpoint[endpointKey] = @(_httpRequestsByEndpoint[endpointKey].integerValue + 1);

    NSString *statusKey = [NSString stringWithFormat:@"status_%ld", (long)status];
    _httpRequestsByStatus[statusKey] = @(_httpRequestsByStatus[statusKey].integerValue + 1);

    os_unfair_lock_unlock(&_lock);
}

- (void)incrementRepositoryCount {
    os_unfair_lock_lock(&_lock);
    _repositoryCount++;
    os_unfair_lock_unlock(&_lock);
}

- (void)incrementBlobCount {
    os_unfair_lock_lock(&_lock);
    _blobCount++;
    os_unfair_lock_unlock(&_lock);
}

- (void)addBlobBytes:(unsigned long long)bytes {
    os_unfair_lock_lock(&_lock);
    _blobStorageBytes += bytes;
    os_unfair_lock_unlock(&_lock);
}

- (void)setActiveConnections:(NSInteger)connections {
    os_unfair_lock_lock(&_lock);
    _activeConnections = connections;
    os_unfair_lock_unlock(&_lock);
}

- (void)setDatabaseSize:(unsigned long long)bytes {
    os_unfair_lock_lock(&_lock);
    _databaseSizeBytes = bytes;
    os_unfair_lock_unlock(&_lock);
}

- (NSString *)exportPrometheus {
    NSMutableString *output = [NSMutableString string];

    [output appendString:@"# HELP pds_http_requests_total Total HTTP requests\n"];
    [output appendString:@"# TYPE pds_http_requests_total counter\n"];

    for (NSString *key in _httpRequestsByMethod) {
        NSString *method = [key stringByReplacingOccurrencesOfString:@"method_" withString:@""];
        [output appendFormat:@"pds_http_requests_total{method=\"%@\"} %@\n", method, _httpRequestsByMethod[key]];
    }

    [output appendString:@"\n# HELP pds_http_requests_by_endpoint Total HTTP requests by endpoint\n"];
    [output appendString:@"# TYPE pds_http_requests_by_endpoint counter\n"];

    for (NSString *key in _httpRequestsByEndpoint) {
        NSString *endpoint = [key stringByReplacingOccurrencesOfString:@"endpoint_" withString:@""];
        endpoint = [endpoint stringByReplacingOccurrencesOfString:@"/xrpc/" withString:@""];
        [output appendFormat:@"pds_http_requests_by_endpoint{endpoint=\"%@\"} %@\n", endpoint, _httpRequestsByEndpoint[key]];
    }

    [output appendString:@"\n# HELP pds_http_responses_total Total HTTP responses by status code\n"];
    [output appendString:@"# TYPE pds_http_responses_total counter\n"];

    for (NSString *key in _httpRequestsByStatus) {
        NSString *status = [key stringByReplacingOccurrencesOfString:@"status_" withString:@""];
        [output appendFormat:@"pds_http_responses_total{status=\"%@\"} %@\n", status, _httpRequestsByStatus[key]];
    }

    [output appendString:@"\n# HELP pds_repository_count Total number of repositories\n"];
    [output appendString:@"# TYPE pds_repository_count gauge\n"];
    [output appendFormat:@"pds_repository_count %ld\n", (long)_repositoryCount];

    [output appendString:@"\n# HELP pds_blob_count Total number of blobs\n"];
    [output appendString:@"# TYPE pds_blob_count gauge\n"];
    [output appendFormat:@"pds_blob_count %ld\n", (long)_blobCount];

    [output appendString:@"\n# HELP pds_blob_storage_bytes Total blob storage used\n"];
    [output appendString:@"# TYPE pds_blob_storage_bytes gauge\n"];
    [output appendFormat:@"pds_blob_storage_bytes %llu\n", _blobStorageBytes];

    [output appendString:@"\n# HELP pds_database_size_bytes Size of database file\n"];
    [output appendString:@"# TYPE pds_database_size_bytes gauge\n"];
    [output appendFormat:@"pds_database_size_bytes %llu\n", _databaseSizeBytes];

    [output appendString:@"\n# HELP pds_active_connections Current active connections\n"];
    [output appendString:@"# TYPE pds_active_connections gauge\n"];
    [output appendFormat:@"pds_active_connections %ld\n", (long)_activeConnections];

    return output;
}

@end
