// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/XrpcHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/RateLimiter.h"
#import "Network/XrpcProxyHandler.h"
#import "Network/XrpcMiddleware.h"
#import "Auth/JWT.h"
#import "Core/DID.h"
#import "Debug/GZLogger.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"

@interface XrpcDispatcher ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, XrpcMethodHandler> *methodHandlers;
@property (nonatomic, strong) NSMutableDictionary<NSString *, XrpcMethodHandler> *internalHandlers;
@property (nonatomic, strong) NSSet<NSString *> *protectedMethods;

- (BOOL)validateHTTPMethodForMethodId:(NSString *)methodId
                               request:(HttpRequest *)request
                              response:(HttpResponse *)response;
- (NSSet<NSString *> *)queryMethodIds;
- (NSSet<NSString *> *)procedureMethodIds;
- (XrpcProxyHandler *)proxyHandlerWithMinter;

@end

@implementation XrpcDispatcher

static XrpcDispatcher *_sharedInstance = nil;

+ (instancetype)sharedDispatcher {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[self alloc] init];
    });
    return _sharedInstance;
}

+ (void)resetSharedDispatcher {
    _sharedInstance = [[self alloc] init];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _methodHandlers = [NSMutableDictionary dictionary];
        _internalHandlers = [NSMutableDictionary dictionary];
        
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
    NSMutableDictionary<NSString *, XrpcMethodHandler> *handlers =
        [methodId hasPrefix:@"_"] ? self.internalHandlers : self.methodHandlers;
    if (handlers[methodId] != nil) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"Duplicate XRPC handler registration for %@", methodId];
    }
    handlers[methodId] = [handler copy];
}

- (BOOL)hasRegisteredMethod:(NSString *)methodId {
    if (methodId.length == 0) {
        return NO;
    }
    return self.methodHandlers[methodId] != nil || self.internalHandlers[methodId] != nil;
}

