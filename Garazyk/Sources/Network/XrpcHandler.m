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
#import "Debug/PDSLogger.h"
#import "App/PDSConfiguration.h"

@interface XrpcDispatcher ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, XrpcMethodHandler> *methodHandlers;
@property (nonatomic, strong) NSSet<NSString *> *protectedMethods;

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

    // 1. Protected methods always execute locally — never proxy them.
    //    This prevents atproto-proxy header injection from redirecting
    //    auth/admin requests to an attacker-controlled service.
    if (handler && isProtected) {
        PDS_LOG_INFO(@"XrpcHandler: Executing protected local handler for method=%@", methodId);
        [self executeHandler:handler methodId:methodId request:request response:response];
        return;
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

#pragma mark - Convenience Registration Methods

- (void)registerComAtprotoServerDescribeServer:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.describeServer" handler:handler];
}

- (void)registerComAtprotoServerCreateSession:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.createSession" handler:handler];
}

- (void)registerComAtprotoServerGetSession:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.getSession" handler:handler];
}

- (void)registerComAtprotoServerCreateAccount:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.createAccount" handler:handler];
}

- (void)registerComAtprotoServerRefreshSession:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.refreshSession" handler:handler];
}

- (void)registerComAtprotoServerDeleteSession:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.deleteSession" handler:handler];
}

- (void)registerComAtprotoServerCreateInviteCode:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.createInviteCode" handler:handler];
}

- (void)registerComAtprotoServerCreateInviteCodes:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.createInviteCodes" handler:handler];
}

- (void)registerComAtprotoServerGetAccountInviteCodes:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.getAccountInviteCodes" handler:handler];
}

- (void)registerComAtprotoServerCreateAppPassword:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.createAppPassword" handler:handler];
}

- (void)registerComAtprotoServerListAppPasswords:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.listAppPasswords" handler:handler];
}

- (void)registerComAtprotoServerRevokeAppPassword:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.revokeAppPassword" handler:handler];
}

- (void)registerComAtprotoServerGetServiceAuth:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.getServiceAuth" handler:handler];
}

- (void)registerComAtprotoServerGetAccount:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.getAccount" handler:handler];
}

- (void)registerComAtprotoServerDeleteAccount:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.deleteAccount" handler:handler];
}

- (void)registerComAtprotoServerCheckAccountStatus:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.checkAccountStatus" handler:handler];
}

- (void)registerComAtprotoServerActivateAccount:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.activateAccount" handler:handler];
}

- (void)registerComAtprotoServerDeactivateAccount:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.deactivateAccount" handler:handler];
}

- (void)registerComAtprotoServerConfirmEmail:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.confirmEmail" handler:handler];
}

- (void)registerComAtprotoServerRequestAccountDelete:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.requestAccountDelete" handler:handler];
}

- (void)registerComAtprotoServerRequestPasswordReset:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.requestPasswordReset" handler:handler];
}

- (void)registerComAtprotoServerReserveSigningKey:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.reserveSigningKey" handler:handler];
}

- (void)registerComAtprotoServerResetPassword:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.resetPassword" handler:handler];
}

- (void)registerComAtprotoTempRevokeAccountCredentials:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.temp.revokeAccountCredentials" handler:handler];
}

- (void)registerComAtprotoLexiconResolveLexicon:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.lexicon.resolveLexicon" handler:handler];
}

- (void)registerComAtprotoServerUpdateEmail:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.updateEmail" handler:handler];
}

- (void)registerComAtprotoServerRequestEmailConfirmation:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.requestEmailConfirmation" handler:handler];
}

- (void)registerComAtprotoServerRequestEmailUpdate:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.requestEmailUpdate" handler:handler];
}

- (void)registerComAtprotoRepoCreateRecord:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.repo.createRecord" handler:handler];
}

- (void)registerComAtprotoRepoGetRecord:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.repo.getRecord" handler:handler];
}

- (void)registerComAtprotoRepoListRecords:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.repo.listRecords" handler:handler];
}

- (void)registerComAtprotoRepoDeleteRecord:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.repo.deleteRecord" handler:handler];
}

- (void)registerComAtprotoRepoDeleteBlob:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.repo.deleteBlob" handler:handler];
}

- (void)registerComAtprotoRepoApplyWrites:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.repo.applyWrites" handler:handler];
}

