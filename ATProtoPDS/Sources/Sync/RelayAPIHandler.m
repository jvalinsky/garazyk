#import "Sync/RelayAPIHandler.h"
#import "Sync/RelayMetrics.h"
#import "Sync/RelayUpstreamManager.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Debug/PDSLogger.h"
#import <Foundation/Foundation.h>

@interface RelayAPIHandler ()
@property (nonatomic, strong) RelayUpstreamManager *upstreamManager;
@property (nonatomic, strong) RelayMetrics *metrics;
@end

@implementation RelayAPIHandler

+ (instancetype)sharedHandler {
    static RelayAPIHandler *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[RelayAPIHandler alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // Upstream manager and metrics are set externally when relay is configured
        _upstreamManager = nil;
        _metrics = nil;
    }
    return self;
}

- (void)setMetrics:(RelayMetrics *)metrics {
    _metrics = metrics;
}

- (void)setUpstreamManager:(RelayUpstreamManager *)manager {
    _upstreamManager = manager;
}

- (BOOL)canHandleRequest:(HttpRequest *)request {
    if (!request) return NO;
    NSString *path = request.path;
    if (!path) return NO;
    return [path hasPrefix:@"/api/relay"];
}

- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *path = request.path ?: @"";

    // Route to appropriate handler
    if ([path isEqualToString:@"/api/relay/metrics"] ||
        [path isEqualToString:@"/api/relay/metrics/"]) {
        [self handleMetricsRequest:request response:response];
    }
    else if ([path isEqualToString:@"/api/relay/upstreams"] ||
             [path isEqualToString:@"/api/relay/upstreams/"]) {
        [self handleUpstreamsRequest:request response:response];
    }
    else if ([path isEqualToString:@"/api/relay/health"] ||
             [path isEqualToString:@"/api/relay/health/"]) {
        [self handleHealthRequest:request response:response];
    }
    else {
        // Unknown endpoint
        response.statusCode = HttpStatusNotFound;
        response.jsonBody = @{
            @"error": @"NotFound",
            @"message": @"Unknown relay API endpoint"
        };
    }
}

#pragma mark - Endpoint Handlers

- (void)handleMetricsRequest:(HttpRequest *)request response:(HttpResponse *)response {
    // Only allow GET
    if (request.method != HttpMethodGET) {
        response.statusCode = HttpStatusMethodNotAllowed;
        response.jsonBody = @{
            @"error": @"MethodNotAllowed",
            @"message": @"Only GET is allowed for this endpoint"
        };
        return;
    }

    // Get metrics snapshot - use stored instance or fallback to shared
    RelayMetrics *metricsSource = self.metrics ?: [RelayMetrics sharedMetrics];
    NSDictionary *metrics = [metricsSource snapshotDictionary];

    response.statusCode = HttpStatusOK;
    response.jsonBody = @{
        @"success": @YES,
        @"metrics": metrics
    };

    // Set CORS headers for web UI access
    [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
    [response setHeader:@"application/json" forKey:@"Content-Type"];
}

- (void)handleUpstreamsRequest:(HttpRequest *)request response:(HttpResponse *)response {
    // Only allow GET
    if (request.method != HttpMethodGET) {
        response.statusCode = HttpStatusMethodNotAllowed;
        response.jsonBody = @{
            @"error": @"MethodNotAllowed",
            @"message": @"Only GET is allowed for this endpoint"
        };
        return;
    }

    NSMutableArray *upstreamsData = [NSMutableArray array];

    if (self.upstreamManager) {
        NSArray<NSString *> *activeUpstreams = [self.upstreamManager activeUpstreams];
        NSArray<NSString *> *allUpstreams = [self.upstreamManager allUpstreams];

        // Build upstream status objects
        for (NSString *upstreamURL in allUpstreams) {
            BOOL isActive = [activeUpstreams containsObject:upstreamURL];
            BOOL isConnected = [self.upstreamManager isConnectedToUpstream:upstreamURL];

            [upstreamsData addObject:@{
                @"url": upstreamURL,
                @"active": @(isActive),
                @"connected": @(isConnected),
                @"status": isConnected ? @"connected" : (isActive ? @"connecting" : @"disconnected")
            }];
        }
    }

    response.statusCode = HttpStatusOK;
    response.jsonBody = @{
        @"success": @YES,
        @"upstreams": upstreamsData,
        @"total": @(upstreamsData.count)
    };

    // Set CORS headers
    [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
    [response setHeader:@"application/json" forKey:@"Content-Type"];
}

- (void)handleHealthRequest:(HttpRequest *)request response:(HttpResponse *)response {
    // Simple health check
    BOOL isHealthy = YES;
    RelayMetrics *metricsSource = self.metrics ?: [RelayMetrics sharedMetrics];
    NSDictionary *metrics = [metricsSource snapshotDictionary];

    // Consider unhealthy if no upstreams connected and reconnection count > 0
    int64_t upstreamConns = [metrics[@"upstreamConnections"] longLongValue];
    int64_t reconnectCount = [metrics[@"reconnectionCount"] longLongValue];

    if (upstreamConns == 0 && reconnectCount > 10) {
        isHealthy = NO;
    }

    response.statusCode = isHealthy ? HttpStatusOK : HttpStatusServiceUnavailable;
    response.jsonBody = @{
        @"status": isHealthy ? @"healthy" : @"degraded",
        @"upstreamConnections": @(upstreamConns),
        @"downstreamConnections": [metrics objectForKey:@"downstreamConnections"],
        @"currentSequence": [metrics objectForKey:@"currentSequence"]
    };

    [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
    [response setHeader:@"application/json" forKey:@"Content-Type"];
}

@end