- (void)resetRegisteredMethods {
    [self.methodHandlers removeAllObjects];
    [self.internalHandlers removeAllObjects];
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
    ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
    NSArray<NSString *> *allowedOrigins = [config arrayForKey:@"cors.allowed_origins"];
    if (!allowedOrigins) {
        allowedOrigins = @[@"*"];
    }

    NSString *origin = [request headerForKey: @"Origin"];
    if (origin && ([allowedOrigins containsObject: @"*"] || [origin hasPrefix: @"http://127.0.0.1"] || [origin hasPrefix: @"http://localhost"])) {
        [response setHeader:origin forKey: @"Access-Control-Allow-Origin"];
        [response setHeader: @"true" forKey: @"Access-Control-Allow-Credentials"];
    } else if (origin && [allowedOrigins containsObject:origin]) {
        [response setHeader:origin forKey: @"Access-Control-Allow-Origin"];
        [response setHeader: @"true" forKey: @"Access-Control-Allow-Credentials"];
    } else if (!origin && [allowedOrigins containsObject: @"*"]) {
        [response setHeader: @"*" forKey: @"Access-Control-Allow-Origin"];
    }

    NSString *allowedMethods = [config stringForKey:@"cors.allowed_methods"] ?: @"GET, POST, PUT, DELETE, OPTIONS, HEAD";
    NSString *allowedHeaders = [config stringForKey:@"cors.allowed_headers"] ?: @"DPoP, Authorization, Content-Type, *";
    NSInteger maxAge = [config integerForKey:@"cors.max_age"] ?: 86400;

    [response setHeader:allowedMethods forKey:@"Access-Control-Allow-Methods"];
    [response setHeader:allowedHeaders forKey:@"Access-Control-Allow-Headers"];
    [response setHeader:[NSString stringWithFormat:@"%ld", (long)maxAge] forKey:@"Access-Control-Max-Age"];
    [response setHeader:@"DPoP-Nonce, WWW-Authenticate" forKey:@"Access-Control-Expose-Headers"];
    [response setHeader:@"true" forKey:@"Access-Control-Allow-Private-Network"];
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

    // Check Rate Limit (per-IP)
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

    // Check Rate Limit (per-DID) — extract DID from Authorization header
    // without full JWT verification. The per-DID limit is only enforced when
    // the rate limiter is enabled and the request carries a Bearer token.
    NSString *authHeader = [request headerForKey:@"Authorization"];
    if (authHeader.length > 0) {
        NSString *did = [self _extractDIDFromAuthHeader:authHeader];
        if (did.length > 0) {
            RateLimitResult *didRateLimit = [[RateLimiter sharedLimiter] checkRateLimitForDid:did];
            if (!didRateLimit.allowed) {
                response.statusCode = HttpStatusTooManyRequests;
                [response setJsonBody:@{
                    @"error": @"RateLimitExceeded",
                    @"message": @"Rate limit exceeded"
                }];
                [response setHeader:[NSString stringWithFormat:@"%ld", (long)didRateLimit.limit] forKey:@"X-RateLimit-Limit"];
                [response setHeader:[NSString stringWithFormat:@"%ld", (long)didRateLimit.remaining] forKey:@"X-RateLimit-Remaining"];
                [response setHeader:[NSString stringWithFormat:@"%.0f", didRateLimit.resetSeconds] forKey:@"X-RateLimit-Reset"];
                [response setHeader:[NSString stringWithFormat:@"%.0f", didRateLimit.retryAfter] forKey:@"Retry-After"];
                return;
            }
        }
    }

    // Timeout signal: set default timeout for all network calls
    static const NSTimeInterval kDefaultRequestTimeout = 30.0;
    // request.timeoutInterval is not available on HttpRequest
    // Timeout should be configured at the session/connection level

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

    XrpcMethodHandler handler = self.methodHandlers[methodId] ?: self.internalHandlers[methodId];
    BOOL isProtected = [self isMethodProtected:methodId];

    GZ_LOG_INFO(@"XrpcHandler: methodId=%@, handler=%@, protected=%d", 
                 methodId, handler ? @"found" : @"nil", isProtected);

    if (![self validateHTTPMethodForMethodId:methodId request:request response:response]) {
        return;
    }

    // Protected methods always execute locally, including when an interceptor
    // is installed for AppView/chat/ozone routing.
    if (handler && isProtected) {
        GZ_LOG_INFO(@"XrpcHandler: Executing protected local handler for method=%@", methodId);
        [self executeHandler:handler methodId:methodId request:request response:response];
        return;
    }

    if (self.requestInterceptor) {
        BOOL handled = self.requestInterceptor(request, response, methodId, handler != nil);
        if (handled) {
            return;
        }
    }

    // 2. Handling for atproto-proxy header (Industry standard)
    //    Only honored for non-protected methods with known proxied prefixes.
    //    This enables service-to-service routing (chat/ozone/appview through PDS).
    NSString *atprotoProxy = [request headerForKey:@"atproto-proxy"];
    if (atprotoProxy && [self isProxiableMethod:methodId]) {
        NSURL *resolvedURL = nil;
        NSString *resolvedDID = nil;
        NSError *resolveError = nil;

        if ([self resolveProxyTarget:atprotoProxy outURL:&resolvedURL outDID:&resolvedDID error:&resolveError]) {
            GZ_LOG_INFO(@"Proxying XRPC method '%@' to resolved service %@ (%@)", methodId, resolvedDID, resolvedURL);
            XrpcProxyHandler *proxy = [self proxyHandlerWithMinter];
            [proxy handleRequest:request response:response baseURL:resolvedURL upstreamDID:resolvedDID];
            return;
        } else {
            GZ_LOG_ERROR(@"Failed to resolve atproto-proxy target '%@': %@", atprotoProxy, resolveError);
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
            GZ_LOG_INFO(@"XrpcHandler: Executing local app.bsky handler for method=%@", methodId);
            [self executeHandler:handler methodId:methodId request:request response:response];
        } else if (self.proxyURL) {
            GZ_LOG_INFO(@"Proxying XRPC method '%@' to AppView (automatic) %@", methodId, self.proxyURL);
            XrpcProxyHandler *proxy = [self proxyHandlerWithMinter];
            [proxy handleRequest:request response:response baseURL:self.proxyURL upstreamDID:self.upstreamDID];
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
            GZ_LOG_INFO(@"Proxying XRPC method '%@' to Ozone %@", methodId, self.ozoneURL);
            XrpcProxyHandler *proxy = [self proxyHandlerWithMinter];
            [proxy handleRequest:request response:response baseURL:self.ozoneURL upstreamDID:self.ozoneDID];
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
            GZ_LOG_INFO(@"Proxying XRPC method '%@' to Chat %@", methodId, self.chatURL);
            XrpcProxyHandler *proxy = [self proxyHandlerWithMinter];
            [proxy handleRequest:request response:response baseURL:self.chatURL upstreamDID:self.chatDID];
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
        GZ_LOG_ERROR(@"[XRPC] Unhandled exception in %@: %@ (%@)\n%@",
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

- (BOOL)validateHTTPMethodForMethodId:(NSString *)methodId
                               request:(HttpRequest *)request
                              response:(HttpResponse *)response {
    HttpMethod expectedMethod = HttpMethodUnknown;
    if ([[self queryMethodIds] containsObject:methodId]) {
        expectedMethod = HttpMethodGET;
    } else if ([[self procedureMethodIds] containsObject:methodId]) {
        expectedMethod = HttpMethodPOST;
    }

    if (expectedMethod == HttpMethodUnknown || request.method == expectedMethod) {
        return YES;
    }

    NSString *allowedMethod = expectedMethod == HttpMethodGET ? @"GET" : @"POST";
    response.statusCode = HttpStatusMethodNotAllowed;
    [response setHeader:allowedMethod forKey:@"Allow"];
    [response setJsonBody:@{
        @"error": @"MethodNotAllowed",
        @"message": [NSString stringWithFormat:@"Expected %@ for %@", allowedMethod, methodId]
    }];
    return NO;
}

- (NSSet<NSString *> *)queryMethodIds {
    static NSSet<NSString *> *queryMethods = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queryMethods = [NSSet setWithArray:@[
            @"com.atproto.admin.getSubjectStatus",
            @"com.atproto.identity.resolveHandle",
            @"com.atproto.repo.describeRepo",
            @"com.atproto.repo.getRecord",
            @"com.atproto.repo.listRecords",
            @"com.atproto.server.describeServer",
            @"com.atproto.server.getAccountInviteCodes",
            @"com.atproto.server.getSession",
            @"com.atproto.sync.getLatestCommit",
            @"com.atproto.sync.getRepo",
            @"com.atproto.sync.listRepos",
        ]];
    });
    return queryMethods;
}

- (NSSet<NSString *> *)procedureMethodIds {
    static NSSet<NSString *> *procedureMethods = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        procedureMethods = [NSSet setWithArray:@[
            @"com.atproto.admin.updateSubjectStatus",
            @"com.atproto.identity.updateHandle",
            @"com.atproto.repo.applyWrites",
            @"com.atproto.repo.createRecord",
            @"com.atproto.repo.deleteRecord",
            @"com.atproto.repo.putRecord",
            @"com.atproto.repo.uploadBlob",
            @"com.atproto.server.createAccount",
            @"com.atproto.server.createInviteCode",
            @"com.atproto.server.createInviteCodes",
            @"com.atproto.server.createSession",
            @"com.atproto.server.deleteAccount",
            @"com.atproto.server.deleteSession",
            @"com.atproto.server.refreshSession",
        ]];
    });
    return procedureMethods;
}

