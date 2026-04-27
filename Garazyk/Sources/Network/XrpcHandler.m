#import "Network/XrpcHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/RateLimiter.h"
#import "Network/XrpcProxyHandler.h"
#import "Network/XrpcMiddleware.h"
#import "Auth/JWT.h"
#import "Core/DID.h"
#import "Debug/PDSLogger.h"
#import "App/PDSConfiguration.h"

@interface XrpcDispatcher ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, XrpcMethodHandler> *methodHandlers;
@property (nonatomic, strong) NSSet<NSString *> *protectedMethods;

@end

@implementation XrpcDispatcher

+ (instancetype)sharedDispatcher {
    static XrpcDispatcher *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _methodHandlers = [NSMutableDictionary dictionary];
        
        // Methods that MUST be handled locally by the PDS
        _protectedMethods = [NSSet setWithArray:@[
            @"app.bsky.actor.getPreferences",
            @"app.bsky.actor.putPreferences",
            @"app.bsky.notification.registerPush",
            @"app.bsky.notification.unregisterPush",
            @"com.atproto.server.describeServer",
            @"com.atproto.server.createSession",
            @"com.atproto.server.getSession",
            @"com.atproto.server.refreshSession",
            @"com.atproto.server.deleteSession",
            @"com.atproto.server.createAccount",
            @"com.atproto.server.deleteAccount",
            @"com.atproto.repo.createRecord",
            @"com.atproto.repo.getRecord",
            @"com.atproto.repo.listRecords",
            @"com.atproto.repo.deleteRecord",
            @"com.atproto.repo.putRecord",
            @"com.atproto.repo.applyWrites",
            @"com.atproto.repo.uploadBlob",
            @"com.atproto.repo.describeRepo",
            @"com.atproto.sync.getRepo",
            @"com.atproto.sync.getCheckout",
            @"com.atproto.sync.getHead",
            @"com.atproto.sync.getLatestCommit",
            @"com.atproto.sync.getBlocks",
            @"com.atproto.sync.getRecord",
            @"com.atproto.sync.getBlob",
            @"com.atproto.sync.listBlobs",
            @"com.atproto.sync.listRepos",
            @"com.atproto.sync.subscribeRepos",
            @"com.atproto.identity.resolveDid",
            @"com.atproto.identity.resolveHandle",
            @"com.atproto.identity.updateHandle"
        ]];
    }
    return self;
}

- (BOOL)isMethodProtected:(NSString *)methodId {
    if ([methodId hasPrefix:@"com.atproto."]) {
        return YES;
    }
    return [self.protectedMethods containsObject:methodId];
}

- (void)registerMethod:(NSString *)methodId handler:(XrpcMethodHandler)handler {
    self.methodHandlers[methodId] = [handler copy];
}

- (void)registerMethod:(NSString *)methodId
           middlewares:(NSArray<id<XrpcMiddleware>> *)middlewares
               handler:(XrpcMethodHandler)handler {
    if (!middlewares || middlewares.count == 0) {
        // No middleware, just register the handler directly
        [self registerMethod:methodId handler:handler];
        return;
    }
    
    // Create a wrapped handler that executes middleware chain first
    XrpcMethodHandler wrappedHandler = ^(HttpRequest *request, HttpResponse *response) {
        // Execute middleware chain
        XrpcMiddlewareChain *chain = [[XrpcMiddlewareChain alloc] init];
        [chain addMiddlewares:middlewares];
        NSError *middlewareError = nil;
        BOOL passed = [chain handleRequest:request response:response error:&middlewareError];
        
        if (passed) {
            // All middleware passed, execute the actual handler
            handler(request, response);
        }
        // If middleware failed, response was already set by the failing middleware
    };
    
    [self registerMethod:methodId handler:wrappedHandler];
}

