/*!
 @file OAuthProvider.m

 @abstract OAuthProvider Authorization Server implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "Auth/OAuthProvider/OAuthProvider.h"
#import "Auth/Crypto/AuthCryptoDPoP.h"
#import "Auth/Crypto/AuthCryptoJWK.h"
#import "Auth/Crypto/AuthCryptoBase64URL.h"
#import "Debug/PDSLogger.h"
#import <CommonCrypto/CommonDigest.h>

NSString * const OAuthProviderErrorDomain = @"com.atproto.oauthprovider";

#pragma mark - OAuthProviderAuthorizationRequest

@implementation OAuthProviderAuthorizationRequest
@end

#pragma mark - OAuthProviderAuthorizationResponse

@implementation OAuthProviderAuthorizationResponse
@end

#pragma mark - OAuthProviderTokenRequest

@implementation OAuthProviderTokenRequest
@end

#pragma mark - OAuthProviderTokenResponse

@implementation OAuthProviderTokenResponse
@end

#pragma mark - OAuthProviderClientMetadata

@implementation OAuthProviderClientMetadata

+ (nullable instancetype)metadataFromDictionary:(NSDictionary *)dict error:(NSError **)error {
    OAuthProviderClientMetadata *metadata = [[OAuthProviderClientMetadata alloc] init];
    metadata.clientID = dict[@"client_id"];
    metadata.redirectURIs = dict[@"redirect_uris"];
    metadata.clientName = dict[@"client_name"];
    metadata.clientURI = dict[@"client_uri"];
    metadata.logoURI = dict[@"logo_uri"];
    metadata.tosURI = dict[@"tos_uri"];
    metadata.policyURI = dict[@"policy_uri"];
    metadata.jwksURI = dict[@"jwks_uri"];
    metadata.jwks = dict[@"jwks"];
    metadata.tokenEndpointAuthMethod = dict[@"token_endpoint_auth_method"];
    metadata.grantTypes = dict[@"grant_types"];
    metadata.responseTypes = dict[@"response_types"];
    metadata.contacts = dict[@"contacts"];
    metadata.softwareID = dict[@"software_id"];
    metadata.softwareVersion = dict[@"software_version"];

    if (!metadata.clientID || !metadata.redirectURIs) {
        if (error) {
            *error = [NSError errorWithDomain:OAuthProviderErrorDomain
                                         code:OAuthProviderErrorInvalidClient
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required client_metadata fields"}];
        }
        return nil;
    }

    return metadata;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"client_id"] = self.clientID;
    dict[@"redirect_uris"] = self.redirectURIs;
    if (self.clientName) dict[@"client_name"] = self.clientName;
    if (self.clientURI) dict[@"client_uri"] = self.clientURI;
    if (self.logoURI) dict[@"logo_uri"] = self.logoURI;
    if (self.tosURI) dict[@"tos_uri"] = self.tosURI;
    if (self.policyURI) dict[@"policy_uri"] = self.policyURI;
    if (self.jwksURI) dict[@"jwks_uri"] = self.jwksURI;
    if (self.jwks) dict[@"jwks"] = self.jwks;
    dict[@"token_endpoint_auth_method"] = self.tokenEndpointAuthMethod;
    if (self.grantTypes) dict[@"grant_types"] = self.grantTypes;
    if (self.responseTypes) dict[@"response_types"] = self.responseTypes;
    if (self.contacts) dict[@"contacts"] = self.contacts;
    if (self.softwareID) dict[@"software_id"] = self.softwareID;
    if (self.softwareVersion) dict[@"software_version"] = self.softwareVersion;
    return dict;
}

@end

#pragma mark - OAuthProviderServer

@interface OAuthProviderServer ()
@property (nonatomic, strong) id<OAuthProviderStorage> storage;
@property (nonatomic, strong) id<OAuthProviderClientRegistry> clientRegistry;
@property (nonatomic, strong) id<OAuthProviderTokenSigner> tokenSigner;
@property (nonatomic, strong) id<OAuthProviderUserAuthenticator> userAuthenticator;
@property (nonatomic, strong, nullable) id<OAuthProviderDIDResolver> didResolver;
@property (nonatomic, strong, nullable) id<OAuthProviderHandleResolver> handleResolver;
@property (nonatomic, assign) dispatch_queue_t parQueue;
@property (nonatomic, assign) dispatch_queue_t tokenQueue;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *inMemoryPARs;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *inMemoryCodes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *inMemoryRefreshTokens;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *inMemoryConsents;
@property (nonatomic, assign) NSTimeInterval parExpiresIn;
@property (nonatomic, assign) NSTimeInterval authCodeExpiresIn;
@end

@implementation OAuthProviderServer

- (instancetype)initWithStorage:(id<OAuthProviderStorage>)storage
                 clientRegistry:(id<OAuthProviderClientRegistry>)clientRegistry
                   tokenSigner:(id<OAuthProviderTokenSigner>)tokenSigner
             userAuthenticator:(id<OAuthProviderUserAuthenticator>)userAuthenticator
                   didResolver:(nullable id<OAuthProviderDIDResolver>)didResolver
               handleResolver:(nullable id<OAuthProviderHandleResolver>)handleResolver {
    self = [super init];
    if (self) {
        _storage = storage;
        _clientRegistry = clientRegistry;
        _tokenSigner = tokenSigner;
        _userAuthenticator = userAuthenticator;
        _didResolver = didResolver;
        _handleResolver = handleResolver;

        _parQueue = dispatch_queue_create("com.atproto.oauthprovider.par", DISPATCH_QUEUE_SERIAL);
        _tokenQueue = dispatch_queue_create("com.atproto.oauthprovider.token", DISPATCH_QUEUE_SERIAL);
        _parExpiresIn = 60;
        _authCodeExpiresIn = 600;

        _supportedTokenEndpointAuthMethods = @[
            @"none",
            @"client_secret_post",
            @"client_secret_basic",
            @"private_key_jwt"
        ];

        if (!storage) {
            _inMemoryPARs = [NSMutableDictionary dictionary];
            _inMemoryCodes = [NSMutableDictionary dictionary];
            _inMemoryRefreshTokens = [NSMutableDictionary dictionary];
            _inMemoryConsents = [NSMutableDictionary dictionary];
        }
    }
    return self;
}

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

#pragma mark - PAR

- (void)processPAR:(NSDictionary *)requestData
        completion:(void (^)(NSString * _Nullable, NSDate * _Nullable, NSError * _Nullable))completion {
    NSString *clientID = requestData[@"client_id"];
    NSString *responseType = requestData[@"response_type"];
    NSString *redirectURI = requestData[@"redirect_uri"];

    if (!clientID || !responseType) {
        completion(nil, nil, [self errorWithCode:OAuthProviderErrorInvalidRequest
                                     description:@"Missing required parameters"]);
        return;
    }

    if (![responseType isEqualToString:@"code"]) {
        completion(nil, nil, [self errorWithCode:OAuthProviderErrorUnsupportedResponseType
                                     description:@"Only 'code' response type supported"]);
        return;
    }

    NSError *clientError = nil;
    NSDictionary *client = [self.clientRegistry getClientByID:clientID error:&clientError];
    if (!client) {
        completion(nil, nil, clientError ?: [self errorWithCode:OAuthProviderErrorInvalidClient
                                                     description:@"Unknown client"]);
        return;
    }

    if (redirectURI) {
        if (![self.clientRegistry validateRedirectURI:redirectURI forClient:client error:&clientError]) {
            completion(nil, nil, clientError ?: [self errorWithCode:OAuthProviderErrorInvalidRedirectURI
                                                     description:@"Invalid redirect_uri"]);
            return;
        }
    }

    NSMutableDictionary *parData = [requestData mutableCopy];
    parData[@"created_at"] = @([[NSDate date] timeIntervalSince1970]);

    NSString *requestURI = [NSString stringWithFormat:@"urn:ietf:params:oauth:request_uri:%@", [[NSUUID UUID] UUIDString]];
    NSDate *expiresAt = [NSDate dateWithTimeIntervalSinceNow:self.parExpiresIn];

    if (self.storage) {
        NSError *storeError = nil;
        BOOL success = [self.storage storePAR:parData forRequestURI:requestURI expiresAt:expiresAt error:&storeError];
        if (!success) {
            completion(nil, nil, storeError ?: [self errorWithCode:OAuthProviderErrorServerError
                                                      description:@"Failed to store PAR"]);
            return;
        }
    } else {
        dispatch_sync(self.parQueue, ^{
            self.inMemoryPARs[requestURI] = [@{@"data": parData, @"expires": expiresAt} mutableCopy];
        });
    }

    NSDate *expiresIn = expiresAt;
    PDS_LOG_AUTH_DEBUG(@"PAR created: request_uri=%@", requestURI);
    completion(requestURI, expiresIn, nil);
}

#pragma mark - Authorization

- (void)processAuthorizationRequest:(OAuthProviderAuthorizationRequest *)request
                         completion:(OAuthProviderAuthorizationCompletion)completion {
    if (!request.clientID || !request.redirectURI || !request.responseType) {
        completion(nil, nil, [self errorWithCode:OAuthProviderErrorInvalidRequest
                                     description:@"Missing required parameters"]);
        return;
    }

    if (![request.responseType isEqualToString:@"code"]) {
        completion(nil, nil, [self errorWithCode:OAuthProviderErrorUnsupportedResponseType
                                     description:@"Only 'code' response type supported"]);
        return;
    }

    NSError *clientError = nil;
    NSDictionary *client = [self.clientRegistry getClientByID:request.clientID error:&clientError];
    if (!client) {
        completion(nil, nil, clientError ?: [self errorWithCode:OAuthProviderErrorInvalidClient
                                                     description:@"Unknown client"]);
        return;
    }

    if (![self.clientRegistry validateRedirectURI:request.redirectURI forClient:client error:&clientError]) {
        completion(nil, nil, clientError ?: [self errorWithCode:OAuthProviderErrorInvalidRedirectURI
                                                     description:@"Invalid redirect_uri"]);
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
    if (request.loginHint) {
        codeData[@"login_hint"] = request.loginHint;
        if (self.handleResolver) {
            NSError *resolveError = nil;
            NSString *did = [self.handleResolver resolveHandle:request.loginHint error:&resolveError];
            if (did) {
                codeData[@"login_hint_did"] = did;
            }
        }
    }
    codeData[@"created_at"] = @([[NSDate date] timeIntervalSince1970]);

    NSDate *expiresAt = [NSDate dateWithTimeIntervalSinceNow:self.authCodeExpiresIn];

    if (self.storage) {
        NSError *storeError = nil;
        [self.storage storeAuthCode:code data:codeData expiresAt:expiresAt error:&storeError];
    } else {
        dispatch_sync(self.parQueue, ^{
            self.inMemoryCodes[code] = [@{@"data": codeData, @"expires": expiresAt} mutableCopy];
        });
    }

    PDS_LOG_AUTH_DEBUG(@"Authorization code created: code=%@ client_id=%@", code, request.clientID);

    NSURLComponents *redirectComponents = [NSURLComponents componentsWithString:request.redirectURI];
    NSMutableArray<NSURLQueryItem *> *queryItems = [redirectComponents.queryItems mutableCopy] ?: [NSMutableArray array];
    [queryItems addObject:[NSURLQueryItem queryItemWithName:@"code" value:code]];
    if (request.state) {
        [queryItems addObject:[NSURLQueryItem queryItemWithName:@"state" value:request.state]];
    }
    if (self.issuer.length > 0) {
        [queryItems addObject:[NSURLQueryItem queryItemWithName:@"iss" value:self.issuer]];
    }
    redirectComponents.queryItems = queryItems;

    completion(redirectComponents.URL, code, nil);
}

#pragma mark - Token

- (void)processTokenRequest:(OAuthProviderTokenRequest *)request
                  completion:(OAuthProviderTokenCompletion)completion {
    if (!request.grantType) {
        completion(nil, [self errorWithCode:OAuthProviderErrorInvalidRequest
                               description:@"Missing grant_type"]);
        return;
    }

    if ([request.grantType isEqualToString:@"authorization_code"]) {
        [self processAuthorizationCodeGrant:request completion:completion];
    } else if ([request.grantType isEqualToString:@"refresh_token"]) {
        [self processRefreshTokenGrant:request completion:completion];
    } else if ([request.grantType isEqualToString:@"client_credentials"]) {
        [self processClientCredentialsGrant:request completion:completion];
    } else {
        completion(nil, [self errorWithCode:OAuthProviderErrorUnsupportedGrantType
                               description:@"Unsupported grant_type"]);
    }
}

- (void)processAuthorizationCodeGrant:(OAuthProviderTokenRequest *)request
                           completion:(OAuthProviderTokenCompletion)completion {
    NSString *code = request.authorizationCode;
    NSString *redirectURI = request.redirectURI;
    NSString *codeVerifier = request.codeVerifier;
    NSString *clientID = request.clientID;
    NSString *dpopProof = request.dpopProof;

    if (!code || !redirectURI) {
        completion(nil, [self errorWithCode:OAuthProviderErrorInvalidGrant
                               description:@"Missing authorization code or redirect_uri"]);
        return;
    }

    NSError *consumeError = nil;
    __block NSDictionary *codeData;
    if (self.storage) {
        codeData = [self.storage consumeAuthCode:code error:&consumeError];
    } else {
        dispatch_sync(self.tokenQueue, ^{
            NSMutableDictionary *stored = self.inMemoryCodes[code];
            if (stored) {
                NSDate *expires = stored[@"expires"];
                if ([expires compare:[NSDate date]] == NSOrderedDescending) {
                    codeData = [stored[@"data"] copy];
                }
                [self.inMemoryCodes removeObjectForKey:code];
            }
        });
    }

    if (!codeData) {
        completion(nil, consumeError ?: [self errorWithCode:OAuthProviderErrorInvalidGrant
                                               description:@"Invalid or expired authorization code"]);
        return;
    }

    if (![codeData[@"redirect_uri"] isEqualToString:redirectURI]) {
        completion(nil, [self errorWithCode:OAuthProviderErrorInvalidGrant
                               description:@"redirect_uri mismatch"]);
        return;
    }

    if (clientID && ![codeData[@"client_id"] isEqualToString:clientID]) {
        completion(nil, [self errorWithCode:OAuthProviderErrorInvalidClient
                               description:@"client_id mismatch"]);
        return;
    }

    NSString *codeChallenge = codeData[@"code_challenge"];
    NSString *codeChallengeMethod = codeData[@"code_challenge_method"];
    if (codeChallenge) {
        if (!codeVerifier) {
            completion(nil, [self errorWithCode:OAuthProviderErrorInvalidGrant
                                   description:@"Missing code_verifier for PKCE"]);
            return;
        }
        if (![self verifyPKCE:codeVerifier challenge:codeChallenge method:codeChallengeMethod]) {
            completion(nil, [self errorWithCode:OAuthProviderErrorInvalidGrant
                                   description:@"Invalid code_verifier"]);
            return;
        }
    }

    NSString *sub = codeData[@"login_hint_did"];
    NSString *scope = codeData[@"scope"];
    NSDictionary *dpopJWK = codeData[@"dpop_jwk"];

    [self issueTokensForClientID:codeData[@"client_id"]
                            sub:sub
                          scope:scope
                       dpopJWK:dpopJWK
                      dpopProof:dpopProof
                            uri:redirectURI
                      completion:completion];
}

- (void)processRefreshTokenGrant:(OAuthProviderTokenRequest *)request
                       completion:(OAuthProviderTokenCompletion)completion {
    NSString *refreshToken = request.refreshToken;
    if (!refreshToken) {
        completion(nil, [self errorWithCode:OAuthProviderErrorInvalidGrant
                               description:@"Missing refresh_token"]);
        return;
    }

    NSError *verifyError = nil;
    NSDictionary *tokenClaims = [self.tokenSigner verifyRefreshToken:refreshToken error:&verifyError];
    if (!tokenClaims) {
        completion(nil, verifyError ?: [self errorWithCode:OAuthProviderErrorInvalidToken
                                              description:@"Invalid refresh token"]);
        return;
    }

    NSString *clientID = tokenClaims[@"client_id"];
    NSString *sub = tokenClaims[@"sub"];
    NSString *scope = tokenClaims[@"scope"];
    NSDictionary *dpopJWK = tokenClaims[@"dpop_jwk"];

    [self issueTokensForClientID:clientID
                            sub:sub
                          scope:scope
                       dpopJWK:dpopJWK
                      dpopProof:request.dpopProof
                            uri:nil
                      completion:completion];
}

- (void)processClientCredentialsGrant:(OAuthProviderTokenRequest *)request
                           completion:(OAuthProviderTokenCompletion)completion {
    NSString *clientID = request.clientID;
    if (!clientID) {
        completion(nil, [self errorWithCode:OAuthProviderErrorInvalidClient
                               description:@"Missing client_id"]);
        return;
    }

    NSString *scope = request.scope;

    [self issueTokensForClientID:clientID
                            sub:clientID
                          scope:scope
                       dpopJWK:nil
                      dpopProof:request.dpopProof
                            uri:nil
                      completion:completion];
}

- (void)issueTokensForClientID:(NSString *)clientID
                           sub:(NSString *)sub
                         scope:(NSString *)scope
                      dpopJWK:(nullable NSDictionary *)dpopJWK
                     dpopProof:(nullable NSString *)dpopProof
                           uri:(nullable NSString *)uri
                   completion:(OAuthProviderTokenCompletion)completion {
    NSString *audience = self.issuer ?: @"";
    NSMutableDictionary *accessClaims = [NSMutableDictionary dictionary];
    accessClaims[@"sub"] = sub;
    accessClaims[@"aud"] = audience;
    accessClaims[@"iat"] = @([[NSDate date] timeIntervalSince1970]);
    accessClaims[@"exp"] = @([[NSDate date] timeIntervalSince1970] + 3600);
    accessClaims[@"client_id"] = clientID;
    if (scope) accessClaims[@"scope"] = scope;
    if (dpopJWK) {
        NSError *thumbprintError = nil;
        NSString *thumbprint = [AuthCryptoJWK thumbprint:dpopJWK error:&thumbprintError];
        if (thumbprint) {
            accessClaims[@"cnf"] = @{@"jkt": thumbprint};
        }
    }

    NSError *mintError = nil;
    NSString *accessToken = [self.tokenSigner mintAccessTokenWithClaims:accessClaims error:&mintError];
    if (!accessToken) {
        completion(nil, mintError ?: [self errorWithCode:OAuthProviderErrorServerError
                                             description:@"Failed to mint access token"]);
        return;
    }

    NSMutableDictionary *refreshClaims = [NSMutableDictionary dictionary];
    refreshClaims[@"sub"] = sub;
    refreshClaims[@"iat"] = @([[NSDate date] timeIntervalSince1970]);
    refreshClaims[@"client_id"] = clientID;
    if (scope) refreshClaims[@"scope"] = scope;
    if (dpopJWK) refreshClaims[@"dpop_jwk"] = dpopJWK;

    NSString *refreshToken = [self.tokenSigner mintRefreshTokenWithClaims:refreshClaims error:&mintError];

    NSString *dpopNonce = nil;
    if (dpopJWK) {
        dpopNonce = [[NSUUID UUID] UUIDString];
    }

    OAuthProviderTokenResponse *response = [[OAuthProviderTokenResponse alloc] init];
    response.accessToken = accessToken;
    response.refreshToken = refreshToken;
    response.tokenType = dpopJWK ? @"DPoP" : @"Bearer";
    response.expiresIn = 3600;
    response.scope = scope;
    response.dpopNonce = dpopNonce;

    if (dpopJWK) {
        NSError *thumbprintError = nil;
        response.dpopKeyThumbprint = [AuthCryptoJWK thumbprint:dpopJWK error:&thumbprintError];
    }

    PDS_LOG_AUTH_DEBUG(@"Tokens issued: sub=%@ client_id=%@", sub, clientID);
    completion(response, nil);
}

#pragma mark - Token Introspection & Revocation

- (void)revokeToken:(NSString *)token
       tokenTypeHint:(nullable NSString *)tokenTypeHint
         completion:(void (^)(NSError * _Nullable))completion {
    if (self.storage) {
        [self.storage revokeRefreshToken:token error:nil];
    }
    completion(nil);
}

- (void)introspectToken:(NSString *)token
             completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    NSError *verifyError = nil;
    NSDictionary *claims = [self.tokenSigner verifyAccessToken:token forAudience:self.issuer ?: @"" error:&verifyError];

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if (claims) {
        result[@"active"] = @YES;
        result[@"sub"] = claims[@"sub"];
        result[@"client_id"] = claims[@"client_id"];
        result[@"exp"] = claims[@"exp"];
        result[@"iat"] = claims[@"iat"];
        if (claims[@"scope"]) result[@"scope"] = claims[@"scope"];
        if (claims[@"cnf"]) result[@"cnf"] = claims[@"cnf"];
    } else {
        result[@"active"] = @NO;
    }

    completion(result, nil);
}

#pragma mark - Metadata

- (NSDictionary *)serverMetadata {
    NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
    metadata[@"issuer"] = self.issuer ?: @"https://example.com";
    metadata[@"authorization_endpoint"] = [NSString stringWithFormat:@"%@/oauth/authorize", self.issuer ?: @"https://example.com"];
    metadata[@"token_endpoint"] = [NSString stringWithFormat:@"%@/oauth/token", self.issuer ?: @"https://example.com"];
    metadata[@"jwks_uri"] = [NSString stringWithFormat:@"%@/.well-known/jwks.json", self.issuer ?: @"https://example.com"];
    metadata[@"registration_endpoint"] = [NSString stringWithFormat:@"%@/oauth/register", self.issuer ?: @"https://example.com"];
    metadata[@"response_types_supported"] = @[@"code"];
    metadata[@"response_modes_supported"] = @[@"query", @"fragment"];
    metadata[@"grant_types_supported"] = @[@"authorization_code", @"refresh_token", @"client_credentials"];
    metadata[@"token_endpoint_auth_methods_supported"] = self.supportedTokenEndpointAuthMethods;
    metadata[@"code_challenge_methods_supported"] = @[@"S256"];
    metadata[@"revocation_endpoint"] = [NSString stringWithFormat:@"%@/oauth/revoke", self.issuer ?: @"https://example.com"];
    metadata[@"revocation_endpoint_auth_methods_supported"] = self.supportedTokenEndpointAuthMethods;
    metadata[@"introspection_endpoint"] = [NSString stringWithFormat:@"%@/oauth/introspect", self.issuer ?: @"https://example.com"];
    metadata[@"introspection_endpoint_auth_methods_supported"] = self.supportedTokenEndpointAuthMethods;
    metadata[@"service_documentation"] = @"https://atproto.com/docs/oauth";
    metadata[@"ui_locales_supported"] = @[@"en"];
    return metadata;
}

- (NSDictionary *)jwks {
    return [self.tokenSigner jwks];
}

#pragma mark - Helpers

- (NSError *)errorWithCode:(OAuthProviderError)code description:(NSString *)description {
    return [NSError errorWithDomain:OAuthProviderErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

- (BOOL)verifyPKCE:(NSString *)verifier challenge:(NSString *)challenge method:(NSString *)method {
    if (![method isEqualToString:@"S256"]) {
        return NO;
    }

    NSData * verifierData = [verifier dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(verifierData.bytes, (CC_LONG)verifierData.length, digest);
    NSData *hashData = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    NSString *computed = [AuthCryptoBase64URL encode:hashData];
    return [computed isEqualToString:challenge];
}

@end