#pragma mark - Proxy Method Allowlist

- (BOOL)isProxiableMethod:(NSString *)methodId {
    // Only honor atproto-proxy for known proxied method prefixes.
    // This prevents header injection attacks that redirect protected
    // methods (com.atproto.server.createSession, etc.) to attacker servers.
    static NSArray<NSString *> *proxiedPrefixes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        proxiedPrefixes = @[
            @"app.bsky.",      // AppView
            @"chat.bsky.",     // Chat
            @"tools.ozone.",   // Ozone
        ];
    });
    for (NSString *prefix in proxiedPrefixes) {
        if ([methodId hasPrefix:prefix]) {
            return YES;
        }
    }
    return NO;
}

#pragma mark - Proxy Handler Construction

- (XrpcProxyHandler *)proxyHandlerWithMinter {
    XrpcProxyHandler *proxy = [[XrpcProxyHandler alloc] initWithMinter:self.jwtMinter];

    // Wire up the signing key resolver if we have access to the user database pool.
    // This allows the proxy handler to mint spec-compliant service auth JWTs
    // signed with the user's repo signing key (ES256K).
    if (self.userDatabasePool) {
        __weak PDSDatabasePool *weakPool = self.userDatabasePool;
        proxy.signingKeyResolver = ^id<PDSActorKeyManager>(NSString *userDID, NSError **error) {
            PDSDatabasePool *pool = weakPool;
            if (!pool) {
                if (error) {
                    *error = [NSError errorWithDomain:@"XrpcDispatcher"
                                                 code:503
                                             userInfo:@{NSLocalizedDescriptionKey: @"User database pool unavailable"}];
                }
                return nil;
            }
            PDSActorStore *store = [pool storeForDid:userDID error:error];
            return store.keyManager;
        };
    }

    return proxy;
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
    ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
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

    // Include the service fragment in the DID for the aud claim.
    // Per AT Protocol spec, the audience must be the full DID with fragment
    // (e.g., "did:web:chat.garazyk.xyz#bsky_chat") so the receiving service
    // can validate that the token was intended for it.
    if (outDID) {
        NSString *serviceId = serviceEntry[@"id"];
        if (serviceId.length > 0) {
            // serviceId is typically "#bsky_chat" — prepend the DID
            *outDID = [NSString stringWithFormat:@"%@%@", did, serviceId];
        } else {
            *outDID = did;
        }
    }

    return YES;
}