- (void)registerComAtprotoRepoDescribeRepo:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.repo.describeRepo" handler:handler];
}

- (void)registerComAtprotoRepoPutRecord:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.repo.putRecord" handler:handler];
}

- (void)registerComAtprotoRepoUpdateRecord:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.repo.updateRecord" handler:handler];
}

- (void)registerComAtprotoRepoGetBlob:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.repo.getBlob" handler:handler];
}

- (void)registerComAtprotoRepoUploadBlob:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.repo.uploadBlob" handler:handler];
}

- (void)registerComAtprotoRepoImportRepo:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.repo.importRepo" handler:handler];
}

- (void)registerComAtprotoRepoListMissingBlobs:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.repo.listMissingBlobs" handler:handler];
}

- (void)registerComAtprotoSyncGetRepo:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.getRepo" handler:handler];
}

- (void)registerComAtprotoSyncGetCheckout:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.getCheckout" handler:handler];
}

- (void)registerComAtprotoSyncGetHead:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.getHead" handler:handler];
}

- (void)registerComAtprotoSyncGetBlob:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.getBlob" handler:handler];
}

- (void)registerComAtprotoSyncListBlobs:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.listBlobs" handler:handler];
}

- (void)registerComAtprotoSyncGetLatestCommit:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.getLatestCommit" handler:handler];
}

- (void)registerComAtprotoSyncGetBlocks:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.getBlocks" handler:handler];
}

- (void)registerComAtprotoSyncGetRecord:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.getRecord" handler:handler];
}

- (void)registerComAtprotoSyncGetHostStatus:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.getHostStatus" handler:handler];
}

- (void)registerComAtprotoSyncListHosts:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.listHosts" handler:handler];
}

- (void)registerComAtprotoSyncListRepos:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.listRepos" handler:handler];
}

- (void)registerComAtprotoSyncGetRepoStatus:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.getRepoStatus" handler:handler];
}

- (void)registerComAtprotoSyncListReposByCollection:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.listReposByCollection" handler:handler];
}

- (void)registerComAtprotoSyncNotifyOfUpdate:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.notifyOfUpdate" handler:handler];
}

- (void)registerComAtprotoSyncRequestCrawl:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.requestCrawl" handler:handler];
}

- (void)registerComAtprotoSyncSubscribeRepos:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.subscribeRepos" handler:handler];
}

- (void)registerComAtprotoIdentityResolveDid:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.identity.resolveDid" handler:handler];
}

- (void)registerComAtprotoIdentityResolveIdentity:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.identity.resolveIdentity" handler:handler];
}

- (void)registerComAtprotoIdentityResolveHandle:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.identity.resolveHandle" handler:handler];
}

- (void)registerComAtprotoIdentityGetRecommendedDidCredentials:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.identity.getRecommendedDidCredentials" handler:handler];
}

- (void)registerComAtprotoIdentityRefreshIdentity:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.identity.refreshIdentity" handler:handler];
}

- (void)registerComAtprotoIdentityRequestPlcOperationSignature:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.identity.requestPlcOperationSignature" handler:handler];
}

- (void)registerComAtprotoIdentitySignPlcOperation:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.identity.signPlcOperation" handler:handler];
}

- (void)registerComAtprotoIdentitySubmitPlcOperation:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.identity.submitPlcOperation" handler:handler];
}

- (void)registerComAtprotoIdentityUpdateHandle:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.identity.updateHandle" handler:handler];
}

- (void)registerComAtprotoModerationCreateReport:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.moderation.createReport" handler:handler];
}

- (void)registerComAtprotoAdminUpdateSubjectStatus:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.updateSubjectStatus" handler:handler];
}

- (void)registerComAtprotoAdminGetSubjectStatus:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.getSubjectStatus" handler:handler];
}

- (void)registerComAtprotoAdminGetAccountTakedown:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.getAccountTakedown" handler:handler];
}

- (void)registerComAtprotoAdminGetAccountInfo:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.getAccountInfo" handler:handler];
}

- (void)registerComAtprotoAdminGetAccountInfos:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.getAccountInfos" handler:handler];
}

- (void)registerComAtprotoAdminGetInviteCodes:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.getInviteCodes" handler:handler];
}

- (void)registerComAtprotoAdminDeleteAccount:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.deleteAccount" handler:handler];
}

