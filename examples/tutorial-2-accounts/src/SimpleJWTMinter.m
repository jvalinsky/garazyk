#import <Foundation/Foundation.h>
#import "SimpleJWTMinter.h"
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonHMAC.h>

@interface SimpleJWTMinter ()
@property (nonatomic, copy) NSString *issuer;
@property (nonatomic, copy) NSString *secret;
@end

@implementation SimpleJWTMinter

- (instancetype)initWithIssuer:(NSString *)issuer {
    self = [super init];
    if (!self) return nil;
    
    self.issuer = issuer;
    self.secret = @"tutorial-secret-key-do-not-use-in-production";
    
    return self;
}

- (NSString *)mintAccessTokenForDID:(NSString *)did handle:(NSString *)handle {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval exp = now + 3600;  // 1 hour
    
    NSDictionary *payload = @{
        @"iss": self.issuer,
        @"sub": did,
        @"aud": self.issuer,
        @"iat": @(now),
        @"exp": @(exp),
        @"scope": @"atproto_repo",
        @"handle": handle
    };
    
    return [self encodeJWT:payload];
}

- (NSString *)mintRefreshTokenForDID:(NSString *)did handle:(NSString *)handle {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval exp = now + (86400 * 30);  // 30 days
    
    NSDictionary *payload = @{
        @"iss": self.issuer,
        @"sub": did,
        @"aud": self.issuer,
        @"iat": @(now),
        @"exp": @(exp),
        @"scope": @"atproto_refresh",
        @"handle": handle
    };
    
    return [self encodeJWT:payload];
}

- (NSString *)encodeJWT:(NSDictionary *)payload {
    // Header
    NSDictionary *header = @{@"alg": @"HS256", @"typ": @"JWT"};
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:nil];
    NSString *headerB64 = [self base64URLEncode:headerData];
    
    // Payload
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *payloadB64 = [self base64URLEncode:payloadData];
    
    // Signature
    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerB64, payloadB64];
    NSData *signingData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];
    NSData *secretData = [self.secret dataUsingEncoding:NSUTF8StringEncoding];
    
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, secretData.bytes, secretData.length, signingData.bytes, signingData.length, digest);
    NSData *signatureData = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    NSString *signatureB64 = [self base64URLEncode:signatureData];
    
    return [NSString stringWithFormat:@"%@.%@.%@", headerB64, payloadB64, signatureB64];
}

- (NSString *)base64URLEncode:(NSData *)data {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return base64;
}

@end