#pragma mark - Private Helpers

- (NSString *)_extractDIDFromAuthHeader:(NSString *)authHeader {
    // Lightweight DID extraction from Bearer token — decodes the JWT payload
    // without signature verification. This is sufficient for rate limiting
    // because the per-DID limit is a soft guard, not a security boundary.
    if (!authHeader) return nil;

    NSString *token = nil;
    if ([authHeader hasPrefix:@"Bearer "]) {
        token = [authHeader substringFromIndex:7];
    } else if ([authHeader hasPrefix:@"DPoP "]) {
        token = [authHeader substringFromIndex:5];
    } else {
        return nil;
    }

    // JWT format: header.payload.signature
    NSArray *parts = [token componentsSeparatedByString:@"."];
    if (parts.count != 3) return nil;

    // Base64url-decode the payload (second segment)
    NSString *payloadB64 = parts[1];
    // Pad with '=' to make valid base64
    NSUInteger padLen = (4 - payloadB64.length % 4) % 4;
    if (padLen > 0) {
        payloadB64 = [payloadB64 stringByAppendingString:
            [@"" stringByPaddingToLength:padLen withString:@"=" startingAtIndex:0]];
    }
    // Replace URL-safe chars
    NSMutableString *mutableB64 = [payloadB64 mutableCopy];
    [mutableB64 replaceOccurrencesOfString:@"-" withString:@"+" options:0 range:NSMakeRange(0, mutableB64.length)];
    [mutableB64 replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0, mutableB64.length)];

    NSData *payloadData = [[NSData alloc] initWithBase64EncodedString:mutableB64 options:0];
    if (!payloadData) return nil;

    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:payloadData
                                                            options:0
                                                              error:nil];
    return payload[@"did"];
}

@end
