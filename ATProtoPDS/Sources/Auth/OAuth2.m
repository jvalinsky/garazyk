#import "Auth/OAuth2.h"
#import "Auth/Session.h"
#import "Auth/KeyManager.h"
#import "Auth/JWT.h"
#import "Auth/Secp256k1.h"
#import "Core/DID.h"
#import "Identity/HandleResolver.h"
#import "Database/PDSDatabase.h"
#import "Auth/TOTPService.h"
#import "Auth/Base32Utils.h"
#import <os/log.h>

NSString * const OAuth2ScopeIdentify = @"atproto:identify";
NSString * const OAuth2ScopeSignIn = @"atproto:signin";
NSString * const OAuth2ScopeRepoWrite = @"atproto:repo_write";
NSString * const OAuth2ScopeRepoRead = @"atproto:repo_read";
NSString * const OAuth2ScopeAtprotoProfile = @"atproto:profile";

NSString * const OAuth2ErrorDomain = @"com.atproto.pds.oauth2";

static NSString * const kAuthorizationCodeKey = @"authorization_code";
static NSString * const kRefreshTokenKey = @"refresh_token";

@interface OAuth2Server ()
@end

@implementation OAuth2AuthorizationRequest

- (NSURL *)authorizationURL {
    NSURLComponents *components = [NSURLComponents componentsWithString:@"/oauth/authorize"];
    NSMutableArray<NSURLQueryItem *> *queryItems = [NSMutableArray array];
    if (self.clientID) [queryItems addObject:[NSURLQueryItem queryItemWithName:@"client_id" value:self.clientID]];
    if (self.redirectURI) [queryItems addObject:[NSURLQueryItem queryItemWithName:@"redirect_uri" value:self.redirectURI]];
    if (self.responseType) [queryItems addObject:[NSURLQueryItem queryItemWithName:@"response_type" value:self.responseType]];
    if (self.scope) [queryItems addObject:[NSURLQueryItem queryItemWithName:@"scope" value:self.scope]];
    if (self.state) [queryItems addObject:[NSURLQueryItem queryItemWithName:@"state" value:self.state]];
    if (self.codeChallenge) [queryItems addObject:[NSURLQueryItem queryItemWithName:@"code_challenge" value:self.codeChallenge]];
    if (self.codeChallengeMethod) [queryItems addObject:[NSURLQueryItem queryItemWithName:@"code_challenge_method" value:self.codeChallengeMethod]];
    if (self.nonce) [queryItems addObject:[NSURLQueryItem queryItemWithName:@"nonce" value:self.nonce]];
    components.queryItems = queryItems;
    return components.URL;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"client_id"] = self.clientID;
    if (self.redirectURI) dict[@"redirect_uri"] = self.redirectURI;
    if (self.responseType) dict[@"response_type"] = self.responseType;
    if (self.scope) dict[@"scope"] = self.scope;
    if (self.state) dict[@"state"] = self.state;
    if (self.codeChallenge) dict[@"code_challenge"] = self.codeChallenge;
    if (self.codeChallengeMethod) dict[@"code_challenge_method"] = self.codeChallengeMethod;
    if (self.nonce) dict[@"nonce"] = self.nonce;
    if (self.dpopJWK) dict[@"dpop_jwk"] = self.dpopJWK;
    return dict;
}

@end

@implementation OAuth2AuthorizationResponse

