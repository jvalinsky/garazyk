// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AppViewOAuth2Middleware.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/Auth/AppViewOAuth2Middleware.h"
#import "AppView/Server/AppViewDatabase.h"
#import "Network/HttpRequest.h"
#import "Auth/Crypto/JWT.h"
#import "Auth/Crypto/AuthCryptoDPoP.h"
#import "Auth/Crypto/CryptoUtils.h"
#import "Auth/PDSReplayCache.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Debug/GZLogger.h"
#import "Compat/PDSTypes.h"

NSErrorDomain const AppViewOAuth2MiddlewareErrorDomain = @"AppViewOAuth2Middleware";

static BOOL AppViewOAuthEnvBool(NSString *value) {
    if (value.length == 0) return NO;
    NSString *normalized = [[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    return [normalized isEqualToString:@"1"] ||
           [normalized isEqualToString:@"true"] ||
           [normalized isEqualToString:@"yes"] ||
           [normalized isEqualToString:@"on"];
}

static BOOL AppViewOAuthIsTrustedProxyRemoteAddress(NSString *remoteAddress) {
    NSString *candidate = [[remoteAddress ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if (candidate.length == 0) return NO;
    if ([candidate hasPrefix:@"127."] || [candidate isEqualToString:@"::1"] || [candidate isEqualToString:@"localhost"]) {
        return YES;
    }
    if ([candidate hasPrefix:@"10."] || [candidate hasPrefix:@"192.168."]) return YES;
    if ([candidate hasPrefix:@"172."]) {
        NSArray<NSString *> *parts = [candidate componentsSeparatedByString:@"."];
        if (parts.count >= 2) {
            NSInteger secondOctet = [parts[1] integerValue];
            if (secondOctet >= 16 && secondOctet <= 31) return YES;
        }
    }
    return NO;
}

static BOOL AppViewOAuthShouldTrustForwardedHeaders(HttpRequest *request) {
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    if (!AppViewOAuthEnvBool(env[@"PDS_TRUST_PROXY_HEADERS"])) return NO;
    return AppViewOAuthIsTrustedProxyRemoteAddress(request.remoteAddress);
}

/// §4.6: build expected DPoP htu from issuer authority; Host / X-Forwarded-*
/// only when local or trusted-proxy.
static NSURL *AppViewOAuthExpectedDPoPURL(HttpRequest *request) {
    NSString *path = request.path ?: @"/";
    if (![path hasPrefix:@"/"]) {
        path = [@"/" stringByAppendingString:path];
    }

    NSString *hostHeader = [[request headerForKey:@"Host"]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *hostLower = [hostHeader lowercaseString];
    BOOL localHost = [hostLower containsString:@"localhost"] ||
                     [hostLower hasPrefix:@"127.0.0.1"] ||
                     [hostLower hasPrefix:@"[::1]"] ||
                     [hostLower isEqualToString:@"::1"];
    BOOL trustForwarded = AppViewOAuthShouldTrustForwardedHeaders(request);

    ATProtoServiceConfiguration *configuration = [ATProtoServiceConfiguration sharedConfiguration];
    NSString *issuer = [configuration canonicalIssuerWithPortHint:0];
    NSURL *issuerURL = [NSURL URLWithString:issuer ?: @""];

    NSString *scheme = nil;
    if (trustForwarded) {
        NSString *forwardedProto = [[request headerForKey:@"X-Forwarded-Proto"] lowercaseString];
        if (forwardedProto.length > 0) {
            NSString *firstProto = [[forwardedProto componentsSeparatedByString:@","] firstObject];
            firstProto = [firstProto stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([firstProto isEqualToString:@"http"] || [firstProto isEqualToString:@"https"]) {
                scheme = firstProto;
            }
        }
    }
    if (scheme.length == 0) {
        if (localHost) {
            scheme = @"http";
        } else if (issuerURL.scheme.length > 0) {
            scheme = issuerURL.scheme;
        } else {
            scheme = @"https";
        }
    }

    NSString *authority = nil;
    if (issuerURL.host.length > 0 && !localHost) {
        authority = issuerURL.host;
        if (issuerURL.port != nil) {
            BOOL isDefaultPort =
                ([issuerURL.scheme.lowercaseString isEqualToString:@"https"] && issuerURL.port.integerValue == 443) ||
                ([issuerURL.scheme.lowercaseString isEqualToString:@"http"] && issuerURL.port.integerValue == 80);
            if (!isDefaultPort) {
                authority = [NSString stringWithFormat:@"%@:%@", issuerURL.host, issuerURL.port];
            }
        }
    } else if (hostHeader.length > 0 && (trustForwarded || localHost)) {
        authority = hostHeader;
    }

    if (authority.length == 0) {
        return nil;
    }

    NSString *urlString = [NSString stringWithFormat:@"%@://%@%@", scheme, authority, path];
    if (request.queryString.length > 0) {
        urlString = [urlString stringByAppendingFormat:@"?%@", request.queryString];
    }
    return [NSURL URLWithString:urlString];
}

@interface AppViewOAuth2Middleware ()

@property (nonatomic, strong) AppViewDatabase *database;
@property (nonatomic, copy, nullable) NSString *masterSecret;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *tokenCache;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t cacheQueue;

@end

@implementation AppViewOAuth2Middleware

- (instancetype)initWithDatabase:(AppViewDatabase *)database
                    masterSecret:(nullable NSString *)masterSecret {
    self = [super init];
    if (self) {
        _database = database;
        _masterSecret = [masterSecret copy];
        _tokenCache = [NSMutableDictionary dictionary];
        _cacheQueue = dispatch_queue_create("com.garazyk.appview.oauth2-cache",
                                            DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (BOOL)validateRequest:(HttpRequest *)request
              callerDID:(NSString *_Nullable *_Nullable)callerDID
                   error:(NSError **)error {
    NSString *token = [self extractBearerToken:request];
    if (!token) {
        if (error) {
            *error = [NSError errorWithDomain:AppViewOAuth2MiddlewareErrorDomain
                                         code:AppViewOAuth2ErrorInvalidToken
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"Missing or invalid Authorization header"
            }];
        }
        return NO;
    }

    // Check if it's a direct DID (for dev/testing)
    for (NSString *prefix in @[@"did:plc:", @"did:web:"]) {
        if ([token hasPrefix:prefix]) {
            if (callerDID) *callerDID = token;
            return YES;
        }
    }

    // Try to parse as JWT
    NSError *jwtError = nil;
    JWT *jwt = [JWT jwtWithToken:token error:&jwtError];
    if (!jwt || !jwt.payload.sub) {
        if (error) {
            *error = [NSError errorWithDomain:AppViewOAuth2MiddlewareErrorDomain
                                         code:AppViewOAuth2ErrorInvalidToken
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"Invalid JWT token"
            }];
        }
        return NO;
    }

    // Check token expiration
    if (jwt.payload.exp) {
        if ([[NSDate date] compare:jwt.payload.exp] == NSOrderedDescending) {
            if (error) {
                *error = [NSError errorWithDomain:AppViewOAuth2MiddlewareErrorDomain
                                             code:AppViewOAuth2ErrorExpiredToken
                                         userInfo:@{
                    NSLocalizedDescriptionKey: @"Token has expired"
                }];
            }
            return NO;
        }
    }

    // Validate DPoP proof if present
    NSString *dpopHeader = [request headerForKey:@"DPoP"];
    NSString *tokenJkt = jwt.payload.cnf[@"jkt"];

    if (dpopHeader.length > 0) {
        // DPoP proof present — must verify proof and check cnf.jkt binding
        NSString *dpopThumbprint = nil;
        if (![self validateDPoPProof:request
                              token:token
                          tokenJkt:tokenJkt
                        outThumbprint:&dpopThumbprint
                             error:error]) {
            return NO;
        }
    } else if (tokenJkt.length > 0) {
        // Token is DPoP-bound but no DPoP proof provided
        if (error) {
            *error = [NSError errorWithDomain:AppViewOAuth2MiddlewareErrorDomain
                                         code:AppViewOAuth2ErrorDPoPKeyMismatch
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"DPoP-bound token requires DPoP proof"
            }];
        }
        return NO;
    }

    if (callerDID) *callerDID = jwt.payload.sub;

    // Cache the validated token
    [self cacheToken:token withDID:jwt.payload.sub];

    return YES;
}

- (nullable NSString *)extractBearerToken:(HttpRequest *)request {
    NSString *authHeader = [request headerForKey:@"Authorization"];
    if (![authHeader hasPrefix:@"Bearer "]) return nil;

    NSString *token = [authHeader substringFromIndex:7];
    return token.length > 0 ? token : nil;
}

- (BOOL)validateDPoPProof:(HttpRequest *)request
                    token:(NSString *)token
                tokenJkt:(nullable NSString *)tokenJkt
           outThumbprint:(NSString *_Nullable *_Nullable)outThumbprint
                   error:(NSError **)error {
    NSString *dpopHeader = [request headerForKey:@"DPoP"];
    if (dpopHeader.length == 0) {
        // No DPoP header — only valid if token is not DPoP-bound (checked by caller)
        return YES;
    }

    // Build the expected DPoP URL from issuer authority (§4.6)
    NSString *method = [request methodString] ?: @"GET";
    NSURL *dpopURL = AppViewOAuthExpectedDPoPURL(request);
    if (!dpopURL) {
        GZ_LOG_AUTH_DEBUG(@"[OAuth2Middleware] Unable to construct DPoP URL");
        if (error) {
            *error = [NSError errorWithDomain:AppViewOAuth2MiddlewareErrorDomain
                                         code:AppViewOAuth2ErrorInvalidDPoPProof
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"Unable to construct DPoP URL"
            }];
        }
        return NO;
    }

    // Verify the DPoP proof using the canonical verifier (RFC 9449)
    NSString *dpopThumbprint = nil;
    NSError *dpopError = nil;
    BOOL validProof = [ATProtoAuthCryptoDPoP verifyProof:dpopHeader
                                           method:method
                                              url:dpopURL
                                            nonce:nil
                                     requireNonce:NO
                                   nonceValidator:nil
                                    replayChecker:[PDSReplayCache sharedCache]
                                    outThumbprint:&dpopThumbprint
                               expectedAccessToken:token
                                            error:&dpopError];

    if (!validProof) {
        GZ_LOG_AUTH_DEBUG(@"[OAuth2Middleware] DPoP proof verification failed: %@",
                           dpopError.localizedDescription ?: @"unknown");
        if (error) {
            *error = [NSError errorWithDomain:AppViewOAuth2MiddlewareErrorDomain
                                         code:AppViewOAuth2ErrorInvalidDPoPProof
                                     userInfo:@{
                NSLocalizedDescriptionKey: dpopError.localizedDescription ?: @"DPoP proof invalid"
            }];
        }
        return NO;
    }

    if (outThumbprint) *outThumbprint = dpopThumbprint;

    // Enforce DPoP binding: cnf.jkt from access token must match proof thumbprint
    if (tokenJkt.length > 0) {
        if (![CryptoUtils constantTimeCompare:tokenJkt to:dpopThumbprint]) {
            GZ_LOG_AUTH_DEBUG(@"[OAuth2Middleware] DPoP thumbprint mismatch");
            if (error) {
                *error = [NSError errorWithDomain:AppViewOAuth2MiddlewareErrorDomain
                                             code:AppViewOAuth2ErrorDPoPKeyMismatch
                                         userInfo:@{
                    NSLocalizedDescriptionKey: @"DPoP proof key does not match token binding"
                }];
            }
            return NO;
        }
    } else {
        // No cnf.jkt on token but DPoP proof provided — accept
        // (token was not DPoP-bound at issuance, but client sent proof anyway)
        GZ_LOG_AUTH_DEBUG(@"[OAuth2Middleware] DPoP proof accepted for non-DPoP-bound token");
    }

    return YES;
}

#pragma mark - Token Cache

- (void)cacheToken:(NSString *)token withDID:(NSString *)did {
    NSDictionary *entry = @{
        @"did": did,
        @"cached_at": @(floor([[NSDate date] timeIntervalSince1970]))
    };

    dispatch_barrier_async(self.cacheQueue, ^{
        self.tokenCache[token] = entry;
    });
}

- (nullable NSString *)cachedDIDForToken:(NSString *)token {
    __block NSString *did = nil;
    dispatch_sync(self.cacheQueue, ^{
        NSDictionary *entry = self.tokenCache[token];
        if (entry) {
            // Check if cache entry is still valid (5 minute TTL)
            NSTimeInterval cachedAt = [entry[@"cached_at"] doubleValue];
            NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
            if (now - cachedAt < 300.0) {
                did = entry[@"did"];
            } else {
                [self.tokenCache removeObjectForKey:token];
            }
        }
    });
    return did;
}

@end
