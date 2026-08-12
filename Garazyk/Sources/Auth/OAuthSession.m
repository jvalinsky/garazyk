// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuthSession.h"
#import "Auth/PKCEUtil.h"
#import "Auth/DPoPUtil.h"
#import "Compat/PDSTypes.h"
#import "Security/PDSSecurityCompare.h"
#import "Security/ATProtoPermissionScopeEvaluator.h"

NSString * const OAuthErrorDomain = @"com.atproto.pds.oauth";

static BOOL OAuthScopeIsValid(NSString *scope) {
    return [ATProtoPermissionScopeEvaluator validateOAuthScopeString:scope];
}

@implementation ATProtoOAuthSession

+ (instancetype)sessionWithId:(NSString *)sessionId {
    ATProtoOAuthSession *session = [[ATProtoOAuthSession alloc] init];
    session.sessionId = sessionId;
    session.createdAt = [NSDate date];
    session.authenticated = NO;
    session.webauthnChallenge = nil;
    session.webauthnChallengeExpiresAt = nil;
    session.webauthnRequired = NO;
    return session;
}

@end

#pragma mark - ATProtoOAuthPARRequest

@implementation ATProtoOAuthPARRequest

- (BOOL)validateWithError:(NSError **)error {
    if (!self.clientId || self.clientId.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:OAuthErrorDomain
                                         code:OAuthErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing client_id"}];
        }
        return NO;
    }

    if (![@"code" isEqualToString:self.responseType]) {
        if (error) {
            *error = [NSError errorWithDomain:OAuthErrorDomain
                                         code:OAuthErrorUnsupportedResponseType
                                     userInfo:@{NSLocalizedDescriptionKey: @"Only code response_type is supported"}];
        }
        return NO;
    }

    if (!self.codeChallenge || self.codeChallenge.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:OAuthErrorDomain
                                         code:OAuthErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing code_challenge"}];
        }
        return NO;
    }

    if (![@"S256" isEqualToString:self.codeChallengeMethod]) {
        if (error) {
            *error = [NSError errorWithDomain:OAuthErrorDomain
                                         code:OAuthErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Only S256 code_challenge_method is supported"}];
        }
        return NO;
    }

    if (!self.state || self.state.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:OAuthErrorDomain
                                         code:OAuthErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing state"}];
        }
        return NO;
    }

    if (!self.redirectUri || self.redirectUri.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:OAuthErrorDomain
                                         code:OAuthErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing redirect_uri"}];
        }
        return NO;
    }

    if (!self.scope || self.scope.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:OAuthErrorDomain
                                         code:OAuthErrorInvalidScope
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing scope"}];
        }
        return NO;
    }

    if (!OAuthScopeIsValid(self.scope)) {
        if (error) {
            *error = [NSError errorWithDomain:OAuthErrorDomain
                                         code:OAuthErrorInvalidScope
                                     userInfo:@{NSLocalizedDescriptionKey: @"A valid atproto scope is required"}];
        }
        return NO;
    }

    return YES;
}

@end

#pragma mark - ATProtoOAuthTokenRequest

@implementation ATProtoOAuthTokenRequest

- (BOOL)validateWithError:(NSError **)error {
    if (!self.grantType || self.grantType.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:OAuthErrorDomain
                                         code:OAuthErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing grant_type"}];
        }
        return NO;
    }

    if (![@"authorization_code" isEqualToString:self.grantType] &&
        ![@"refresh_token" isEqualToString:self.grantType]) {
        if (error) {
            *error = [NSError errorWithDomain:OAuthErrorDomain
                                         code:OAuthErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid grant_type"}];
        }
        return NO;
    }

    if ([@"authorization_code" isEqualToString:self.grantType]) {
        if (!self.code || self.code.length == 0) {
            if (error) {
                *error = [NSError errorWithDomain:OAuthErrorDomain
                                             code:OAuthErrorInvalidRequest
                                         userInfo:@{NSLocalizedDescriptionKey: @"Missing code"}];
            }
            return NO;
        }

        if (!self.redirectUri || self.redirectUri.length == 0) {
            if (error) {
                *error = [NSError errorWithDomain:OAuthErrorDomain
                                             code:OAuthErrorInvalidRequest
                                         userInfo:@{NSLocalizedDescriptionKey: @"Missing redirect_uri"}];
            }
            return NO;
        }
        
        if (!self.codeVerifier || self.codeVerifier.length == 0) {
            if (error) {
                *error = [NSError errorWithDomain:OAuthErrorDomain
                                             code:OAuthErrorInvalidRequest
                                         userInfo:@{NSLocalizedDescriptionKey: @"Missing code_verifier (PKCE is mandated)"}];
            }
            return NO;
        }
    }

    if (!self.dpopJwt || self.dpopJwt.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:OAuthErrorDomain
                                         code:OAuthErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing DPoP token"}];
        }
        return NO;
    }

    return YES;
}