+ (nullable instancetype)responseFromURL:(NSURL *)url expectedState:(nullable NSString *)state error:(NSError **)error {
    OAuth2AuthorizationResponse *response = [[OAuth2AuthorizationResponse alloc] init];
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSMutableDictionary<NSString *, NSString *> *params = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in components.queryItems) {
        params[item.name] = item.value;
    }

    response.code = params[@"code"];
    response.state = params[@"state"];
    response.error = params[@"error"];
    response.errorDescription = params[@"error_description"];

    NSString *errorParam = params[@"error"];
    if (errorParam) {
        OAuth2Error errorCode = OAuth2ErrorInvalidRequest;
        if ([errorParam isEqualToString:@"invalid_request"]) errorCode = OAuth2ErrorInvalidRequest;
        else if ([errorParam isEqualToString:@"unauthorized_client"]) errorCode = OAuth2ErrorUnauthorizedClient;
        else if ([errorParam isEqualToString:@"access_denied"]) errorCode = OAuth2ErrorAccessDenied;
        else if ([errorParam isEqualToString:@"unsupported_response_type"]) errorCode = OAuth2ErrorUnsupportedResponseType;
        else if ([errorParam isEqualToString:@"invalid_scope"]) errorCode = OAuth2ErrorInvalidScope;
        else if ([errorParam isEqualToString:@"server_error"]) errorCode = OAuth2ErrorServerError;
        else if ([errorParam isEqualToString:@"temporarily_unavailable"]) errorCode = OAuth2ErrorTemporarilyUnavailable;
        else if ([errorParam isEqualToString:@"interaction_required"]) errorCode = OAuth2ErrorInteractionRequired;
        else if ([errorParam isEqualToString:@"consent_required"]) errorCode = OAuth2ErrorConsentRequired;

        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:errorCode
                                     userInfo:@{
                NSLocalizedDescriptionKey: response.errorDescription ?: errorParam,
                @"error": errorParam
            }];
        }
        return nil;
    }

    if (!response.code) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidGrant
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing authorization code"}];
        }
        return nil;
    }

    if (state && ![response.state isEqualToString:state]) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"State mismatch"}];
        }
        return nil;
    }

    return response;
}

@end

@implementation OAuth2TokenRequest

- (NSDictionary *)toFormData {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"grant_type"] = self.grantType;
    if (self.code) dict[@"code"] = self.code;
    if (self.redirectURI) dict[@"redirect_uri"] = self.redirectURI;
    if (self.clientID) dict[@"client_id"] = self.clientID;
    if (self.codeVerifier) dict[@"code_verifier"] = self.codeVerifier;
    if (self.refreshToken) dict[@"refresh_token"] = self.refreshToken;
    if (self.accessToken) dict[@"access_token"] = self.accessToken;
    if (self.dpopProof) dict[@"dpop"] = self.dpopProof;
    if (self.scope) dict[@"scope"] = self.scope;
    if (self.tfaCode) dict[@"tfa_code"] = self.tfaCode;
    return dict;
}

@end

@implementation OAuth2TokenResponse

+ (nullable instancetype)responseFromDictionary:(NSDictionary *)dictionary error:(NSError **)error {
    OAuth2TokenResponse *response = [[OAuth2TokenResponse alloc] init];
    response.accessToken = dictionary[@"access_token"];
    response.tokenType = dictionary[@"token_type"] ?: @"Bearer";
    response.refreshToken = dictionary[@"refresh_token"];
    response.scope = dictionary[@"scope"];

    id expiresIn = dictionary[@"expires_in"];
    if ([expiresIn isKindOfClass:[NSNumber class]]) {
        response.expiresIn = [expiresIn doubleValue];
    } else if ([expiresIn isKindOfClass:[NSString class]]) {
        response.expiresIn = [expiresIn doubleValue];
    } else {
        response.expiresIn = 3600;
    }

    response.dpopKeyThumbprint = dictionary[@"dpop_key_thumbprint"];

    if (!response.accessToken) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidGrant
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing access token"}];
        }
        return nil;
    }

    return response;
}

@end

@implementation OAuth2DPoPProof

+ (nullable NSString *)createProofForURL:(NSURL *)url
                                method:(NSString *)method
                                  key:(NSDictionary *)jwk
                                 error:(NSError **)error {
    NSMutableDictionary *proof = [NSMutableDictionary dictionary];
    proof[@"typ"] = @"dpop+jwt";
    proof[@"alg"] = @"RS256";

    NSMutableDictionary *header = [NSMutableDictionary dictionary];
    header[@"typ"] = @"dpop+jwt";
    header[@"alg"] = @"RS256";
    if (jwk[@"kid"]) header[@"kid"] = jwk[@"kid"];

    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:error];
    if (!headerData) return nil;

    NSString *headerEncoded = [JWT base64URLEncodeData:headerData error:error];
    if (!headerEncoded) return nil;

    NSDateFormatter *isoFormatter = [[NSDateFormatter alloc] init];
    isoFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    isoFormatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];

    NSMutableDictionary *claims = [NSMutableDictionary dictionary];
    claims[@"jti"] = [[NSUUID UUID] UUIDString];
    claims[@"htm"] = method;
    claims[@"htu"] = url.absoluteString;
    claims[@"iat"] = @([[NSDate date] timeIntervalSince1970]);

    NSData *claimsData = [NSJSONSerialization dataWithJSONObject:claims options:0 error:error];
    if (!claimsData) return nil;

    NSString *claimsEncoded = [JWT base64URLEncodeData:claimsData error:error];
    if (!claimsEncoded) return nil;

    return [NSString stringWithFormat:@"%@.%@.stub", headerEncoded, claimsEncoded];
}

