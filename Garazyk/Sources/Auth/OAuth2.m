/*!
 @file OAuth2.m

 @abstract OAuth 2.0 with DPoP implementation for ATProto.

 @discussion This file implements the OAuth 2.0 authorization server including
 authorization request handling, token issuance with DPoP proof binding,
 PKCE support, and token refresh. Follows ATProto OAuth 2.0 specification.

 @copyright Copyright (c) 2024 Jack Valinsky
 */

#import "Auth/OAuth2.h"
#import "Debug/PDSLogRedactor.h"
#import "Auth/JWT.h"
#import "Auth/Session.h"
#import "Auth/TOTPService.h"
#import "Auth/WebAuthnVerifier.h"
#import "Security/PDSSecurityCompare.h"
#import "Auth/Base32Utils.h"
#import "Auth/CryptoUtils.h"
#import "Auth/PDSReplayCache.h"
#import "Auth/PDSNonceManager.h"
#import "App/PDSConfiguration.h"
#import "Auth/Crypto/AuthCryptoJWK.h"
#import "Auth/Crypto/AuthCryptoDPoP.h"
#import "Auth/Crypto/AuthCryptoBase64URL.h"
#import "Auth/Crypto/AuthCryptoECDSA.h"
#import "Auth/Secp256k1.h"
#import "Database/PDSDatabase.h"
#import "Debug/PDSLogger.h"
#import "Metrics/PDSMetrics.h"
#import "Core/DID.h"
#import "Auth/PDSKeyManagerProtocol.h"
#import "Auth/PDSKeyManagerFactory.h"
#import "Identity/HandleResolver.h"
#if !TARGET_OS_LINUX
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>
#endif

NSString * const OAuth2ScopeAtproto = @"atproto";
NSString * const OAuth2ScopeTransitionGeneric = @"transition:generic";
NSString * const OAuth2ScopeTransitionChatBsky = @"transition:chat.bsky";
NSString * const OAuth2ScopeTransitionEmail = @"transition:email";

NSString * const OAuth2ScopeIdentify = @"atproto:identify";
NSString * const OAuth2ScopeSignIn = @"atproto:signin";
NSString * const OAuth2ScopeRepoWrite = @"atproto:repo_write";
NSString * const OAuth2ScopeRepoRead = @"atproto:repo_read";
NSString * const OAuth2ScopeAtprotoProfile = @"atproto:profile";

NSString * const OAuth2ErrorDomain = @"com.atproto.pds.oauth2";

static NSString * const kAuthorizationCodeKey = @"authorization_code";
static NSString * const kRefreshTokenKey = @"refresh_token";

static BOOL OAuth2ShouldUseEphemeralJWTKeyForTests(void) {
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    NSString *processName = [[NSProcessInfo processInfo] processName] ?: @"";
    BOOL runningTests = [env[@"PDS_RUNNING_TESTS"] length] > 0 ||
                        [processName containsString:@"AllTests"];
    if (!runningTests) {
        return NO;
    }

    NSString *useKeychainEnv = [env[@"PDS_USE_KEYCHAIN"] lowercaseString];
    if ([useKeychainEnv isEqualToString:@"0"] ||
        [useKeychainEnv isEqualToString:@"false"] ||
        [useKeychainEnv isEqualToString:@"no"]) {
        return YES;
    }

    return ![PDSConfiguration sharedConfiguration].useKeychain;
}

static void OAuth2LogEphemeralJWTKeyModeOnce(void) {
    static BOOL didLog = NO;
    if (didLog) {
        return;
    }
    didLog = YES;
    PDS_LOG_AUTH_INFO(@"Using in-memory secp256k1 OAuth2 JWT signing key in test mode (keychain disabled).");
}



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
    if (self.responseMode) [queryItems addObject:[NSURLQueryItem queryItemWithName:@"response_mode" value:self.responseMode]];
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
    if (self.responseMode) dict[@"response_mode"] = self.responseMode;
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
    response.issuer = params[@"iss"];

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

+ (nullable NSData *)decodeBase64URL:(NSString *)value error:(NSError **)error {
    return [JWT base64URLDecode:value error:error];
}

+ (nullable NSData *)decodeJWKComponent:(NSString *)value expectedLength:(NSUInteger)expectedLength error:(NSError **)error {
    NSData *decoded = [self decodeBase64URL:value error:error];
    if (!decoded) {
        return nil;
    }
    if (decoded.length != expectedLength) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid JWK component length"}];
        }
        return nil;
    }
    return decoded;
}

