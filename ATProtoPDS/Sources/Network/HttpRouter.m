#import "HttpRouter.h"
#import "Compat/PDSTypes.h"
#import "HttpRequest.h"
#import "HttpResponse.h"
#import "Auth/OAuthServerMetadata.h"
#import "WebSocketUpgradeHandler.h"
#import "HttpRouteTrie.h"

@interface HttpRoute ()

@property (nonatomic, readwrite, copy) NSString *method;
@property (nonatomic, readwrite, copy) NSString *pattern;
@property (nonatomic, readwrite, copy) HttpRouteHandler handler;
@property (nonatomic, readwrite) NSUInteger priority;

@end

@implementation HttpRoute

- (instancetype)initWithMethod:(NSString *)method
                       pattern:(NSString *)pattern
                       handler:(HttpRouteHandler)handler
                      priority:(NSUInteger)priority {
    self = [super init];
    if (self) {
        _method = [method copy];
        _pattern = [pattern copy];
        _handler = [handler copy];
        _priority = priority;
    }
    return self;
}

@end

@interface HttpRouter ()

@property (nonatomic, strong) NSMutableArray<HttpRoute *> *routes;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t routingQueue;
@property (nonatomic, strong) WebSocketUpgradeHandler *wsUpgradeHandler;
@property (nonatomic, copy, nullable) void (^wsUpgradeCallback)(HttpRequest *request, HttpResponse *response);
@property (nonatomic, strong) HttpRouteTrie *routeTrie;

@end

@implementation HttpRouter

- (instancetype)init {
    self = [super init];
    if (self) {
        _routes = [NSMutableArray array];
        _routingQueue = dispatch_queue_create("com.atproto.pds.router", DISPATCH_QUEUE_CONCURRENT);
        _wsUpgradeHandler = [[WebSocketUpgradeHandler alloc] init];
        _routeTrie = [[HttpRouteTrie alloc] init];
    }
    return self;
}

- (instancetype)initWithBaseURL:(NSString *)baseURL {
    self = [self init];
    if (self) {
        _baseURL = [baseURL copy];
    }
    return self;
}

- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response {
    [self setupRoutes];

    if ([self.wsUpgradeHandler isWebSocketUpgradeRequest:request]) {
        if (self.wsUpgradeCallback) {
            BOOL shouldUpgrade = [self.wsUpgradeHandler handleUpgradeRequest:request response:response];
            if (shouldUpgrade) {
                self.wsUpgradeCallback(request, response);
            }
        } else {
            [self.wsUpgradeHandler handleUpgradeRequest:request response:response];
        }
        return;
    }

    HttpRouteHandler handler = [self handlerForRequest:request];
    if (handler) {
        handler(request, response);
    } else {
        response.statusCode = 404;
    }
}

- (void)addRoute:(NSString *)method
         pattern:(NSString *)pattern
         handler:(HttpRouteHandler)handler {
    [self addRoute:method pattern:pattern handler:handler priority:100];
}

- (void)addRoute:(NSString *)method
         pattern:(NSString *)pattern
         handler:(HttpRouteHandler)handler
        priority:(NSUInteger)priority {

    // Validate inputs
    NSAssert(method != nil, @"Method cannot be nil");
    NSAssert(pattern != nil, @"Pattern cannot be nil");
    NSAssert(handler != nil, @"Handler cannot be nil");

    // Prevent path traversal in patterns
    if ([pattern containsString:@".."] || [pattern containsString:@"//"]) {
        NSAssert(NO, @"Invalid pattern: contains path traversal sequences");
        return;
    }

    HttpRoute *route = [[HttpRoute alloc] initWithMethod:method
                                                 pattern:pattern
                                                 handler:handler
                                                priority:priority];

    dispatch_barrier_async(self.routingQueue, ^{
        [self.routes addObject:route];
        [self.routeTrie insertRoute:method pattern:pattern handler:handler priority:priority];

        // Sort routes by priority (higher priority first)
        [self.routes sortUsingComparator:^NSComparisonResult(HttpRoute *a, HttpRoute *b) {
            if (a.priority > b.priority) return NSOrderedAscending;
            if (a.priority < b.priority) return NSOrderedDescending;
            return NSOrderedSame;
        }];
    });
}