- (void)setCorsHeaders:(HttpResponse *)response forRequest:(HttpRequest *)request {
    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    NSArray<NSString *> *allowedOrigins = [config arrayForKey:@"cors.allowed_origins"];
    if (!allowedOrigins) {
        allowedOrigins = @[@"*"];
    }

    NSString *origin = [request headerForKey:@"Origin"];

    if (origin && [allowedOrigins containsObject:@"*"]) {
        [response setHeader:origin forKey:@"Access-Control-Allow-Origin"];
    } else if (origin && [allowedOrigins containsObject:origin]) {
        [response setHeader:origin forKey:@"Access-Control-Allow-Origin"];
    } else if (!origin && [allowedOrigins containsObject:@"*"]) {
        [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
    }

    NSString *allowedMethods = [config stringForKey:@"cors.allowed_methods"] ?: @"GET, POST, PUT, DELETE, OPTIONS, HEAD";
    NSString *allowedHeaders = [config stringForKey:@"cors.allowed_headers"] ?: @"DPoP, Authorization, Content-Type, *";
    NSInteger maxAge = [config integerForKey:@"cors.max_age"] ?: 86400;

    [response setHeader:allowedMethods forKey:@"Access-Control-Allow-Methods"];
    [response setHeader:allowedHeaders forKey:@"Access-Control-Allow-Headers"];
    [response setHeader:[NSString stringWithFormat:@"%ld", (long)maxAge] forKey:@"Access-Control-Max-Age"];
    [response setHeader:@"DPoP-Nonce, WWW-Authenticate" forKey:@"Access-Control-Expose-Headers"];
    [response setHeader:@"Origin" forKey:@"Vary"];
}

- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response {
    // Handle CORS preflight immediately — the /xrpc pathHandler prefix match
    // catches OPTIONS before the route trie's explicit OPTIONS route, so we
    // must handle it here to guarantee a 200 response for browsers.
    if (request.method == HttpMethodOPTIONS) {
        [self setCorsHeaders:response forRequest:request];
        response.statusCode = HttpStatusOK;
        return;
    }

    // Set CORS headers for all XRPC responses (not just OPTIONS)
    [self setCorsHeaders:response forRequest:request];

    // Check Rate Limit
    RateLimitResult *rateLimit = [[RateLimiter sharedLimiter] checkRateLimitForIP:request.remoteAddress];
    if (!rateLimit.allowed) {
        response.statusCode = HttpStatusTooManyRequests;
        [response setJsonBody:@{
            @"error": @"RateLimitExceeded",
            @"message": @"Too many requests"
        }];
        
        // Add rate limit headers for client backoff (per reference implementation)
        // Reference: reference/indigo/xrpc/xrpc.go (errorFromHTTPResponse function)
        [response setHeader:[NSString stringWithFormat:@"%ld", (long)rateLimit.limit] forKey:@"X-RateLimit-Limit"];
        [response setHeader:[NSString stringWithFormat:@"%ld", (long)rateLimit.remaining] forKey:@"X-RateLimit-Remaining"];
        [response setHeader:[NSString stringWithFormat:@"%.0f", rateLimit.resetSeconds] forKey:@"X-RateLimit-Reset"];
        [response setHeader:[NSString stringWithFormat:@"%.0f", rateLimit.retryAfter] forKey:@"Retry-After"];
        
        return;
    }

    NSString *path = request.path;
    NSString *methodId = request.pathParameters[@"method"];

    if (!methodId || methodId.length == 0) {
        methodId = nil;
    }

    if (!methodId) {
        if ([path hasPrefix:@"/xrpc/"]) {
            methodId = [path substringFromIndex:6];
        } else if ([path hasPrefix:@"/"]) {
            methodId = [path substringFromIndex:1];
        }
    }

    if (!methodId || methodId.length == 0) {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{@"error": @"InvalidMethod", @"message": @"Missing XRPC method name"}];
        return;
    }

    XrpcMethodHandler handler = self.methodHandlers[methodId];
    BOOL isProtected = [self isMethodProtected:methodId];

    PDS_LOG_INFO(@"XrpcHandler: methodId=%@, handler=%@, protected=%d", 
                 methodId, handler ? @"found" : @"nil", isProtected);

    if (self.requestInterceptor) {
        BOOL handled = self.requestInterceptor(request, response, methodId, handler != nil);
        if (handled) {
            return;
        }
    }

    // 1. If method is local and protected, execute it
    if (handler && isProtected) {
        PDS_LOG_INFO(@"XrpcHandler: Executing protected local handler for method=%@", methodId);
        [self executeHandler:handler methodId:methodId request:request response:response];
        return;
    }

    // 2. Handling for atproto-proxy header (Industry standard)
    NSString *atprotoProxy = [request headerForKey:@"atproto-proxy"];
    if (atprotoProxy && !isProtected) {
        NSURL *resolvedURL = nil;
        NSString *resolvedDID = nil;
        NSError *resolveError = nil;
        
        if ([self resolveProxyTarget:atprotoProxy outURL:&resolvedURL outDID:&resolvedDID error:&resolveError]) {
            PDS_LOG_INFO(@"Proxying XRPC method '%@' to resolved service %@ (%@)", methodId, resolvedDID, resolvedURL);
            XrpcProxyHandler *proxy = [[XrpcProxyHandler alloc] initWithMinter:self.jwtMinter];
            [proxy handleRequest:request response:response baseURL:resolvedURL upstreamDID:resolvedDID];
            return;
        } else {
            PDS_LOG_ERROR(@"Failed to resolve atproto-proxy target '%@': %@", atprotoProxy, resolveError);
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{
                @"error": @"InvalidAtprotoProxy", 
                @"message": resolveError.localizedDescription ?: @"Failed to resolve proxy target"
            }];
            return;
        }
    }

    // 3. Fallback for app.bsky.* methods (AppView)
    if ([methodId hasPrefix:@"app.bsky."] && !isProtected) {
        if (handler) {
            PDS_LOG_INFO(@"XrpcHandler: Executing local app.bsky handler for method=%@", methodId);
            [self executeHandler:handler methodId:methodId request:request response:response];
        } else if (self.proxyURL) {
            PDS_LOG_INFO(@"Proxying XRPC method '%@' to AppView (automatic) %@", methodId, self.proxyURL);
            XrpcProxyHandler *proxy = [[XrpcProxyHandler alloc] initWithProxyURL:self.proxyURL
                                                                     upstreamDID:self.upstreamDID
                                                                          minter:self.jwtMinter];
            [proxy handleRequest:request response:response];
        } else {
            [self sendMethodNotFound:methodId response:response];
        }
        return;
    }

    // 4. Fallback for tools.ozone.* methods (Moderation)
    if ([methodId hasPrefix:@"tools.ozone."] && !isProtected) {
        if (handler) {
            [self executeHandler:handler methodId:methodId request:request response:response];
        } else if (self.ozoneURL) {
            PDS_LOG_INFO(@"Proxying XRPC method '%@' to Ozone %@", methodId, self.ozoneURL);
            XrpcProxyHandler *proxy = [[XrpcProxyHandler alloc] initWithProxyURL:self.ozoneURL
                                                                     upstreamDID:self.ozoneDID
                                                                          minter:self.jwtMinter];
            [proxy handleRequest:request response:response];
        } else {
            [self sendMethodNotFound:methodId response:response];
        }
        return;
    }

    // 5. Fallback for chat.bsky.* methods (Chat)
    if ([methodId hasPrefix:@"chat.bsky."] && !isProtected) {
        if (handler) {
            [self executeHandler:handler methodId:methodId request:request response:response];
        } else if (self.chatURL) {
            PDS_LOG_INFO(@"Proxying XRPC method '%@' to Chat %@", methodId, self.chatURL);
            XrpcProxyHandler *proxy = [[XrpcProxyHandler alloc] initWithProxyURL:self.chatURL
                                                                     upstreamDID:self.chatDID
                                                                          minter:self.jwtMinter];
            [proxy handleRequest:request response:response];
        } else {
            [self sendMethodNotFound:methodId response:response];
        }
        return;
    }

    // 6. Final attempt: Local handler (even if not explicitly protected, e.g. custom lexicons)
    if (handler) {
        [self executeHandler:handler methodId:methodId request:request response:response];
        return;
    }

    if (self.defaultHandler) {
        self.defaultHandler(request, response);
        return;
    }

    [self sendMethodNotFound:methodId response:response];
}