+ (nullable SecKeyRef)createPrivateKeyFromJWK:(NSDictionary *)jwk error:(NSError **)error {
    NSString *kty = jwk[@"kty"];
    if (!kty) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing JWK key type"}];
        }
        return nil;
    }

    if ([kty isEqualToString:@"EC"]) {
        NSString *crv = jwk[@"crv"];
        if (crv && ![crv isEqualToString:@"P-256"]) {
            if (error) {
                *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidRequest
                                         userInfo:@{NSLocalizedDescriptionKey: @"Unsupported EC curve"}];
            }
            return nil;
        }

        NSString *xValue = jwk[@"x"];
        NSString *yValue = jwk[@"y"];
        NSString *dValue = jwk[@"d"];
        if (!xValue || !yValue || !dValue) {
            if (error) {
                *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidRequest
                                         userInfo:@{NSLocalizedDescriptionKey: @"Missing EC key material"}];
            }
            return nil;
        }

        NSError *decodeError = nil;
        NSData *xData = [self decodeJWKComponent:xValue expectedLength:32 error:&decodeError];
        NSData *yData = [self decodeJWKComponent:yValue expectedLength:32 error:&decodeError];
        NSData *dData = [self decodeJWKComponent:dValue expectedLength:32 error:&decodeError];
        if (!xData || !yData || !dData) {
            if (error) *error = decodeError;
            return nil;
        }

        NSMutableData *privateKeyData = [NSMutableData dataWithCapacity:97];
        uint8_t prefix = 0x04;
        [privateKeyData appendBytes:&prefix length:1];
        [privateKeyData appendData:xData];
        [privateKeyData appendData:yData];
        [privateKeyData appendData:dData];

        NSDictionary *attrs = @{
            (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
            (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPrivate,
            (__bridge id)kSecAttrKeySizeInBits: @256
        };

        CFErrorRef keyError = NULL;
        SecKeyRef privateKey = SecKeyCreateWithData((__bridge CFDataRef)privateKeyData,
                                                    (__bridge CFDictionaryRef)attrs,
                                                    &keyError);
        if (!privateKey) {
            if (error) {
                if (keyError) {
                    *error = CFBridgingRelease(keyError);
                } else {
                    *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                                 code:OAuth2ErrorServerError
                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to create EC private key"}];
                }
            } else if (keyError) {
                CFRelease(keyError);
            }
            return nil;
        }
        if (keyError) CFRelease(keyError);
        return privateKey;
    }

    if (error) {
        *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                     code:OAuth2ErrorInvalidRequest
                                 userInfo:@{NSLocalizedDescriptionKey: @"Unsupported JWK key type"}];
    }
    return nil;
}

+ (nullable SecKeyRef)createPublicKeyFromJWK:(NSDictionary *)jwk error:(NSError **)error {
    NSString *kty = jwk[@"kty"];
    if (![kty isEqualToString:@"EC"]) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unsupported JWK key type"}];
        }
        return nil;
    }

    NSString *xValue = jwk[@"x"];
    NSString *yValue = jwk[@"y"];
    if (!xValue || !yValue) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing EC public key material"}];
        }
        return nil;
    }

    NSError *decodeError = nil;
    NSData *xData = [self decodeJWKComponent:xValue expectedLength:32 error:&decodeError];
    NSData *yData = [self decodeJWKComponent:yValue expectedLength:32 error:&decodeError];
    if (!xData || !yData) {
        if (error) *error = decodeError;
        return nil;
    }

    NSMutableData *publicKeyData = [NSMutableData dataWithCapacity:65];
    uint8_t prefix = 0x04;
    [publicKeyData appendBytes:&prefix length:1];
    [publicKeyData appendData:xData];
    [publicKeyData appendData:yData];

    NSDictionary *attrs = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPublic,
        (__bridge id)kSecAttrKeySizeInBits: @256
    };

    CFErrorRef keyError = NULL;
    SecKeyRef publicKey = SecKeyCreateWithData((__bridge CFDataRef)publicKeyData,
                                               (__bridge CFDictionaryRef)attrs,
                                               &keyError);
    if (!publicKey) {
        if (error) {
            if (keyError) {
                *error = CFBridgingRelease(keyError);
            } else {
                *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorServerError
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to create EC public key"}];
            }
        } else if (keyError) {
            CFRelease(keyError);
        }
        return nil;
    }
    if (keyError) CFRelease(keyError);
    return publicKey;
}

+ (NSDictionary *)publicJWKFromJWK:(NSDictionary *)jwk {
    return [AuthCryptoJWK publicJWKFromJWK:jwk];
}

+ (nullable NSString *)jwkThumbprint:(NSDictionary *)jwk error:(NSError **)error {
    return [AuthCryptoJWK thumbprint:jwk error:error];
}

