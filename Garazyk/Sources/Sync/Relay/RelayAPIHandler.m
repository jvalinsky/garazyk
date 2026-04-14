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

    // Route to appropriate handler - specific routes first, then pattern matching
    if ([path isEqualToString:@"/api/relay/metrics"] ||
        [path isEqualToString:@"/api/relay/metrics/"]) {
        [self handleMetricsRequest:request response:response];
    }
    else if ([path isEqualToString:@"/api/relay/capabilities"] ||
             [path isEqualToString:@"/api/relay/capabilities/"]) {
        [self handleCapabilitiesRequest:request response:response];
    }
    else if ([path isEqualToString:@"/api/relay/health"] ||
             [path isEqualToString:@"/api/relay/health/"]) {
        [self handleHealthRequest:request response:response];
    }
    else if ([path isEqualToString:@"/api/relay/upstreams/reconnect-all"] ||
             [path isEqualToString:@"/api/relay/upstreams/reconnect-all/"]) {
        [self handleReconnectAll:response];
    }
    else if ([path isEqualToString:@"/api/relay/upstreams/disconnect-all"] ||
             [path isEqualToString:@"/api/relay/upstreams/disconnect-all/"]) {
        [self handleDisconnectAll:response];
    }
    else if ([path hasPrefix:@"/api/relay/upstreams"]) {
        [self handleUpstreamsRoute:path method:request.method body:request.jsonBody response:response];
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

- (void)handleCapabilitiesRequest:(HttpRequest *)request response:(HttpResponse *)response {
    if (request.method != HttpMethodGET) {
        response.statusCode = HttpStatusMethodNotAllowed;
        response.jsonBody = @{@"error": @"MethodNotAllowed", @"message": @"Only GET is allowed"};
        return;
    }

    response.statusCode = HttpStatusOK;
    response.jsonBody = @{
        @"success": @YES,
        @"capabilities": @{
            @"upstream_mutation": @YES,
            @"connect_one": @YES,
            @"disconnect_one": @YES,
            @"connect_all": @YES,
            @"disconnect_all": @YES,
            @"remove_upstream": @YES,
            @"event_stream": @YES,
            @"host_repo_state": @YES
        },
        @"version": @"1.0.0"
    };

    [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
    [response setHeader:@"application/json" forKey:@"Content-Type"];
}

- (void)handleUpstreamsRoute:(NSString *)path method:(HttpMethod)method body:(NSDictionary *)body response:(HttpResponse *)response {
    if ([path isEqualToString:@"/api/relay/upstreams"] || [path isEqualToString:@"/api/relay/upstreams/"]) {
        if (method == HttpMethodGET) {
            [self handleUpstreamsList:response];
        } else if (method == HttpMethodPOST) {
            [self handleUpstreamsCreate:body response:response];
        } else {
            [self methodNotAllowed:response];
        }
    } else if ([path hasPrefix:@"/api/relay/upstreams/"]) {
        NSString *encoded = [path substringFromIndex:@"/api/relay/upstreams/".length];
        NSString *action = nil;
        NSString *upstreamURL = nil;

        if ([encoded hasSuffix:@"/connect"]) {
            action = @"connect";
            upstreamURL = [encoded substringToIndex:encoded.length - @"/connect".length];
        } else if ([encoded hasSuffix:@"/disconnect"]) {
            action = @"disconnect";
            upstreamURL = [encoded substringToIndex:encoded.length - @"/disconnect".length];
        } else {
            upstreamURL = encoded;
        }

        upstreamURL = [self urlDecode:upstreamURL];

        if ([upstreamURL length] == 0) {
            response.statusCode = HttpStatusBadRequest;
            response.jsonBody = @{@"error": @"BadRequest", @"message": @"Upstream URL required"};
            [self setCORS:response];
            return;
        }

        if (action) {
            if (method != HttpMethodPOST) {
                [self methodNotAllowed:response];
                return;
            }
            if ([action isEqualToString:@"connect"]) {
                [self handleUpstreamConnect:upstreamURL response:response];
            } else if ([action isEqualToString:@"disconnect"]) {
                [self handleUpstreamDisconnect:upstreamURL response:response];
            }
        } else if (method == HttpMethodDELETE) {
            [self handleUpstreamRemove:upstreamURL response:response];
        } else if (method == HttpMethodGET) {
            [self handleUpstreamDetail:upstreamURL response:response];
        } else {
            [self methodNotAllowed:response];
        }
    } else {
        response.statusCode = HttpStatusNotFound;
        response.jsonBody = @{@"error": @"NotFound", @"message": @"Unknown upstream endpoint"};
        [self setCORS:response];
    }
}

- (NSString *)urlDecode:(NSString *)encoded {
    if (!encoded || encoded.length == 0) return @"";
    NSString *decoded = [encoded stringByReplacingOccurrencesOfString:@"%2F" withString:@"/"];
    decoded = [decoded stringByReplacingOccurrencesOfString:@"%3A" withString:@":"];
    decoded = [decoded stringByReplacingOccurrencesOfString:@"%3B" withString:@";"];
    decoded = [decoded stringByReplacingOccurrencesOfString:@"%40" withString:@"@"];
    decoded = [decoded stringByReplacingOccurrencesOfString:@"%3D" withString:@"="];
    decoded = [decoded stringByReplacingOccurrencesOfString:@"%26" withString:@"&"];
    return decoded;
}

- (void)handleUpstreamsList:(HttpResponse *)response {
    NSMutableArray *upstreamsData = [NSMutableArray array];

    if (self.upstreamManager) {
        NSArray<NSString *> *activeUpstreams = [self.upstreamManager activeUpstreams];
        NSArray<NSString *> *allUpstreams = [self.upstreamManager allUpstreams];

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
    response.jsonBody = @{@"success": @YES, @"upstreams": upstreamsData, @"total": @(upstreamsData.count)};
    [self setCORS:response];
}

- (void)handleUpstreamsCreate:(NSDictionary *)body response:(HttpResponse *)response {
    NSString *url = body[@"url"];
    if (!url || ![url isKindOfClass:[NSString class]] || url.length == 0) {
        response.statusCode = HttpStatusBadRequest;
        response.jsonBody = @{@"error": @"BadRequest", @"message": @"Upstream URL required in body.url"};
        [self setCORS:response];
        return;
    }

    if (![url hasPrefix:@"wss://"] && ![url hasPrefix:@"ws://"]) {
        response.statusCode = HttpStatusBadRequest;
        response.jsonBody = @{@"error": @"BadRequest", @"message": @"URL must start with wss:// or ws://"};
        [self setCORS:response];
        return;
    }

    if (self.upstreamManager) {
        [self.upstreamManager addUpstream:url];
    }

    response.statusCode = HttpStatusCreated;
    response.jsonBody = @{@"success": @YES, @"url": url, @"action": @"added"};
    [self setCORS:response];
    PDSLog(@"Relay: Added upstream %@", url);
}

- (void)handleUpstreamDetail:(NSString *)url response:(HttpResponse *)response {
    BOOL isActive = NO, isConnected = NO;
    NSString *status = @"unknown";

    if (self.upstreamManager) {
        isActive = [[self.upstreamManager activeUpstreams] containsObject:url];
        isConnected = [self.upstreamManager isConnectedToUpstream:url];
        status = isConnected ? @"connected" : (isActive ? @"connecting" : @"disconnected");
    }

    response.statusCode = HttpStatusOK;
    response.jsonBody = @{
        @"success": @YES,
        @"url": url,
        @"active": @(isActive),
        @"connected": @(isConnected),
        @"status": status
    };
    [self setCORS:response];
}

- (void)handleUpstreamConnect:(NSString *)url response:(HttpResponse *)response {
    if (!self.upstreamManager) {
        response.statusCode = HttpStatusServiceUnavailable;
        response.jsonBody = @{@"error": @"ServiceUnavailable", @"message": @"Relay not configured"};
        [self setCORS:response];
        return;
    }

    [self.upstreamManager connectToUpstream:url];
    response.statusCode = HttpStatusOK;
    response.jsonBody = @{@"success": @YES, @"url": url, @"action": @"connecting"};
    [self setCORS:response];
    PDSLog(@"Relay: Connecting to upstream %@", url);
}

- (void)handleUpstreamDisconnect:(NSString *)url response:(HttpResponse *)response {
    if (!self.upstreamManager) {
        response.statusCode = HttpStatusServiceUnavailable;
        response.jsonBody = @{@"error": @"ServiceUnavailable", @"message": @"Relay not configured"};
        [self setCORS:response];
        return;
    }

    [self.upstreamManager disconnectFromUpstream:url];
    response.statusCode = HttpStatusOK;
    response.jsonBody = @{@"success": @YES, @"url": url, @"action": @"disconnected"};
    [self setCORS:response];
    PDSLog(@"Relay: Disconnected from upstream %@", url);
}

- (void)handleUpstreamRemove:(NSString *)url response:(HttpResponse *)response {
    if (!self.upstreamManager) {
        response.statusCode = HttpStatusServiceUnavailable;
        response.jsonBody = @{@"error": @"ServiceUnavailable", @"message": @"Relay not configured"};
        [self setCORS:response];
        return;
    }

    if (self.upstreamManager) {
        [self.upstreamManager disconnectFromUpstream:url];
        [self.upstreamManager removeUpstream:url];
    }

    response.statusCode = HttpStatusOK;
    response.jsonBody = @{@"success": @YES, @"url": url, @"action": @"removed"};
    [self setCORS:response];
    PDSLog(@"Relay: Removed upstream %@", url);
}

- (void)handleReconnectAll:(HttpResponse *)response {
    if (!self.upstreamManager) {
        response.statusCode = HttpStatusServiceUnavailable;
        response.jsonBody = @{@"error": @"ServiceUnavailable", @"message": @"Relay not configured"};
        [self setCORS:response];
        return;
    }

    [self.upstreamManager connectAll];
    response.statusCode = HttpStatusOK;
    response.jsonBody = @{@"success": @YES, @"action": @"reconnect_all"};
    [self setCORS:response];
    PDSLog(@"Relay: Reconnecting all upstreams");
}

- (void)handleDisconnectAll:(HttpResponse *)response {
    if (!self.upstreamManager) {
        response.statusCode = HttpStatusServiceUnavailable;
        response.jsonBody = @{@"error": @"ServiceUnavailable", @"message": @"Relay not configured"};
        [self setCORS:response];
        return;
    }

    [self.upstreamManager disconnectAll];
    response.statusCode = HttpStatusOK;
    response.jsonBody = @{@"success": @YES, @"action": @"disconnect_all"};
    [self setCORS:response];
    PDSLog(@"Relay: Disconnected all upstreams");
}

- (void)methodNotAllowed:(HttpResponse *)response {
    response.statusCode = HttpStatusMethodNotAllowed;
    response.jsonBody = @{@"error": @"MethodNotAllowed", @"message": @"Method not allowed for this endpoint"};
    [self setCORS:response];
}

- (void)setCORS:(HttpResponse *)response {
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