- (void)executeHandler:(XrpcMethodHandler)handler 
             methodId:(NSString *)methodId 
              request:(HttpRequest *)request 
             response:(HttpResponse *)response {
    @try {
        handler(request, response);
    } @catch (NSException *exception) {
        NSString *name = exception.name ?: @"(null)";
        NSString *reason = exception.reason ?: @"(null)";
        NSArray<NSString *> *stack = exception.callStackSymbols ?: @[];
        PDS_LOG_ERROR(@"[XRPC] Unhandled exception in %@: %@ (%@)\n%@",
                      methodId, name, reason, [stack componentsJoinedByString:@"\n"]);

        response.statusCode = HttpStatusInternalServerError;
        [response setJsonBody:@{
            @"error": @"InternalServerError",
            @"message": @"Unhandled exception"
        }];
    }
}

- (void)sendMethodNotFound:(NSString *)methodId response:(HttpResponse *)response {
    response.statusCode = HttpStatusNotFound;
    [response setJsonBody:@{
        @"error": @"MethodNotFound",
        @"message": [NSString stringWithFormat:@"XRPC method '%@' not found", methodId]
    }];
}

#pragma mark - Proxy Resolution

- (BOOL)resolveProxyTarget:(NSString *)proxyDescriptor 
                    outURL:(NSURL **)outURL 
                    outDID:(NSString **)outDID 
                     error:(NSError **)error {
    
    if (proxyDescriptor.length == 0) return NO;

    // Check if it's already a direct URL
    NSURL *directURL = [NSURL URLWithString:proxyDescriptor];
    if (directURL.scheme.length > 0 && directURL.host.length > 0) {
        if (outURL) *outURL = directURL;
        // If it's a URL, we attempt to infer the DID from the host if not provided
        if (outDID) *outDID = [NSString stringWithFormat:@"did:web:%@", directURL.host];
        return YES;
    }

    NSString *did = proxyDescriptor;
    NSString *serviceFragment = nil;
    NSRange fragmentRange = [proxyDescriptor rangeOfString:@"#"];
    if (fragmentRange.location != NSNotFound) {
        did = [proxyDescriptor substringToIndex:fragmentRange.location];
        serviceFragment = [proxyDescriptor substringFromIndex:fragmentRange.location + 1];
    }

    if (![did hasPrefix:@"did:"]) {
        if (error) *error = [NSError errorWithDomain:@"XrpcDispatcher" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Proxy target must be a URL or DID"}];
        return NO;
    }

    // Use DIDResolver to get document
    DIDResolver *resolver = [[DIDResolver alloc] init];
    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    if (config.plcURL.length > 0) {
        resolver.plcURL = config.plcURL;
    }

    DIDDocument *document = [resolver resolveDIDSync:did error:error];
    if (!document) return NO;

    // Find service entry
    NSDictionary *serviceEntry = nil;
    NSArray<NSDictionary *> *services = document.service ?: @[];
    
    if (serviceFragment.length > 0) {
        NSString *targetId = [serviceFragment hasPrefix:@"#"] ? serviceFragment : [@"#" stringByAppendingString:serviceFragment];
        for (NSDictionary *entry in services) {
            NSString *entryId = entry[@"id"];
            if ([entryId isEqualToString:targetId] || [entryId hasSuffix:targetId]) {
                serviceEntry = entry;
                break;
            }
        }
    } else {
        // Default to first appview or just the first service
        for (NSDictionary *entry in services) {
            NSString *type = entry[@"type"];
            if ([type.lowercaseString containsString:@"appview"]) {
                serviceEntry = entry;
                break;
            }
        }
        if (!serviceEntry && services.count > 0) {
            serviceEntry = services.firstObject;
        }
    }

    if (!serviceEntry) {
        if (error) *error = [NSError errorWithDomain:@"XrpcDispatcher" code:404 userInfo:@{NSLocalizedDescriptionKey: @"Service not found in DID document"}];
        return NO;
    }

    NSString *endpoint = serviceEntry[@"serviceEndpoint"];
    if (endpoint.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"XrpcDispatcher" code:502 userInfo:@{NSLocalizedDescriptionKey: @"Service entry has no endpoint"}];
        return NO;
    }

    if (outURL) *outURL = [NSURL URLWithString:endpoint];
    if (outDID) *outDID = did;

    return YES;
}

@end