+ (nullable NSString *)createProofForURL:(NSURL *)url
                                 method:(NSString *)method
                                   key:(NSDictionary *)jwk
                                  error:(NSError **)error {
    return [AuthCryptoDPoP createProofForURL:url method:method key:jwk error:error];
}

+ (BOOL)verifyProof:(NSString *)dpopJwt
             method:(NSString *)method
                url:(NSURL *)url
               nonce:(nullable NSString *)nonce
       outThumbprint:(NSString * _Nullable * _Nullable)thumbprint
               error:(NSError **)error {
    return [self verifyProof:dpopJwt
                      method:method
                         url:url
                       nonce:nonce
                requireNonce:NO
               outThumbprint:thumbprint
                       error:error];
}

+ (BOOL)verifyProof:(NSString *)dpopJwt
              method:(NSString *)method
                 url:(NSURL *)url
               nonce:(nullable NSString *)nonce
        requireNonce:(BOOL)requireNonce
      outThumbprint:(NSString * _Nullable * _Nullable)thumbprint
                error:(NSError **)error {
    return [AuthCryptoDPoP verifyProof:dpopJwt
                                method:method
                                   url:url
                                 nonce:nonce
                          requireNonce:requireNonce
                        nonceValidator:(id<AuthCryptoDPoPNonceValidator>)[PDSNonceManager sharedManager]
                         replayChecker:(id<AuthCryptoDPoPReplayChecker>)[PDSReplayCache sharedCache]
                         outThumbprint:thumbprint
                                 error:error];
}

@end

@implementation OAuth2Server

- (void)setIssuer:(NSString *)issuer {
    _issuer = [issuer copy];
    if (self.jwtMinter) {
        self.jwtMinter.issuer = _issuer;
        if (!self.jwtMinter.audience) {
            self.jwtMinter.audience = _issuer;
        }
    }
}

- (instancetype)initWithDatabase:(nullable PDSDatabase *)database {
    self = [super init];
    if (self) {
        _authorizationCodes = [NSMutableDictionary dictionary];
        _activeSessions = [NSMutableDictionary dictionary];
        _authorizationQueue = dispatch_queue_create("com.atproto.oauth2.authorization", DISPATCH_QUEUE_SERIAL);
        _sessionQueue = dispatch_queue_create("com.atproto.oauth2.session", DISPATCH_QUEUE_SERIAL);
        _jwtMinter = [[JWTMinter alloc] init];
        _keyManager = [PDSKeyManagerFactory createKeyManagerWithDatabase:database];
        _jwtMinter.keyManager = _keyManager;
        _jwtMinter.signingAlgorithm = @"ES256K";
        _jwtMinter.issuer = self.issuer;
        _jwtMinter.audience = self.issuer;
        _didResolver = [[DIDResolver alloc] init];
        _didResolver.plcURL = [PDSConfiguration sharedConfiguration].plcURL;
        _handleResolver = [[HandleResolver alloc] init];
        _database = database;

        BOOL hasProvisionedSigningKey = NO;
        if (OAuth2ShouldUseEphemeralJWTKeyForTests()) {
            NSError *fallbackError = nil;
            Secp256k1KeyPair *fallbackKeyPair = [[Secp256k1 shared] generateKeyPairWithError:&fallbackError];
            if (fallbackKeyPair) {
                _keyManager = nil;
                _jwtMinter.keyManager = nil;
                _jwtMinter.signingAlgorithm = @"ES256K";
                _jwtMinter.privateKey = fallbackKeyPair.privateKey;
                _jwtMinter.publicKey = fallbackKeyPair.publicKey;
                hasProvisionedSigningKey = YES;
                OAuth2LogEphemeralJWTKeyModeOnce();
            } else {
                PDS_LOG_AUTH_WARN(@"Test-mode ephemeral OAuth2 JWT key generation failed; falling back to key manager path: %@",
                                  fallbackError.localizedDescription ?: @"unknown error");
            }
        }

        if (!hasProvisionedSigningKey) {
            NSError *keyError = nil;
            id<PDSKeyPair> keyPair = [_keyManager getActiveKeyPair:&keyError];
            if (!keyPair) {
                NSDictionary *env = [[NSProcessInfo processInfo] environment];
                BOOL isProduction = [[env[@"PDS_ENV"] lowercaseString] isEqualToString:@"production"] ||
                                    [[env[@"PDS_REQUIRE_ISSUER"] lowercaseString] isEqualToString:@"1"] ||
                                    [[env[@"PDS_REQUIRE_ISSUER"] lowercaseString] isEqualToString:@"true"];
                if (!isProduction) {
                    NSError *fallbackError = nil;
                    Secp256k1KeyPair *fallbackKeyPair = [[Secp256k1 shared] generateKeyPairWithError:&fallbackError];
                    if (fallbackKeyPair) {
                        _keyManager = nil;
                        _jwtMinter.keyManager = nil;
                        _jwtMinter.signingAlgorithm = @"ES256K";
                        _jwtMinter.privateKey = fallbackKeyPair.privateKey;
                        _jwtMinter.publicKey = fallbackKeyPair.publicKey;
                        PDS_LOG_AUTH_WARN(@"Using in-memory secp256k1 OAuth2 JWT signing key fallback because key manager provisioning failed (%@).",
                                          keyError.localizedDescription ?: @"unknown error");
                    } else {
                        PDS_LOG_AUTH_ERROR(@"Failed to get or generate JWT signing key for OAuth2: %@ (fallback error: %@)",
                                           keyError.localizedDescription ?: @"unknown error",
                                           fallbackError.localizedDescription ?: @"unknown error");
                    }
                } else {
                    PDS_LOG_AUTH_ERROR(@"Failed to get or generate JWT signing key for OAuth2: %@", keyError.localizedDescription ?: @"unknown error");
                }
            }
        }
    }
    return self;
}