@end

@implementation OAuth2Server

- (instancetype)init {
    self = [super init];
    if (self) {
        _authorizationCodes = [NSMutableDictionary dictionary];
        _activeSessions = [NSMutableDictionary dictionary];
        _jwtMinter = [[JWTMinter alloc] init];
        _keyManager = [[KeyManager alloc] init];
        _didResolver = [[DIDResolver alloc] init];
        _handleResolver = [[HandleResolver alloc] init];
        // Initialize with default database location for now (should be injected preferably)
        NSURL *dbURL = [[NSURL fileURLWithPath:NSHomeDirectory()] URLByAppendingPathComponent:@".gemini/pds.db"];
        _database = [PDSDatabase databaseAtURL:dbURL];
        [_database openWithError:nil];

        // Generate Secp256k1 key pair for JWT signing
        NSError *keyError;
        Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:&keyError];
        if (keyPair) {
            _jwtMinter.privateKey = keyPair.privateKey;
        } else {
            NSLog(@"Failed to generate JWT signing key: %@", keyError);
        }
    }
    return self;
}

- (void)handleAuthorizationRequest:(OAuth2AuthorizationRequest *)request
                        completion:(OAuth2AuthorizationCompletion)completion {
    if (!request.clientID || !request.redirectURI || !request.responseType) {
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidRequest
                                         userInfo:@{NSLocalizedDescriptionKey: @"Missing required parameters"}];
        completion(nil, nil, error);
        return;
    }

    if (![request.responseType isEqualToString:@"code"]) {
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorUnsupportedResponseType
                                         userInfo:@{NSLocalizedDescriptionKey: @"Only 'code' response type is supported"}];
        completion(nil, nil, error);
        return;
    }

    NSString *code = [[NSUUID UUID] UUIDString];
    NSMutableDictionary *codeData = [NSMutableDictionary dictionary];
    codeData[@"client_id"] = request.clientID;
    codeData[@"redirect_uri"] = request.redirectURI;
    if (request.scope) codeData[@"scope"] = request.scope;
    if (request.state) codeData[@"state"] = request.state;
    if (request.codeChallenge) codeData[@"code_challenge"] = request.codeChallenge;
    if (request.codeChallengeMethod) codeData[@"code_challenge_method"] = request.codeChallengeMethod;
    if (request.nonce) codeData[@"nonce"] = request.nonce;
    if (request.dpopJWK) codeData[@"dpop_jwk"] = request.dpopJWK;
    if (request.loginHint) codeData[@"login_hint"] = request.loginHint; // Ensure we store this
    codeData[@"created_at"] = @([[NSDate date] timeIntervalSince1970]);

    // ATProto: Resolve identity if login_hint provided
    if (request.loginHint) {
        NSString *resolvedDID = [self resolveIdentity:request.loginHint error:nil];
        if (resolvedDID) {
            codeData[@"login_hint_did"] = resolvedDID;
            codeData[@"login_hint_original"] = request.loginHint;
            os_log_info(OS_LOG_DEFAULT, "OAuth2: Resolved login_hint %{public}@ to DID %{public}@", request.loginHint, resolvedDID);
        } else {
            os_log_error(OS_LOG_DEFAULT, "OAuth2: Failed to resolve login_hint %{public}@", request.loginHint);
            // Continue without resolved identity - authorization server will handle
        }
    }

    self.authorizationCodes[code] = codeData;

    NSMutableString *authURL = [request.authorizationURL.absoluteString mutableCopy];
    NSString *separator = [authURL containsString:@"?"] ? @"&" : @"?";
    [authURL appendFormat:@"%@code=%@", separator, code];

    completion([NSURL URLWithString:authURL], code, nil);
}

