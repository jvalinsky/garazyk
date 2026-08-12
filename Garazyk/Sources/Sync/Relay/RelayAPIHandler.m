// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Sync/Relay/RelayAPIHandler.h"
#import "Sync/Relay/RelayMetrics.h"
#import "Sync/Relay/RelayUpstreamManager.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Debug/GZLogger.h"
#import <Foundation/Foundation.h>

@interface ATProtoRelayAPIHandler ()
@property (nonatomic, strong) ATProtoRelayUpstreamManager *upstreamManager;
@property (nonatomic, strong) ATProtoRelayMetrics *metrics;
@end

@implementation ATProtoRelayAPIHandler

+ (instancetype)sharedHandler {
    static ATProtoRelayAPIHandler *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ATProtoRelayAPIHandler alloc] init];
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

- (void)setMetrics:(ATProtoRelayMetrics *)metrics {
    _metrics = metrics;
}

- (void)setUpstreamManager:(ATProtoRelayUpstreamManager *)manager {
    _upstreamManager = manager;
}

- (BOOL)canHandleRequest:(ATProtoHttpRequest *)request {
    if (!request) return NO;
    NSString *path = request.path;
    if (!path) return NO;
    return [path hasPrefix:@"/api/relay"];
}

- (void)handleRequest:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response {
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
    else if ([path isEqualToString:@"/api/relay/requestCrawl"] ||
             [path isEqualToString:@"/api/relay/requestCrawl/"]) {
        [self handleRequestCrawl:request response:response];
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

- (void)handleMetricsRequest:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response {
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
    ATProtoRelayMetrics *metricsSource = self.metrics ?: [ATProtoRelayMetrics sharedMetrics];
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

- (void)handleCapabilitiesRequest:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response {
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
            @"host_repo_state": @YES,
            @"mutations_require_auth": @YES,
            @"mutation_auth": @"dashboard_session"
        },
        @"version": @"1.0.0"
    };

    [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
    [response setHeader:@"application/json" forKey:@"Content-Type"];
}

- (void)handleUpstreamsRoute:(NSString *)path method:(HttpMethod)method body:(NSDictionary *)body response:(ATProtoHttpResponse *)response {
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

- (NSString *)crawlStateString:(RelayCrawlState)state {
    switch (state) {
        case RelayCrawlStateRequested: return @"requested";
        case RelayCrawlStateCrawling: return @"crawling";
        case RelayCrawlStateComplete: return @"complete";
        case RelayCrawlStateFailed: return @"failed";
        case RelayCrawlStateNotRequested: return @"not-requested";
    }
    return @"not-requested";
}

- (NSDictionary *)upstreamDictionaryForURL:(NSString *)upstreamURL {
    BOOL isActive = [[self.upstreamManager activeUpstreams] containsObject:upstreamURL];
    BOOL isConnected = [self.upstreamManager isConnectedToUpstream:upstreamURL];
    NSURL *parsedURL = [NSURL URLWithString:upstreamURL];
    NSString *hostname = parsedURL.host ?: upstreamURL;
    RelayHostStatus hostStatus = [self.upstreamManager statusForUpstream:upstreamURL];
    RelayCrawlState crawlState = [self.upstreamManager crawlStateForUpstream:upstreamURL];
    NSString *hostStatusString = @"disconnected";
    if (hostStatus == RelayHostStatusActive) hostStatusString = @"active";
    else if (hostStatus == RelayHostStatusError) hostStatusString = @"error";

    NSMutableDictionary *upstream = [@{
        @"url": upstreamURL,
        @"hostname": hostname,
        @"active": @(isActive),
        @"connected": @(isConnected),
        @"status": isConnected ? @"connected" : (isActive ? @"connecting" : @"disconnected"),
        @"hostStatus": hostStatusString,
        @"crawlRequested": @([self.upstreamManager crawlWasRequestedForUpstream:upstreamURL]),
        @"inventoryRequested": @([self.upstreamManager inventoryWasRequestedForUpstream:upstreamURL]),
        @"crawlState": [self crawlStateString:crawlState],
        @"crawlRepoCount": @([self.upstreamManager crawlRepoCountForUpstream:upstreamURL]),
        @"seq": @([self.upstreamManager seqForUpstream:upstreamURL]),
        @"accountCount": @([self.upstreamManager accountCountForUpstream:upstreamURL]),
        @"eventsReceived": @([self.upstreamManager eventCountForUpstream:upstreamURL]),
        @"eventCounts": [self.upstreamManager eventCountsByKindForUpstream:upstreamURL],
        @"reconnectAttempts": @([self.upstreamManager reconnectAttemptsForUpstream:upstreamURL])
    } mutableCopy];
    NSDate *requestedAt = [self.upstreamManager crawlRequestedAtForUpstream:upstreamURL];
    if (requestedAt) {
        upstream[@"crawlRequestedAt"] =
            [[[NSISO8601DateFormatter alloc] init] stringFromDate:requestedAt];
    }
    NSString *crawlError = [self.upstreamManager crawlErrorForUpstream:upstreamURL];
    if (crawlError.length > 0) upstream[@"crawlError"] = crawlError;
    NSDate *lastEventAt = [self.upstreamManager lastEventAtForUpstream:upstreamURL];
    if (lastEventAt) {
        upstream[@"lastEventAt"] =
            [[[NSISO8601DateFormatter alloc] init] stringFromDate:lastEventAt];
    }
    NSDate *connectedAt = [self.upstreamManager connectedAtForUpstream:upstreamURL];
    if (connectedAt) {
        upstream[@"connectedAt"] =
            [[[NSISO8601DateFormatter alloc] init] stringFromDate:connectedAt];
    }
    return upstream;
}

- (void)handleUpstreamsList:(ATProtoHttpResponse *)response {
    NSMutableArray *upstreamsData = [NSMutableArray array];

    if (self.upstreamManager) {
        for (NSString *upstreamURL in [self.upstreamManager allUpstreams]) {
            [upstreamsData addObject:[self upstreamDictionaryForURL:upstreamURL]];
        }
        for (NSString *requestedURL in [self.upstreamManager crawlRequestedUpstreams]) {
            if (![[self.upstreamManager allUpstreams] containsObject:requestedURL]) {
                [upstreamsData addObject:[self upstreamDictionaryForURL:requestedURL]];
            }
        }
    }

    response.statusCode = HttpStatusOK;
    response.jsonBody = @{@"success": @YES, @"upstreams": upstreamsData, @"total": @(upstreamsData.count)};
    [self setCORS:response];
}

- (void)handleUpstreamsCreate:(NSDictionary *)body response:(ATProtoHttpResponse *)response {
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
    GZ_LOG_SYNC_INFO(@"Relay: Added upstream %@", url);
}

- (void)handleUpstreamDetail:(NSString *)url response:(ATProtoHttpResponse *)response {
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

- (void)handleUpstreamConnect:(NSString *)url response:(ATProtoHttpResponse *)response {
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
    GZ_LOG_SYNC_INFO(@"Relay: Connecting to upstream %@", url);
}

- (void)handleUpstreamDisconnect:(NSString *)url response:(ATProtoHttpResponse *)response {
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
    GZ_LOG_SYNC_INFO(@"Relay: Disconnected from upstream %@", url);
}

- (void)handleUpstreamRemove:(NSString *)url response:(ATProtoHttpResponse *)response {
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
    GZ_LOG_SYNC_INFO(@"Relay: Removed upstream %@", url);
}

- (void)handleReconnectAll:(ATProtoHttpResponse *)response {
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
    GZ_LOG_SYNC_INFO(@"Relay: Reconnecting all upstreams");
}

- (void)handleDisconnectAll:(ATProtoHttpResponse *)response {
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
    GZ_LOG_SYNC_INFO(@"Relay: Disconnected all upstreams");
}

- (void)methodNotAllowed:(ATProtoHttpResponse *)response {
    response.statusCode = HttpStatusMethodNotAllowed;
    response.jsonBody = @{@"error": @"MethodNotAllowed", @"message": @"Method not allowed for this endpoint"};
    [self setCORS:response];
}

- (void)setCORS:(ATProtoHttpResponse *)response {
    [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
    [response setHeader:@"application/json" forKey:@"Content-Type"];
}

- (void)handleHealthRequest:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response {
    // Simple health check
    BOOL isHealthy = YES;
    ATProtoRelayMetrics *metricsSource = self.metrics ?: [ATProtoRelayMetrics sharedMetrics];
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

- (void)handleRequestCrawl:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response {
    if (request.method != HttpMethodPOST) {
        response.statusCode = HttpStatusMethodNotAllowed;
        response.jsonBody = @{@"error": @"MethodNotAllowed", @"message": @"Only POST is allowed for this endpoint"};
        [self setCORS:response];
        return;
    }

    NSDictionary *body = request.jsonBody;
    NSString *hostname = body[@"hostname"];
    if (!hostname || ![hostname isKindOfClass:[NSString class]] || hostname.length == 0) {
        response.statusCode = HttpStatusBadRequest;
        response.jsonBody = @{@"error": @"BadRequest", @"message": @"hostname is required in request body"};
        [self setCORS:response];
        return;
    }

    if (!self.upstreamManager) {
        response.statusCode = HttpStatusServiceUnavailable;
        response.jsonBody = @{@"error": @"ServiceUnavailable", @"message": @"Relay not configured"};
        [self setCORS:response];
        return;
    }

    // Construct a websocket URL from the hostname and record the request before
    // adding the upstream so the dashboard can distinguish it from configuration.
    NSString *wsURL = [hostname hasPrefix:@"ws"] ? hostname :
                      [NSString stringWithFormat:@"wss://%@/xrpc/com.atproto.sync.subscribeRepos", hostname];
    [self.upstreamManager markCrawlRequestedForUpstream:wsURL];

    // Check if already an upstream
    if ([[self.upstreamManager allUpstreams] containsObject:wsURL]) {
        // Already known — just reconnect
        [self.upstreamManager connectToUpstream:wsURL];
        response.statusCode = HttpStatusOK;
        response.jsonBody = @{@"success": @YES, @"hostname": hostname, @"action": @"reconnecting"};
    } else {
        // New upstream — add and connect
        [self.upstreamManager addUpstream:wsURL];
        response.statusCode = HttpStatusOK;
        response.jsonBody = @{@"success": @YES, @"hostname": hostname, @"action": @"crawling"};
    }
    [self setCORS:response];
    GZ_LOG_SYNC_INFO(@"Relay: Crawl requested for hostname %@", hostname);
}

@end