- (instancetype)init {
    return [self initWithDatabase:nil];
}

#pragma mark - Thread-Safe Authorization Code Access

- (void)storeAuthorizationCode:(NSString *)code data:(NSDictionary *)codeData {
    dispatch_sync(self.authorizationQueue, ^{
        self.authorizationCodes[code] = codeData;
    });
}

- (nullable NSDictionary *)getAuthorizationCodeData:(NSString *)code {
    __block NSDictionary *result = nil;
    dispatch_sync(self.authorizationQueue, ^{
        result = [self.authorizationCodes[code] copy];
    });
    return result;
}

- (void)removeAuthorizationCode:(NSString *)code {
    dispatch_sync(self.authorizationQueue, ^{
        [self.authorizationCodes removeObjectForKey:code];
    });
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
    if (request.loginHint) {
        codeData[@"login_hint"] = request.loginHint;
        NSError *resolveError = nil;
        NSString *did = [self resolveIdentity:request.loginHint error:&resolveError];
        if (did) {
            codeData[@"login_hint_did"] = did;
        } else {
            PDS_LOG_AUTH_WARN(@"Failed to resolve login_hint for authorization request (client_id=%@): %@",
                              request.clientID ?: @"",
                              resolveError.localizedDescription ?: @"unknown error");
        }
    }
    if (request.webauthn) {
        NSData *webauthnChallenge = [CryptoUtils randomBytes:32];
        if (webauthnChallenge) {
            codeData[@"webauthn_challenge"] = webauthnChallenge;
        }
    }
    codeData[@"created_at"] = @([[NSDate date] timeIntervalSince1970]);

    [self storeAuthorizationCode:code data:codeData];

    PDS_LOG_AUTH_DEBUG(@"Stored authorization code (client_id=%@, has_pkce=%@, has_dpop_jwk=%@, has_login_hint=%@)",
                       request.clientID ?: @"",
                       @(request.codeChallenge.length > 0),
                       @(request.dpopJWK != nil),
                       @(request.loginHint.length > 0));

    NSURLComponents *redirectComponents = [NSURLComponents componentsWithString:request.redirectURI];
    if (!redirectComponents) {
        NSError *invalidRedirectError = [NSError errorWithDomain:OAuth2ErrorDomain
                                                            code:OAuth2ErrorInvalidRequest
                                                        userInfo:@{NSLocalizedDescriptionKey: @"Invalid redirect URI"}];
        completion(nil, nil, invalidRedirectError);
        return;
    }

    NSMutableArray<NSURLQueryItem *> *queryItems =
        [redirectComponents.queryItems mutableCopy] ?: [NSMutableArray array];
    [queryItems addObject:[NSURLQueryItem queryItemWithName:@"code" value:code]];
    if (request.state) {
        [queryItems addObject:[NSURLQueryItem queryItemWithName:@"state" value:request.state]];
    }
    if (self.issuer.length > 0) {
        [queryItems addObject:[NSURLQueryItem queryItemWithName:@"iss" value:self.issuer]];
    }

    // Determine response mode: fragment or query (default)
    BOOL useFragment = [request.responseMode isEqualToString:@"fragment"];
    if (useFragment) {
        // Build fragment string from the response parameters
        NSMutableArray<NSString *> *fragParts = [NSMutableArray array];
        for (NSURLQueryItem *item in queryItems) {
            NSString *encodedName = [item.name stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
            NSString *encodedValue = item.value ? [item.value stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]] : @"";
            [fragParts addObject:[NSString stringWithFormat:@"%@=%@", encodedName, encodedValue]];
        }
        redirectComponents.fragment = [fragParts componentsJoinedByString:@"&"];
        // Clear any existing query items that were on the redirect URI
        // (keep the original query items from the redirect_uri itself)
    } else {
        redirectComponents.queryItems = queryItems;
    }

    completion(redirectComponents.URL, code, nil);
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
    NSDictionary *codeData = [self getAuthorizationCodeData:request.code];
    if (!codeData) {
        PDS_LOG_AUTH_WARN(@"Authorization code not found or expired (client_id=%@)", request.clientID ?: @"");
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidGrant
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid or expired authorization code"}];
        completion(nil, error);
        return;
    }

    PDS_LOG_AUTH_DEBUG(@"Processing token request (grant_type=%@, client_id=%@, has_code=%@, has_code_verifier=%@)",
                       request.grantType ?: @"",
                       request.clientID ?: @"",
                       @(request.code.length > 0),
                       @(request.codeVerifier.length > 0));

    NSTimeInterval codeAge = [[NSDate date] timeIntervalSince1970] - [codeData[@"created_at"] doubleValue];
    if (codeAge > 600) {
        [self removeAuthorizationCode:request.code];
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

    // PKCE is mandatory per AT Protocol OAuth spec
    NSString *expectedChallenge = codeData[@"code_challenge"];
    if (!expectedChallenge) {
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidGrant
                                         userInfo:@{NSLocalizedDescriptionKey: @"PKCE code_challenge was not provided during authorization"}];
        completion(nil, error);
        return;
    }

    if (!request.codeVerifier) {
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidGrant
                                         userInfo:@{NSLocalizedDescriptionKey: @"Missing code_verifier (PKCE is mandatory)"}];
        completion(nil, error);
        return;
    }

    NSString *method = codeData[@"code_challenge_method"] ?: @"S256";

    // URL-decode the code_verifier since browsers send it encoded
    NSString *codeVerifier = [request.codeVerifier stringByRemovingPercentEncoding];
    if (!codeVerifier) {
        codeVerifier = request.codeVerifier;
    }

    PDS_LOG_AUTH_DEBUG(@"Verifying PKCE (client_id=%@, method=%@, verifier_len=%lu, challenge_len=%lu)",
                       request.clientID ?: @"",
                       method,
                       (unsigned long)codeVerifier.length,
                       (unsigned long)expectedChallenge.length);

    if (![self verifyCodeVerifier:codeVerifier challenge:expectedChallenge method:method]) {
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidGrant
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid code verifier"}];
        completion(nil, error);
        return;
    }
    PDS_LOG_AUTH_DEBUG(@"PKCE verification passed (client_id=%@)", request.clientID ?: @"");

    [self removeAuthorizationCode:request.code];

    NSString *did = codeData[@"login_hint_did"];
    if (!did) {
        PDS_LOG_AUTH_ERROR(@"Authorization code missing login_hint_did (client_id=%@)", request.clientID ?: @"");
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidGrant
                                         userInfo:@{NSLocalizedDescriptionKey: @"Missing user identity in authorization code"}];
        completion(nil, error);
        return;
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

    // MARK: WebAuthn integration
    if (account && account.webauthnEnabled && !request.tfaCode) {
        if (!request.webauthnAssertion) {
            NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                          code:OAuth2ErrorInteractionRequired
                                      userInfo:@{NSLocalizedDescriptionKey: @"WebAuthn authentication required",
                                                 @"error": @"webauthn_required"}];
            completion(nil, error);
            return;
        }

        NSData *webauthnChallenge = codeData[@"webauthn_challenge"];
        if (!webauthnChallenge) {
            NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                          code:OAuth2ErrorInvalidGrant
                                      userInfo:@{NSLocalizedDescriptionKey: @"No WebAuthn challenge found for session"}];
            completion(nil, error);
            return;
        }

        NSError *webauthnError = nil;
        NSArray<NSDictionary *> *credentials = [self.database getWebAuthnCredentialsForDid:did error:&webauthnError];
        if (credentials.count == 0) {
            NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                          code:OAuth2ErrorInvalidGrant
                                      userInfo:@{NSLocalizedDescriptionKey: @"No WebAuthn credentials found"}];
            completion(nil, error);
            return;
        }

        NSString *origin = [PDSConfiguration sharedConfiguration].issuer;
        BOOL verified = NO;
        uint32_t newSignCount = 0;
        NSDictionary *matchedCredential = nil;

        for (NSDictionary *cred in credentials) {
            uint32_t storedSignCount = [cred[@"signCount"] unsignedIntValue];
            uint32_t newCount = 0;

            verified = [WebAuthnVerifier verifyAssertionResponse:request.webauthnAssertion
                                               challenge:webauthnChallenge
                                                  origin:origin
                                               publicKey:cred[@"publicKey"]
                                               signCount:storedSignCount
                                            newSignCount:&newCount
                                                   error:&webauthnError];
            if (verified) {
                matchedCredential = cred;
                newSignCount = newCount;
                break;
            }
        }

        if (!verified) {
            NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                          code:OAuth2ErrorInvalidGrant
                                      userInfo:@{NSLocalizedDescriptionKey: @"WebAuthn verification failed"}];
            completion(nil, error);
            return;
        }

        if (matchedCredential && newSignCount > 0) {
            [self.database updateWebAuthnCredentialSignCount:matchedCredential[@"credentialId"]
                                                  forDid:did
                                               signCount:newSignCount
                                                   error:nil];
        }
    }

    if (!account.handle) {
        PDS_LOG_ERROR(@"OAuth2", @"Account handle is nil, cannot proceed with token exchange");
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                              code:OAuth2ErrorInvalidRequest
                                          userInfo:@{NSLocalizedDescriptionKey: @"Account handle is required"}];
        completion(nil, error);
        return;
    }
    NSString *handle = account.handle;
    NSString *scope = codeData[@"scope"] ?: OAuth2ScopeAtproto;

    // AT Protocol spec: atproto scope is required for all sessions
    if (![scope containsString:@"atproto"]) {
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidScope
                                         userInfo:@{NSLocalizedDescriptionKey: @"The 'atproto' scope is required"}];
        completion(nil, error);
        return;
    }

    if (!request.dpopKeyThumbprint || request.dpopKeyThumbprint.length == 0) {
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidDPoPProof
                                         userInfo:@{NSLocalizedDescriptionKey: @"Missing DPoP key thumbprint"}];
        completion(nil, error);
        return;
    }

    NSString *expectedDPoPJKT = codeData[@"dpop_jwk"];
    if (expectedDPoPJKT.length > 0 &&
        ![CryptoUtils constantTimeCompare:expectedDPoPJKT
                                       to:request.dpopKeyThumbprint]) {
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidDPoPProof
                                         userInfo:@{NSLocalizedDescriptionKey: @"DPoP key mismatch for authorization session"}];
        completion(nil, error);
        return;
    }

    Session *session = [self createSessionForDID:did
                                          handle:handle
                                           scope:scope
                               dpopKeyThumbprint:request.dpopKeyThumbprint];

    // Store refresh token in database (H3)
    [self.database storeRefreshToken:session.refreshToken
                      forAccountDid:session.did
                          expiresAt:session.refreshTokenExpiresAt
                              error:nil];

    [[PDSMetrics sharedMetrics] incrementOAuthTokenGrant:@"authorization_code"];
    [[PDSMetrics sharedMetrics] setActiveAuthSessions:(NSInteger)self.activeSessions.count];
    completion(session, nil);
}