@end

#pragma mark - ATProtoOAuthPARService

@interface ATProtoOAuthPARService ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, ATProtoOAuthSession *> *sessions;
@property (nonatomic, strong) NSMutableDictionary<NSString *, ATProtoOAuthSession *> *authCodes;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t sessionQueue;
@property (nonatomic, copy) NSString *dpopNonce;
@property (nonatomic, strong) NSDate *nonceExpiresAt;

@end

@implementation ATProtoOAuthPARService

- (instancetype)init {
    self = [super init];
    if (self) {
        _sessions = [NSMutableDictionary dictionary];
        _authCodes = [NSMutableDictionary dictionary];
        _sessionQueue = dispatch_queue_create("com.atproto.pds.oauth.par", DISPATCH_QUEUE_SERIAL);
        _dpopNonce = [[NSUUID UUID] UUIDString];
        _nonceExpiresAt = [NSDate dateWithTimeIntervalSinceNow:300];
    }
    return self;
}

- (void)rotateDpopNonce {
    self.dpopNonce = [[NSUUID UUID] UUIDString];
    self.nonceExpiresAt = [NSDate dateWithTimeIntervalSinceNow:300];
}

- (nullable ATProtoOAuthSession *)handlePARRequest:(ATProtoOAuthPARRequest *)request error:(NSError **)error {
    if (![request validateWithError:error]) {
        return nil;
    }

    ATProtoOAuthSession *session = [ATProtoOAuthSession sessionWithId:[[NSUUID UUID] UUIDString]];
    session.clientId = request.clientId;
    session.responseType = request.responseType;
    session.codeChallenge = request.codeChallenge;
    session.state = request.state;
    session.redirectUri = request.redirectUri;
    session.scope = request.scope;
    session.loginHint = request.loginHint;
    session.dpopJwt = request.dpopJwt;
    session.dpopNonce = self.dpopNonce;

    dispatch_sync(self.sessionQueue, ^{
        self.sessions[session.sessionId] = session;
    });

    return session;
}