- (nullable HttpRouteHandler)handlerForRequest:(HttpRequest *)request {
    NSString *requestMethod = request.methodString;
    NSString *requestPath = request.path;

    if ([requestPath containsString:@".."] || [requestPath hasPrefix:@"/"]) {
        requestPath = [self normalizePath:requestPath];
    }

    NSDictionary *params = nil;
    HttpRouteHandler handler = [self.routeTrie handlerForMethod:requestMethod path:requestPath outParameters:&params];
    if (handler && params) {
        request.pathParameters = params;
    }
    return handler;
}

- (BOOL)route:(HttpRoute *)route matchesMethod:(NSString *)method path:(NSString *)path {
    // Check method match
    if (![route.method isEqualToString:@"*"] && ![route.method isEqualToString:method]) {
        return NO;
    }

    // Check path match
    return [self path:path matchesPattern:route.pattern];
}

- (BOOL)path:(NSString *)path matchesPattern:(NSString *)pattern {
    // Exact match
    if ([path isEqualToString:pattern]) {
        return YES;
    }

    // Parameter pattern matching (e.g., "/users/:id")
    return [self path:path matchesParameterizedPattern:pattern];
}

- (BOOL)path:(NSString *)path matchesParameterizedPattern:(NSString *)pattern {
    NSArray<NSString *> *pathComponents = [path componentsSeparatedByString:@"/"];
    NSArray<NSString *> *patternComponents = [pattern componentsSeparatedByString:@"/"];

    if (pathComponents.count != patternComponents.count) {
        return NO;
    }

    for (NSUInteger i = 0; i < pathComponents.count; i++) {
        NSString *pathComponent = pathComponents[i];
        NSString *patternComponent = patternComponents[i];

        // Parameter component (starts with ':')
        if ([patternComponent hasPrefix:@":"]) {
            continue; // Parameter matches anything
        }

        // Wildcard component
        if ([patternComponent isEqualToString:@"*"]) {
            continue; // Wildcard matches anything
        }

        // Exact match required
        if (![pathComponent isEqualToString:patternComponent]) {
            return NO;
        }
    }

    return YES;
}

- (nullable NSDictionary<NSString *, NSString *> *)extractParametersFromPath:(NSString *)path
                                                                      pattern:(NSString *)pattern {
    NSMutableDictionary<NSString *, NSString *> *parameters = [NSMutableDictionary dictionary];

    NSArray<NSString *> *pathComponents = [path componentsSeparatedByString:@"/"];
    NSArray<NSString *> *patternComponents = [pattern componentsSeparatedByString:@"/"];

    // Filter out empty components (from leading/trailing slashes)
    NSMutableArray *filteredPathComponents = [NSMutableArray array];
    for (NSString *component in pathComponents) {
        if (component.length > 0) {
            [filteredPathComponents addObject:component];
        }
    }
    pathComponents = [filteredPathComponents copy];

    NSMutableArray *filteredPatternComponents = [NSMutableArray array];
    for (NSString *component in patternComponents) {
        if (component.length > 0) {
            [filteredPatternComponents addObject:component];
        }
    }
    patternComponents = [filteredPatternComponents copy];

    // Wildcard patterns may have fewer components than paths
    BOOL hasWildcard = NO;
    for (NSString *component in patternComponents) {
        if ([component isEqualToString:@"*"]) {
            hasWildcard = YES;
            break;
        }
    }

    if (!hasWildcard && pathComponents.count != patternComponents.count) {
        return nil;
    }

    // If path has fewer components than pattern, it can't match
    if (pathComponents.count < patternComponents.count) {
        return nil;
    }

    NSUInteger minCount = MIN(pathComponents.count, patternComponents.count);
    for (NSUInteger i = 0; i < minCount; i++) {
        NSString *pathComponent = pathComponents[i];
        NSString *patternComponent = patternComponents[i];

        if ([patternComponent hasPrefix:@":"]) {
            // Extract parameter
            NSString *paramName = [patternComponent substringFromIndex:1];
            parameters[paramName] = pathComponent;
        }
        // Wildcard (*) matches anything, no extraction needed
    }

    return [parameters copy];
}

- (NSString *)normalizePath:(NSString *)path {
    // Remove leading slashes and normalize
    while ([path hasPrefix:@"/"]) {
        path = [path substringFromIndex:1];
    }

    // Prevent directory traversal
    if ([path containsString:@".."]) {
        // In a secure implementation, this would return an error
        // For now, we'll sanitize by removing dangerous sequences
        path = [path stringByReplacingOccurrencesOfString:@".." withString:@""];
        path = [path stringByReplacingOccurrencesOfString:@"//" withString:@"/"];
    }

    return path;
}