- (void)processRefreshTokenGrant:(OAuth2TokenRequest *)request
                      completion:(OAuth2TokenCompletion)completion {
    // 1. Try to find active session in memory
    Session *existingSession = nil;
    for (Session *session in self.activeSessions.allValues) {
        if ([PDSSecurityCompare constantTimeEqualString:session.refreshToken string:request.refreshToken]) {
            existingSession = session;
            break;
        }
    }

    NSString *did = nil;
    if (existingSession) {
        did = existingSession.did;
    } else {
        // 2. Fallback to database for server-side persistence (H3/H4)
        NSError *dbError = nil;
        did = [self.database accountDidForRefreshToken:request.refreshToken error:&dbError];
        if (!did) {
            PDS_LOG_AUTH_WARN(@"Invalid or expired refresh token (not found in memory or DB): %@", [PDSLogRedactor maskToken:request.refreshToken]);
            NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                                 code:OAuth2ErrorInvalidGrant
                                             userInfo:@{NSLocalizedDescriptionKey: @"Invalid or expired refresh token"}];
            completion(nil, error);
            return;
        }
    }

    // 3. Verify token_use claim if it's a JWT (H3)
    NSError *jwtError = nil;
    JWT *refreshTokenJWT = [JWT jwtWithToken:request.refreshToken error:&jwtError];
    if (refreshTokenJWT) {
        if (![refreshTokenJWT.payload.token_use isEqualToString:@"refresh"]) {
            PDS_LOG_AUTH_ERROR(@"Token usage mismatch: expected 'refresh', got '%@'", refreshTokenJWT.payload.token_use ?: @"none");
            NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                                 code:OAuth2ErrorInvalidGrant
                                             userInfo:@{NSLocalizedDescriptionKey: @"Invalid token use"}];
            completion(nil, error);
            return;
        }
    }

    if (existingSession && [existingSession.refreshTokenExpiresAt compare:[NSDate date]] == NSOrderedAscending) {
        [self.activeSessions removeObjectForKey:existingSession.sessionID];
        [self.database revokeSession:request.refreshToken error:nil];
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorTokenExpired
                                         userInfo:@{NSLocalizedDescriptionKey: @"Refresh token expired"}];
        completion(nil, error);
        return;
    }

    // 4. Issue new tokens
    NSError *accountError = nil;
    PDSDatabaseAccount *account = [self.database getAccountByDid:did error:&accountError];
    if (!account) {
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidGrant
                                         userInfo:@{NSLocalizedDescriptionKey: @"Account not found"}];
        completion(nil, error);
        return;
    }

    NSString *newScope = request.scope ?: (existingSession ? existingSession.scope : OAuth2ScopeAtproto);
    Session *newSession = [self createSessionForDID:did
                                             handle:account.handle
                                              scope:newScope
                                  dpopKeyThumbprint:nil];

    // 5. Cleanup old session
    if (existingSession) {
        [self.activeSessions removeObjectForKey:existingSession.sessionID];
    }
    [self.database revokeSession:request.refreshToken error:nil];

    // 6. Store new refresh token (H3)
    [self.database storeRefreshToken:newSession.refreshToken
                      forAccountDid:newSession.did
                          expiresAt:newSession.refreshTokenExpiresAt
                              error:nil];

    [[PDSMetrics sharedMetrics] incrementOAuthTokenGrant:@"refresh_token"];
    [[PDSMetrics sharedMetrics] setActiveAuthSessions:(NSInteger)self.activeSessions.count];
    completion(newSession, nil);
}