- (void)registerComAtprotoAdminDisableAccountInvites:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.disableAccountInvites" handler:handler];
}

- (void)registerComAtprotoAdminEnableAccountInvites:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.enableAccountInvites" handler:handler];
}

- (void)registerComAtprotoAdminDisableInviteCodes:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.disableInviteCodes" handler:handler];
}

- (void)registerComAtprotoAdminSearchAccounts:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.searchAccounts" handler:handler];
}

- (void)registerComAtprotoAdminSendEmail:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.sendEmail" handler:handler];
}

- (void)registerComAtprotoAdminUpdateAccountEmail:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.updateAccountEmail" handler:handler];
}

- (void)registerComAtprotoAdminUpdateAccountHandle:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.updateAccountHandle" handler:handler];
}

- (void)registerComAtprotoAdminUpdateAccountPassword:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.updateAccountPassword" handler:handler];
}

- (void)registerComAtprotoAdminUpdateAccountSigningKey:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.updateAccountSigningKey" handler:handler];
}

- (void)registerComAtprotoAdminModerateAccount:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.moderateAccount" handler:handler];
}

- (void)registerComAtprotoAdminModerateRecord:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.moderateRecord" handler:handler];
}

- (void)registerComAtprotoAdminGetModerationReports:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.getModerationReports" handler:handler];
}

- (void)registerComAtprotoAdminResolveReport:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.resolveReport" handler:handler];
}

- (void)registerComAtprotoLabelQueryLabels:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.label.queryLabels" handler:handler];
}

- (void)registerComAtprotoLabelCreateLabel:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.label.createLabel" handler:handler];
}

- (void)registerComAtprotoLabelGetLabels:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.label.getLabels" handler:handler];
}

- (void)registerComAtprotoLabelSubscribeLabels:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.label.subscribeLabels" handler:handler];
}

- (void)registerAppBskyActorGetProfile:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.actor.getProfile" handler:handler];
}

- (void)registerAppBskyActorGetProfiles:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.actor.getProfiles" handler:handler];
}

- (void)registerAppBskyActorGetPreferences:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.actor.getPreferences" handler:handler];
}

- (void)registerAppBskyActorPutPreferences:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.actor.putPreferences" handler:handler];
}

- (void)registerAppBskyActorSearchActors:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.actor.searchActors" handler:handler];
}

- (void)registerAppBskyActorSearchActorsTypeahead:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.actor.searchActorsTypeahead" handler:handler];
}

- (void)registerAppBskyFeedGetTimeline:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.feed.getTimeline" handler:handler];
}

- (void)registerAppBskyFeedGetAuthorFeed:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.feed.getAuthorFeed" handler:handler];
}

- (void)registerAppBskyFeedGetPostThread:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.feed.getPostThread" handler:handler];
}

- (void)registerAppBskyFeedGetFeed:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.feed.getFeed" handler:handler];
}

- (void)registerAppBskyFeedGetActorLikes:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.feed.getActorLikes" handler:handler];
}

- (void)registerAppBskyFeedGetPosts:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.feed.getPosts" handler:handler];
}

- (void)registerAppBskyGraphGetMutes:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.graph.getMutes" handler:handler];
}

- (void)registerAppBskyGraphGetBlocks:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.graph.getBlocks" handler:handler];
}

- (void)registerAppBskyFeedGetFeedGenerators:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.feed.getFeedGenerators" handler:handler];
}

- (void)registerAppBskyNotificationRegisterPush:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.notification.registerPush" handler:handler];
}

- (void)registerAppBskyNotificationUnregisterPush:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.notification.unregisterPush" handler:handler];
}

- (void)registerAppBskyBookmarkGetBookmarks:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.bookmark.getBookmarks" handler:handler];
}

- (void)registerAppBskyBookmarkCreateBookmark:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.bookmark.createBookmark" handler:handler];
}

- (void)registerAppBskyBookmarkDeleteBookmark:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.bookmark.deleteBookmark" handler:handler];
}

- (void)registerAppBskyGraphGetStarterPack:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.graph.getStarterPack" handler:handler];
}

- (void)registerAppBskyGraphGetStarterPacks:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.graph.getStarterPacks" handler:handler];
}

- (void)registerAppBskyGraphGetActorStarterPacks:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.graph.getActorStarterPacks" handler:handler];
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