- (void)setupRoutes {
    // ... existing routes ...

    __weak typeof(self) weakSelf = self;
    [self addRoute:@"GET"
             pattern:@"/.well-known/oauth-authorization-server"
             handler:^(HttpRequest *request, HttpResponse *response) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        // Validate base URL configuration
        if (!strongSelf.baseURL || [strongSelf.baseURL length] == 0) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{
                @"error": @"server_error",
                @"error_description": @"Server configuration error: base URL not configured"
            }];
            return;
        }

        OAuthServerMetadata *metadata = [[OAuthServerMetadata alloc] initWithBaseURL:strongSelf.baseURL];
        if (!metadata) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{
                @"error": @"server_error",
                @"error_description": @"Server configuration error: invalid base URL format"
            }];
            return;
        }

        // Add CORS headers for OAuth metadata
        [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
        [response setHeader:@"GET, OPTIONS" forKey:@"Access-Control-Allow-Methods"];
        [response setHeader:@"Content-Type, Authorization" forKey:@"Access-Control-Allow-Headers"];
        [response setHeader:@"86400" forKey:@"Access-Control-Max-Age"];

        [response setJsonBody:metadata.metadata];
        response.statusCode = HttpStatusOK;
    }];

    // CORS preflight for authorization server metadata
    [self addRoute:@"OPTIONS"
             pattern:@"/.well-known/oauth-authorization-server"
             handler:^(HttpRequest *request, HttpResponse *response) {
        [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
        [response setHeader:@"GET, OPTIONS" forKey:@"Access-Control-Allow-Methods"];
        [response setHeader:@"Content-Type, Authorization" forKey:@"Access-Control-Allow-Headers"];
        [response setHeader:@"86400" forKey:@"Access-Control-Max-Age"];
        response.statusCode = HttpStatusOK;
    }];

    [self addRoute:@"GET"
             pattern:@"/.well-known/oauth-protected-resource"
             handler:^(HttpRequest *request, HttpResponse *response) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        // Validate base URL configuration
        if (!strongSelf.baseURL || [strongSelf.baseURL length] == 0) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{
                @"error": @"server_error",
                @"error_description": @"Server configuration error: base URL not configured"
            }];
            return;
        }

        // OAuth 2.0 Protected Resource Metadata
        NSDictionary *resourceMetadata = @{
            @"resource": strongSelf.baseURL,
            @"authorization_servers": @[
                @{
                    @"authorization_server": strongSelf.baseURL,
                    @"resource_servers": @[strongSelf.baseURL]
                }
            ],
            @"protected_resources": @[
                @{
                    @"resource": strongSelf.baseURL,
                    @"resource_scopes": @[@"atproto"],
                    @"bearer_methods_supported": @[@"header"],
                    @"access_token_types_supported": @[@"Bearer"]
                }
            ],
            @"mtls_endpoint_aliases": @{
                @"token_endpoint": [strongSelf.baseURL stringByAppendingPathComponent:@"/oauth/token"],
                @"resource": strongSelf.baseURL
            }
        };

        // Add CORS headers for OAuth metadata
        [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
        [response setHeader:@"GET, OPTIONS" forKey:@"Access-Control-Allow-Methods"];
        [response setHeader:@"Content-Type, Authorization" forKey:@"Access-Control-Allow-Headers"];
        [response setHeader:@"86400" forKey:@"Access-Control-Max-Age"];

        [response setJsonBody:resourceMetadata];
        response.statusCode = HttpStatusOK;
    }];

    // CORS preflight for protected resource metadata
    [self addRoute:@"OPTIONS"
             pattern:@"/.well-known/oauth-protected-resource"
             handler:^(HttpRequest *request, HttpResponse *response) {
        [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
        [response setHeader:@"GET, OPTIONS" forKey:@"Access-Control-Allow-Methods"];
        [response setHeader:@"Content-Type, Authorization" forKey:@"Access-Control-Allow-Headers"];
        [response setHeader:@"86400" forKey:@"Access-Control-Max-Age"];
        response.statusCode = HttpStatusOK;
    }];
}

- (void)addWebSocketRoute:(NSString *)pattern handler:(void (^)(HttpRequest *request, HttpResponse *response))handler {
    self.wsUpgradeCallback = handler;
}

@end