- (void)processDPoPGrant:(OAuth2TokenRequest *)request
              completion:(OAuth2TokenCompletion)completion {
    Session *existingSession = [self getSessionByAccessToken:request.accessToken];
    if (!existingSession) {
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidGrant
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid or expired access token"}];
        completion(nil, error);
        return;
    }

    NSString *newAccessToken = [existingSession refreshAccessToken];
    if (request.dpopKeyThumbprint) {
        existingSession.dpopKeyThumbprint = request.dpopKeyThumbprint;
    }

    completion(existingSession, nil);
}

- (nullable Session *)getSessionByAccessToken:(NSString *)accessToken {
    for (Session *session in self.activeSessions.allValues) {
        if ([PDSSecurityCompare constantTimeEqualString:session.accessToken string:accessToken]) {
            return session;
        }
    }
    return nil;
}

- (Session *)createSessionForDID:(NSString *)did
                          handle:(NSString *)handle
                           scope:(NSString *)scope
               dpopKeyThumbprint:(nullable NSString *)dpopKeyThumbprint {
    Session *session = [[Session alloc] initWithDID:did
                                             handle:handle
                                              scope:scope
                                             minter:self.jwtMinter
                                  dpopKeyThumbprint:dpopKeyThumbprint];

    self.activeSessions[session.sessionID] = session;

    return session;
}