- (void)handleTokenRequest:(OAuth2TokenRequest *)request
                completion:(OAuth2TokenCompletion)completion {
    if ([request.grantType isEqualToString:@"authorization_code"]) {
        [self processAuthorizationCodeGrant:request completion:completion];
    } else if ([request.grantType isEqualToString:@"refresh_token"]) {
        [self processRefreshTokenGrant:request completion:completion];
    } else if ([request.grantType isEqualToString:@"urn:ietf:params:oauth:grant-type:dpop"]) {
        [self processDPoPGrant:request completion:completion];
    } else {
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorUnsupportedGrantType
                                         userInfo:@{NSLocalizedDescriptionKey: @"Unsupported grant type"}];
        completion(nil, error);
    }
}

- (void)processAuthorizationCodeGrant:(OAuth2TokenRequest *)request
                          completion:(OAuth2TokenCompletion)completion {
    NSDictionary *codeData = self.authorizationCodes[request.code];
    if (!codeData) {
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidGrant
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid or expired authorization code"}];
        completion(nil, error);
        return;
    }

    NSTimeInterval codeAge = [[NSDate date] timeIntervalSince1970] - [codeData[@"created_at"] doubleValue];
    if (codeAge > 600) {
        [self.authorizationCodes removeObjectForKey:request.code];
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidGrant
                                         userInfo:@{NSLocalizedDescriptionKey: @"Authorization code expired"}];
        completion(nil, error);
        return;
    }

    if (![codeData[@"client_id"] isEqualToString:request.clientID]) {
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidGrant
                                         userInfo:@{NSLocalizedDescriptionKey: @"Client ID mismatch"}];
        completion(nil, error);
        return;
    }

    if (request.codeVerifier && codeData[@"code_challenge"]) {
        NSString *expectedChallenge = codeData[@"code_challenge"];
        NSString *method = codeData[@"code_challenge_method"] ?: @"plain";

        if (![self verifyCodeVerifier:request.codeVerifier challenge:expectedChallenge method:method]) {
            NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                                 code:OAuth2ErrorInvalidGrant
                                             userInfo:@{NSLocalizedDescriptionKey: @"Invalid code verifier"}];
            completion(nil, error);
            return;
        }
    }

    [self.authorizationCodes removeObjectForKey:request.code];

    NSString *did = @"did:plc:stub-user-placeholder"; // In real usage, this comes from the codeData or is resolved
    if (codeData[@"login_hint_did"]) {
        did = codeData[@"login_hint_did"];
    }
    
    // Check 2FA Status
    NSError *dbError = nil;
    PDSDatabaseAccount *account = [self.database getAccountByDid:did error:&dbError];
    
    if (account && account.tfaEnabled) {
        if (!request.tfaCode) {
             NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                                  code:OAuth2ErrorInteractionRequired
                                              userInfo:@{NSLocalizedDescriptionKey: @"Two-factor authentication code required", @"error": @"mfa_required"}];
             completion(nil, error);
             return;
        }
        
        // Verify Code
        NSString *secret = [Base32Utils base32StringFromData:account.tfaSecret];
        BOOL valid = [TOTPService verifyCode:request.tfaCode secret:secret];
        if (!valid) {
            NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                                  code:OAuth2ErrorInvalidGrant
                                              userInfo:@{NSLocalizedDescriptionKey: @"Invalid 2FA code"}];
            completion(nil, error);
            return;
        }
    }

    NSString *handle = account.handle ?: @"handle.placeholder";
    NSString *scope = codeData[@"scope"] ?: OAuth2ScopeIdentify;

    Session *session = [self createSessionForDID:did handle:handle scope:scope dpopJWK:codeData[@"dpop_jwk"]];

    completion(session, nil);
}

- (void)processRefreshTokenGrant:(OAuth2TokenRequest *)request
                      completion:(OAuth2TokenCompletion)completion {
    Session *existingSession = nil;
    for (Session *session in self.activeSessions.allValues) {
        if ([session.refreshToken isEqualToString:request.refreshToken]) {
            existingSession = session;
            break;
        }
    }

    if (!existingSession) {
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidGrant
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid refresh token"}];
        completion(nil, error);
        return;
    }

    if ([existingSession.refreshTokenExpiresAt compare:[NSDate date]] == NSOrderedAscending) {
        [self.activeSessions removeObjectForKey:existingSession.sessionID];
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorTokenExpired
                                         userInfo:@{NSLocalizedDescriptionKey: @"Refresh token expired"}];
        completion(nil, error);
        return;
    }

    NSString *newScope = request.scope ?: existingSession.scope;
    Session *newSession = [self createSessionForDID:existingSession.did
                                             handle:existingSession.handle
                                              scope:newScope
                                            dpopJWK:nil];

    [self.activeSessions removeObjectForKey:existingSession.sessionID];

    completion(newSession, nil);
}

