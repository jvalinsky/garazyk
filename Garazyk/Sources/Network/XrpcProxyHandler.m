// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/XrpcProxyHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcAuthHelper.h"
#import "Auth/JWT.h"
#import "Auth/PDSActorKeyManagerProtocol.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Debug/GZLogger.h"

@implementation XrpcProxyHandler

- (instancetype)initWithMinter:(JWTMinter *)minter {
    self = [super init];
    if (self) {
        _minter = minter;
    }
    return self;
}

- (instancetype)initWithProxyURL:(NSURL *)proxyURL
                     upstreamDID:(NSString *)upstreamDID
                          minter:(JWTMinter *)minter {
    self = [super init];
    if (self) {
        _proxyURL = [proxyURL copy];
        _upstreamDID = [upstreamDID copy];
        _minter = minter;
    }
    return self;
}

- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response {
    [self handleRequest:request response:response baseURL:self.proxyURL upstreamDID:self.upstreamDID];
}

- (void)handleRequest:(HttpRequest *)request
             response:(HttpResponse *)response
              baseURL:(NSURL *)baseURL
          upstreamDID:(NSString *)upstreamDID {

    if (!baseURL || !upstreamDID) {
        GZ_LOG_ERROR(@"Proxy request failed: No target baseURL or upstreamDID provided");
        response.statusCode = HttpStatusInternalServerError;
        [response setJsonBody:@{@"error": @"InternalError", @"message": @"Proxy target not configured"}];
        return;
    }

    // 1. Extract User DID from the incoming request.
    NSString *authHeader = [request headerForKey:@"Authorization"];
    NSString *userDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                       jwtMinter:self.minter
                                                 adminController:nil
                                                         request:request
                                                        response:response];

    if (!userDid) {
        if (response.statusCode == HttpStatusOK) {
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{@"error": @"AuthenticationRequired", @"message": @"Authentication required for proxying"}];
        }
        return;
    }

    // 2. Mint Service-to-Service JWT per AT Protocol spec.
    //    iss = user DID, aud = service DID (with fragment), lxm = method NSID,
    //    signed with user's repo signing key, exp = 60s, jti = random nonce.
    NSString *methodNSID = request.pathParameters[@"method"] ?: @"";
    NSString *token = nil;
    NSError *mintError = nil;

    if (self.signingKeyResolver) {
        // Resolve the user's actor key manager for signing
        id<PDSActorKeyManager> actorKeyManager = self.signingKeyResolver(userDid, &mintError);
        if (actorKeyManager) {
            token = [self.minter mintServiceAuthJWTForDID:userDid
                                                      aud:upstreamDID
                                                      lxm:methodNSID
                                          actorKeyManager:actorKeyManager
                                                     error:&mintError];
        } else {
            GZ_LOG_ERROR(@"Failed to resolve signing key for user %@: %@", userDid, mintError);
        }
    }

    if (!token) {
        // Fallback: if no signing key resolver or actor key resolution failed,
        // attempt legacy PDS-signed token (for AppView proxying where the
        // upstream service accepts PDS-signed tokens).
        GZ_LOG_WARN(@"Service auth JWT minting failed for user %@, falling back to PDS-signed token", userDid);
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        NSDictionary *payload = @{
            @"iss": self.minter.issuer ?: [[ATProtoServiceConfiguration sharedConfiguration] canonicalIssuer],
            @"sub": userDid,
            @"aud": upstreamDID,
            @"iat": @((NSInteger)now),
            @"exp": @((NSInteger)(now + 300)),
            @"lxm": methodNSID
        };
        token = [self.minter signPayload:payload error:&mintError];
    }

    if (!token) {
        GZ_LOG_ERROR(@"Failed to mint proxy token: %@", mintError);
        response.statusCode = HttpStatusInternalServerError;
        [response setJsonBody:@{@"error": @"InternalError", @"message": @"Failed to create service token"}];
        return;
    }

    // 3. Forward the request
    NSURLComponents *components = [NSURLComponents componentsWithURL:baseURL resolvingAgainstBaseURL:NO];

    // Ensure we append the method path correctly
    NSString *methodId = request.pathParameters[@"method"] ?: request.path;
    if ([methodId hasPrefix:@"/xrpc/"]) {
        methodId = [methodId substringFromIndex:6];
    }

    NSString *methodPath = [NSString stringWithFormat:@"/xrpc/%@", methodId];
    components.path = [components.path stringByAppendingPathComponent:methodPath];
    components.query = request.queryString;

    NSMutableURLRequest *proxyRequest = [NSMutableURLRequest requestWithURL:components.URL];
    proxyRequest.HTTPMethod = request.methodString;
    proxyRequest.HTTPBody = request.body;

    // Copy headers except Authorization (which we replace), Host, and Atproto-Proxy
    [request.headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *obj, BOOL *stop) {
        NSString *lowerKey = [key lowercaseString];
        if (![lowerKey isEqualToString:@"authorization"] &&
            ![lowerKey isEqualToString:@"host"] &&
            ![lowerKey isEqualToString:@"dpop"] &&
            ![lowerKey isEqualToString:@"atproto-proxy"]) {
            [proxyRequest setValue:obj forHTTPHeaderField:key];
        }
    }];

    [proxyRequest setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];

    // 4. Execute request synchronously (for now, as XrpcDispatcher is synchronous)
    NSTimeInterval proxyTimeoutSeconds = (NSClassFromString(@"XCTestCase") != Nil) ? 2.0 : 30.0;
    proxyRequest.timeoutInterval = proxyTimeoutSeconds;

    __block BOOL timedOut = NO;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:proxyRequest completionHandler:^(NSData *data, NSURLResponse *urlResponse, NSError *error) {
        if (timedOut) {
            return;
        }
        if (error) {
            if ([error.domain isEqualToString:NSURLErrorDomain] &&
                (error.code == NSURLErrorTimedOut || error.code == NSURLErrorCancelled)) {
                GZ_LOG_ERROR(@"Proxy request timed out (NSURLConnection): %@", request.path);
                response.statusCode = 504;
                [response setJsonBody:@{@"error": @"UpstreamTimeout", @"message": @"Upstream AppView did not respond within the timeout window"}];
            } else {
                GZ_LOG_ERROR(@"Proxy request failed to upstream %@: %@", baseURL, error);
                response.statusCode = HttpStatusServiceUnavailable;
                [response setJsonBody:@{@"error": @"UpstreamError", @"message": @"Failed to contact upstream service"}];
            }
        } else if ([urlResponse isKindOfClass:[NSHTTPURLResponse class]]) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)urlResponse;
            response.statusCode = (HttpStatusCode)httpResponse.statusCode;
            [response setBodyData:data];

            // Forward relevant headers from upstream
            [httpResponse.allHeaderFields enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                if ([key isKindOfClass:[NSString class]]) {
                    NSString *lowerKey = [key lowercaseString];
                    if (![lowerKey isEqualToString:@"content-length"] &&
                        ![lowerKey isEqualToString:@"transfer-encoding"] &&
                        ![lowerKey isEqualToString:@"connection"] &&
                        ![lowerKey isEqualToString:@"access-control-allow-origin"]) {
                        [response setHeader:obj forKey:key];
                    }
                }
            }];
        }
        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];
    long waitResult = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(proxyTimeoutSeconds * NSEC_PER_SEC)));
    if (waitResult != 0) {
        timedOut = YES;
        [task cancel];
        GZ_LOG_ERROR(@"Proxy request timed out after %.0f seconds: %@", proxyTimeoutSeconds, request.path);
        response.statusCode = 504;
        [response setJsonBody:@{@"error": @"UpstreamTimeout", @"message": @"Upstream AppView did not respond within the timeout window"}];
    }
}

@end