- (BOOL)verifyCodeVerifier:(NSString *)verifier challenge:(NSString *)challenge method:(NSString *)method {
    // AT Protocol OAuth spec: only S256 is allowed, "plain" is not permitted
    if (![method isEqualToString:@"S256"]) {
        return NO;
    }
    NSData *verifierData = [verifier dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(verifierData.bytes, (CC_LONG)verifierData.length, hash);
    NSData *hashData = [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
    NSString *base64Hash = [self base64URLEncodeData:hashData];
    return [base64Hash isEqualToString:challenge];
}

- (NSString *)base64URLEncodeData:(NSData *)data {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return base64;
}

- (void)refreshAccessToken:(NSString *)refreshToken
                     scope:(nullable NSString *)scope
                   dpopJWK:(nullable NSDictionary *)dpopJWK
                completion:(OAuth2RefreshCompletion)completion {
    // Find session with this refresh token
    Session *foundSession = nil;
    for (Session *session in self.activeSessions.allValues) {
        if ([PDSSecurityCompare constantTimeEqualString:session.refreshToken string:refreshToken]) {
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
    
    NSString *ttlEnv = [[NSProcessInfo processInfo] environment][@"PDS_REFRESH_TOKEN_TTL_DAYS"];
    NSTimeInterval refreshTokenTTL = ttlEnv ? ttlEnv.doubleValue * 24 * 60 * 60 : 30 * 24 * 60 * 60;
    if ([foundSession.createdAt timeIntervalSinceNow] < -refreshTokenTTL) {
        [self.activeSessions removeObjectForKey:foundSession.sessionID];
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidGrant
                                         userInfo:@{NSLocalizedDescriptionKey: @"Refresh token expired"}];
        completion(nil, error);
        return;
    }
    
    // Issue new access token and rotate refresh token
    NSString *newAccessToken = [foundSession refreshAccessToken];
    
    if (completion) {
        completion(newAccessToken, nil);
    }
}

#pragma mark - Security Administration

- (nullable NSArray<NSDictionary *> *)listSessionsForDid:(NSString *)did error:(NSError **)error {
    return [self.database listSessionsForDid:did error:error];
}

- (BOOL)revokeSession:(NSString *)token error:(NSError **)error {
    // Revoke in memory if present
    dispatch_sync(self.sessionQueue, ^{
        NSString *foundSessionId = nil;
        for (Session *session in self.activeSessions.allValues) {
            if ([PDSSecurityCompare constantTimeEqualString:session.refreshToken string:token]) {
                foundSessionId = session.sessionID;
                break;
            }
        }
        if (foundSessionId) {
            [self.activeSessions removeObjectForKey:foundSessionId];
        }
    });

    return [self.database revokeSession:token error:error];
}

- (BOOL)revokeAllSessionsForDid:(NSString *)did error:(NSError **)error {
    // Revoke in memory
    dispatch_sync(self.sessionQueue, ^{
        NSMutableArray *toRemove = [NSMutableArray array];
        for (Session *session in self.activeSessions.allValues) {
            if ([session.did isEqualToString:did]) {
                [toRemove addObject:session.sessionID];
            }
        }
        [self.activeSessions removeObjectsForKeys:toRemove];
    });

    return [self.database revokeAllSessionsForDid:did error:error];
}

- (nullable NSArray<NSDictionary *> *)listAppPasswordsForDid:(NSString *)did error:(NSError **)error {
    return [self.database listAppPasswordsForDid:did error:error];
}

- (BOOL)revokeAppPassword:(NSString *)passwordId forDid:(NSString *)did error:(NSError **)error {
    return [self.database revokeAppPassword:passwordId forDid:did error:error];
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

    // Trim potential trailing '+' or spaces (common URL encoding artifacts)
    identity = [identity stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" +"]];
    BOOL isDID = [identity hasPrefix:@"did:"];
    BOOL looksLikeEmail = [identity containsString:@"@"];
    PDS_LOG_AUTH_DEBUG(@"Resolving identity (is_did=%@, looks_like_email=%@)", @(isDID), @(looksLikeEmail));

    // Check database is valid
    if (!self.database) {
        PDS_LOG_AUTH_ERROR(@"Database is nil during identity resolution");
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorServerError
                                     userInfo:@{NSLocalizedDescriptionKey: @"Database not initialized"}];
        }
        return nil;
    }

    // Local optimization: check our own database for the handle first
    if (![identity hasPrefix:@"did:"]) {
        NSError *dbError = nil;
        PDSDatabaseAccount *account = [self.database getAccountByHandle:identity error:&dbError];
        if (dbError) {
            PDS_LOG_AUTH_ERROR(@"Database error looking up handle: %@", dbError.localizedDescription ?: @"unknown error");
        }
        if (account) {
            PDS_LOG_AUTH_DEBUG(@"Found local account for handle (did=%@)", account.did ?: @"");
            return account.did;
        }
        PDS_LOG_AUTH_DEBUG(@"Account not found for handle in local database");
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

        PDS_LOG_AUTH_DEBUG(@"Resolving handle via HandleResolver");
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

        [self.handleResolver resolveHandle:identity completion:^(NSString * _Nullable did, NSError * _Nullable err) {
            resolvedDID = did;
            resolveError = err;
            dispatch_semaphore_signal(semaphore);
        }];

        if (dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) != 0) {
            PDS_LOG_AUTH_ERROR(@"Handle resolution timeout");
            if (error) *error = [NSError errorWithDomain:OAuth2ErrorDomain code:OAuth2ErrorServerError userInfo:@{NSLocalizedDescriptionKey: @"Identity resolution timeout"}];
            return nil;
        }

        PDS_LOG_AUTH_DEBUG(@"Handle resolution completed (resolved_did_present=%@)", @(resolvedDID.length > 0));

        if (resolveError) {
            if (error) *error = resolveError;
            return nil;
        }

        // Verify bidirectional resolution (ATProto requirement)
        if (resolvedDID) {
            NSDictionary *atprotoData = [self.didResolver resolveAtprotoDataForDID:resolvedDID error:error];
            NSString *verifiedHandle = atprotoData[@"handle"];

            if (verifiedHandle && ![verifiedHandle isEqualToString:identity]) {
                PDS_LOG_AUTH_ERROR(@"Handle verification failed (mismatch)");
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