- (void)processDPoPGrant:(OAuth2TokenRequest *)request
              completion:(OAuth2TokenCompletion)completion {
    if (!request.accessToken) {
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidRequest
                                         userInfo:@{NSLocalizedDescriptionKey: @"Missing access token in DPoP request"}];
        completion(nil, error);
        return;
    }

    Session *session = [self createSessionForDID:@"did:plc:stub-dpop-user"
                                          handle:@"dpop.handle"
                                           scope:OAuth2ScopeIdentify
                                         dpopJWK:nil];
    completion(session, nil);
}

- (Session *)createSessionForDID:(NSString *)did
                          handle:(NSString *)handle
                           scope:(NSString *)scope
                         dpopJWK:(nullable NSString *)dpopJWK {
    Session *session = [[Session alloc] initWithDID:did
                                             handle:handle
                                              scope:scope
                                             minter:self.jwtMinter];

    if (dpopJWK) {
        session.dpopKeyThumbprint = dpopJWK;
    }

    self.activeSessions[session.sessionID] = session;

    return session;
}

- (BOOL)verifyCodeVerifier:(NSString *)verifier challenge:(NSString *)challenge method:(NSString *)method {
    if ([method isEqualToString:@"plain"]) {
        return [verifier isEqualToString:challenge];
    }
    return NO;
}

- (void)refreshAccessToken:(NSString *)refreshToken
                     scope:(nullable NSString *)scope
                   dpopJWK:(nullable NSDictionary *)dpopJWK
                completion:(OAuth2RefreshCompletion)completion {
    // Find session with this refresh token
    Session *foundSession = nil;
    for (Session *session in self.activeSessions.allValues) {
        if ([session.refreshToken isEqualToString:refreshToken]) {
            foundSession = session;
            break;
        }
    }
    
    if (!foundSession) {
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidGrant
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid refresh token"}];
        completion(nil, error);
        return;
    }
    
    // Check if refresh token is expired (assuming 30 days for now)
    if ([foundSession.createdAt timeIntervalSinceNow] < -30 * 24 * 60 * 60) {
        [self.activeSessions removeObjectForKey:foundSession.sessionID];
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidGrant
                                         userInfo:@{NSLocalizedDescriptionKey: @"Refresh token expired"}];
        completion(nil, error);
        return;
    }
    
    // Issue new access token
    NSString *newAccessToken = [foundSession refreshAccessToken];
    
    if (completion) {
        completion(newAccessToken, nil);
    }
}

#pragma mark - ATProto Identity Resolution

- (nullable NSString *)resolveIdentity:(NSString *)identity error:(NSError **)error {
    if (!identity || identity.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Empty identity"}];
        }
        return nil;
    }

    // Check if it's already a DID
    if ([identity hasPrefix:@"did:"]) {
        // Validate DID format and resolve to ensure it exists
        DIDDocument *doc = [self.didResolver resolveDIDSync:identity error:error];
        return doc ? identity : nil;
    } else {
        // It's a handle - resolve to DID
        __block NSString *resolvedDID = nil;
        __block NSError *resolveError = nil;

        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

        [self.handleResolver resolveHandle:identity completion:^(NSString * _Nullable did, NSError * _Nullable err) {
            resolvedDID = did;
            resolveError = err;
            dispatch_semaphore_signal(semaphore);
        }];

        dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));

        if (resolveError) {
            if (error) *error = resolveError;
            return nil;
        }

        // Verify bidirectional resolution (ATProto requirement)
        if (resolvedDID) {
            NSDictionary *atprotoData = [self.didResolver resolveAtprotoDataForDID:resolvedDID error:error];
            NSString *verifiedHandle = atprotoData[@"handle"];

            if (verifiedHandle && ![verifiedHandle isEqualToString:identity]) {
                os_log_error(OS_LOG_DEFAULT, "OAuth2: Handle verification failed - provided %{public}@, resolved %{public}@", identity, verifiedHandle);
                if (error) {
                    *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                                 code:OAuth2ErrorInvalidRequest
                                             userInfo:@{NSLocalizedDescriptionKey: @"Handle verification failed"}];
                }
                return nil;
            }
        }

        return resolvedDID;
    }
}

@end