- (nullable ATProtoOAuthSession *)getSessionByRequestUri:(NSString *)requestUri error:(NSError **)error {
    NSArray<NSString *> *parts = [requestUri componentsSeparatedByString:@"="];
    if (parts.count != 2 || ![parts[0] isEqualToString:@"request_uri"]) {
        if (error) {
            *error = [NSError errorWithDomain:OAuthErrorDomain
                                         code:OAuthErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid request_uri format"}];
        }
        return nil;
    }

    __block ATProtoOAuthSession *session = nil;
    NSString *sessionId = parts[1];

    dispatch_sync(self.sessionQueue, ^{
        session = self.sessions[sessionId];
    });

    if (!session) {
        if (error) {
            *error = [NSError errorWithDomain:OAuthErrorDomain
                                         code:OAuthErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Session not found"}];
        }
        return nil;
    }

    return session;
}

- (nullable NSString *)createAuthorizationCodeForSession:(ATProtoOAuthSession *)session error:(NSError **)error {
    NSString *authCode = [[NSUUID UUID] UUIDString];
    session.authorizationCode = authCode;
    session.codeExpiresAt = [NSDate dateWithTimeIntervalSinceNow:600];

    dispatch_sync(self.sessionQueue, ^{
        self.authCodes[authCode] = session;
    });

    return authCode;
}

- (nullable ATProtoOAuthSession *)sessionForAuthCode:(NSString *)authCode {
    __block ATProtoOAuthSession *session = nil;
    dispatch_sync(self.sessionQueue, ^{
        session = self.authCodes[authCode];
    });
    return session;
}

@end

#pragma mark - ATProtoOAuthTokenService

@interface ATProtoOAuthTokenService ()

@property (nonatomic, strong) ATProtoOAuthPARService *parService;

@end

@implementation ATProtoOAuthTokenService

- (instancetype)init {
    self = [super init];
    if (self) {
        _parService = [[ATProtoOAuthPARService alloc] init];
    }
    return self;
}

- (NSDictionary *)handleTokenRequest:(ATProtoOAuthTokenRequest *)request
                        session:(ATProtoOAuthSession *)session
                          error:(NSError **)error {
    if (![request validateWithError:error]) {
        return @{@"error": @"invalid_request"};
    }

    if ([@"authorization_code" isEqualToString:request.grantType]) {
        return [self processAuthorizationCodeGrant:request session:session error:error];
    } else if ([@"refresh_token" isEqualToString:request.grantType]) {
        return [self processRefreshTokenGrant:request error:error];
    }

    return @{@"error": @"unsupported_grant_type"};
}

- (NSDictionary *)processAuthorizationCodeGrant:(ATProtoOAuthTokenRequest *)request
                                     session:(ATProtoOAuthSession *)session
                                       error:(NSError **)error {
    __block ATProtoOAuthSession *validSession = nil;

    dispatch_sync(self.parService.sessionQueue, ^{
        validSession = self.parService.authCodes[request.code];
    });

    if (!validSession) {
        if (error) {
            *error = [NSError errorWithDomain:OAuthErrorDomain
                                         code:OAuthErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid or expired authorization code"}];
        }
        return @{@"error": @"invalid_grant"};
    }

    if (validSession.codeExpiresAt && [validSession.codeExpiresAt compare:[NSDate date]] == NSOrderedAscending) {
        if (error) {
            *error = [NSError errorWithDomain:OAuthErrorDomain
                                         code:OAuthErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Authorization code expired"}];
        }
        return @{@"error": @"invalid_grant"};
    }

    if (![PDSSecurityCompare constantTimeEqualString:validSession.redirectUri string:request.redirectUri]) {
        if (error) {
            *error = [NSError errorWithDomain:OAuthErrorDomain
                                         code:OAuthErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Redirect URI mismatch"}];
        }
        return @{@"error": @"invalid_grant"};
    }

    if (![ATProtoPKCEUtil verifyCodeChallenge:validSession.codeChallenge withVerifier:request.codeVerifier]) {
        if (error) {
            *error = [NSError errorWithDomain:OAuthErrorDomain
                                         code:OAuthErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid code verifier"}];
        }
        return @{@"error": @"invalid_grant"};
    }

    NSString *accessToken = [[NSUUID UUID] UUIDString];
    NSString *refreshToken = [[NSUUID UUID] UUIDString];

    NSDate *now = [NSDate date];
    NSDate *accessExpires = [now dateByAddingTimeInterval:1800];
    NSDate *refreshExpires = [now dateByAddingTimeInterval:86400 * 180];

    dispatch_sync(self.parService.sessionQueue, ^{
        [self.parService.authCodes removeObjectForKey:request.code];
    });

    return @{
        @"access_token": accessToken,
        @"token_type": @"DPoP",
        @"expires_in": @(1800),
        @"refresh_token": refreshToken,
        @"scope": validSession.scope ?: @"atproto",
        @"sub": validSession.accountDid ?: @"",
        @"dpop_nonce": self.parService.dpopNonce ?: @""
    };
}

- (NSDictionary *)processRefreshTokenGrant:(ATProtoOAuthTokenRequest *)request error:(NSError **)error {
    if (!request.refreshToken || request.refreshToken.length == 0) {
        return @{@"error": @"invalid_request"};
    }

    NSString *accessToken = [[NSUUID UUID] UUIDString];
    NSString *newRefreshToken = [[NSUUID UUID] UUIDString];

    return @{
        @"access_token": accessToken,
        @"token_type": @"DPoP",
        @"expires_in": @(1800),
        @"refresh_token": newRefreshToken,
        @"dpop_nonce": self.parService.dpopNonce ?: @""
    };
}

@end
