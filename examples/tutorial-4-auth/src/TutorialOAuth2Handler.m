/*!
 @file TutorialOAuth2Handler.m

 @abstract OAuth 2.0 authorization server handler implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "TutorialOAuth2Handler.h"
#import "TutorialJWTMinter.h"
#import "TutorialBase64URL.h"

#if defined(__APPLE__) && !defined(GNUSTEP)
#import <CommonCrypto/CommonDigest.h>
#else
#import <openssl/sha.h>
#endif

@interface TutorialOAuth2Handler ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *authorizationCodes;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation TutorialOAuth2Handler

- (instancetype)initWithMinter:(TutorialJWTMinter *)minter {
    self = [super init];
    if (!self) return nil;
    _minter = minter;
    _authorizationCodes = [NSMutableDictionary dictionary];
    _queue = dispatch_queue_create("com.atproto.tutorial.oauth2", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (void)handleAuthorize:(NSDictionary *)params
             completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion {
    NSString *clientId = params[@"client_id"];
    NSString *redirectUri = params[@"redirect_uri"];
    NSString *scope = params[@"scope"];
    NSString *state = params[@"state"];
    NSString *codeChallenge = params[@"code_challenge"];
    NSString *codeChallengeMethod = params[@"code_challenge_method"];

    if (!clientId || !redirectUri || !scope) {
        NSError *error = [NSError errorWithDomain:@"OAuth2" code:400
                                         userInfo:@{NSLocalizedDescriptionKey: @"Missing required parameters"}];
        completion(nil, error);
        return;
    }

    // PKCE: require code_challenge if method is S256
    if (codeChallengeMethod && ![codeChallengeMethod isEqualToString:@"S256"] && ![codeChallengeMethod isEqualToString:@"plain"]) {
        NSError *error = [NSError errorWithDomain:@"OAuth2" code:400
                                         userInfo:@{NSLocalizedDescriptionKey: @"Unsupported code_challenge_method"}];
        completion(nil, error);
        return;
    }

    // Generate authorization code
    NSString *code = [[NSUUID UUID] UUIDString];

    NSDictionary *authCodeData = @{
        @"client_id": clientId,
        @"redirect_uri": redirectUri,
        @"scope": scope,
        @"did": @"did:web:localhost:~alice",
        @"handle": @"alice",
        @"code_challenge": codeChallenge ?: @"",
        @"code_challenge_method": codeChallengeMethod ?: @"",
        @"created_at": @([[NSDate date] timeIntervalSince1970])
    };

    dispatch_sync(self.queue, ^{
        self.authorizationCodes[code] = authCodeData;
    });

    NSMutableString *redirectURL = [NSMutableString stringWithFormat:@"%@?code=%@", redirectUri, code];
    if (state) {
        [redirectURL appendFormat:@"&state=%@", state];
    }

    completion(redirectURL, nil);
}

- (void)handleToken:(NSDictionary *)params
          completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    NSString *grantType = params[@"grant_type"];

    if ([grantType isEqualToString:@"authorization_code"]) {
        [self handleAuthorizationCodeGrant:params completion:completion];
    } else if ([grantType isEqualToString:@"refresh_token"]) {
        [self handleRefreshTokenGrant:params completion:completion];
    } else {
        NSError *error = [NSError errorWithDomain:@"OAuth2" code:400
                                         userInfo:@{NSLocalizedDescriptionKey: @"Unsupported grant type"}];
        completion(nil, error);
    }
}

#pragma mark - Private

- (void)handleAuthorizationCodeGrant:(NSDictionary *)params
                           completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    NSString *code = params[@"code"];
    NSString *clientId = params[@"client_id"];
    NSString *codeVerifier = params[@"code_verifier"];

    if (!code || !clientId) {
        NSError *error = [NSError errorWithDomain:@"OAuth2" code:400
                                         userInfo:@{NSLocalizedDescriptionKey: @"Missing code or client_id"}];
        completion(nil, error);
        return;
    }

    __block NSDictionary *authCodeData = nil;
    dispatch_sync(self.queue, ^{
        authCodeData = self.authorizationCodes[code];
    });

    if (!authCodeData) {
        NSError *error = [NSError errorWithDomain:@"OAuth2" code:400
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid authorization code"}];
        completion(nil, error);
        return;
    }

    if (![authCodeData[@"client_id"] isEqualToString:clientId]) {
        NSError *error = [NSError errorWithDomain:@"OAuth2" code:400
                                         userInfo:@{NSLocalizedDescriptionKey: @"Client ID mismatch"}];
        completion(nil, error);
        return;
    }

    // PKCE verification
    NSString *expectedChallenge = authCodeData[@"code_challenge"];
    NSString *challengeMethod = authCodeData[@"code_challenge_method"];

    if (expectedChallenge.length > 0 && codeVerifier) {
        NSString *computedChallenge;
        if ([challengeMethod isEqualToString:@"S256"]) {
            // S256: BASE64URL(SHA256(code_verifier))
            NSData *verifierData = [codeVerifier dataUsingEncoding:NSUTF8StringEncoding];
            unsigned char digest[32];
#if defined(__APPLE__) && !defined(GNUSTEP)
            CC_SHA256(verifierData.bytes, (CC_LONG)verifierData.length, digest);
#else
            SHA256(verifierData.bytes, verifierData.length, digest);
#endif
            computedChallenge = [TutorialBase64URL encode:[NSData dataWithBytes:digest length:32]];
        } else {
            // plain: code_challenge == code_verifier
            computedChallenge = codeVerifier;
        }

        if (![computedChallenge isEqualToString:expectedChallenge]) {
            NSError *error = [NSError errorWithDomain:@"OAuth2" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"PKCE verification failed"}];
            completion(nil, error);
            return;
        }
    }

    // Generate ES256-signed tokens
    NSString *did = authCodeData[@"did"];
    NSString *handle = authCodeData[@"handle"];
    NSString *scope = authCodeData[@"scope"];

    NSError *mintError = nil;
    NSString *accessToken = [self.minter mintAccessTokenForDID:did
                                                       handle:handle
                                                       scopes:@[scope]
                                                        error:&mintError];
    if (!accessToken) {
        completion(nil, mintError);
        return;
    }

    NSString *refreshToken = [self.minter mintRefreshTokenForDID:did
                                                          handle:handle
                                                          scopes:@[@"atproto_refresh"]
                                                           error:&mintError];
    if (!refreshToken) {
        completion(nil, mintError);
        return;
    }

    // Consume authorization code
    dispatch_sync(self.queue, ^{
        [self.authorizationCodes removeObjectForKey:code];
    });

    NSDictionary *result = @{
        @"access_token": accessToken,
        @"refresh_token": refreshToken,
        @"token_type": @"Bearer",
        @"expires_in": @3600,
        @"scope": scope
    };

    completion(result, nil);
}

- (void)handleRefreshTokenGrant:(NSDictionary *)params
                     completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    NSString *refreshToken = params[@"refresh_token"];

    if (!refreshToken) {
        NSError *error = [NSError errorWithDomain:@"OAuth2" code:400
                                         userInfo:@{NSLocalizedDescriptionKey: @"Missing refresh_token"}];
        completion(nil, error);
        return;
    }

    // In a real implementation, we would verify the refresh token JWT
    // and extract the subject DID and handle.
    // For this tutorial, we mint a new access token for the demo user.
    NSError *mintError = nil;
    NSString *accessToken = [self.minter mintAccessTokenForDID:@"did:web:localhost:~alice"
                                                        handle:@"alice"
                                                        scopes:@[@"atproto_repo"]
                                                         error:&mintError];
    if (!accessToken) {
        completion(nil, mintError);
        return;
    }

    NSDictionary *result = @{
        @"access_token": accessToken,
        @"token_type": @"Bearer",
        @"expires_in": @3600
    };

    completion(result, nil);
}

@end
