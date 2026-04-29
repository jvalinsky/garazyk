/*!
 @file TutorialJWTMinter.m

 @abstract ES256 JWT token creation implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "TutorialJWTMinter.h"
#import "TutorialECDSAUtils.h"
#import "TutorialBase64URL.h"

NSString * const TutorialJWTErrorDomain = @"com.atproto.tutorial.jwt";

@implementation TutorialJWTMinter

- (instancetype)initWithIssuer:(NSString *)issuer {
    self = [super init];
    if (self) {
        _issuer = [issuer copy];
        NSError *error = nil;
        _keyPair = [TutorialECDSAUtils generateKeyPairWithError:&error];
        if (!_keyPair) {
            NSLog(@"Warning: Failed to generate key pair: %@", error.localizedDescription);
        }
    }
    return self;
}

- (nullable NSString *)mintAccessTokenForDID:(NSString *)did
                                      handle:(NSString *)handle
                                      scopes:(NSArray<NSString *> *)scopes
                                       error:(NSError **)error {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSDictionary *payload = @{
        @"iss": self.issuer,
        @"sub": did,
        @"aud": self.issuer,
        @"iat": @(now),
        @"exp": @(now + 3600),  // 1 hour
        @"scope": [scopes componentsJoinedByString:@" "],
        @"handle": handle
    };
    return [self mintTokenWithPayload:payload error:error];
}

- (nullable NSString *)mintRefreshTokenForDID:(NSString *)did
                                        handle:(NSString *)handle
                                        scopes:(NSArray<NSString *> *)scopes
                                         error:(NSError **)error {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSDictionary *payload = @{
        @"iss": self.issuer,
        @"sub": did,
        @"aud": self.issuer,
        @"iat": @(now),
        @"exp": @(now + 86400 * 30),  // 30 days
        @"scope": [scopes componentsJoinedByString:@" "],
        @"handle": handle
    };
    return [self mintTokenWithPayload:payload error:error];
}

- (nullable NSString *)mintTokenWithPayload:(NSDictionary *)payload
                                      error:(NSError **)error {
    if (!self.keyPair) {
        if (error) {
            *error = [NSError errorWithDomain:TutorialJWTErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"No signing key available"}];
        }
        return nil;
    }

    // Build header with ES256 algorithm and key ID
    NSDictionary *header = @{
        @"alg": @"ES256",
        @"typ": @"JWT",
        @"kid": self.keyPair.keyID
    };

    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:error];
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:error];
    if (!headerData || !payloadData) return nil;

    NSString *headerB64 = [TutorialBase64URL encode:headerData];
    NSString *payloadB64 = [TutorialBase64URL encode:payloadData];

    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerB64, payloadB64];
    NSData *signingData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];

    // Sign with ES256
    NSData *signature = [TutorialECDSAUtils signData:signingData
                                       withPrivateKey:self.keyPair.privateJWK
                                                error:error];
    if (!signature) return nil;

    NSString *signatureB64 = [TutorialBase64URL encode:signature];
    return [NSString stringWithFormat:@"%@.%@.%@", headerB64, payloadB64, signatureB64];
}

- (NSDictionary *)toJWKS {
    if (!self.keyPair) return @{};
    return @{@"keys": @[self.keyPair.publicJWK]};
}

@end
