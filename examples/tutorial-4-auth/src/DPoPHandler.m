#import "DPoPHandler.h"
#import <CommonCrypto/CommonDigest.h>

@implementation DPoPHandler

+ (nullable NSString *)generateDPoPProof:(NSString *)method
                                     uri:(NSString *)uri
                                   nonce:(nullable NSString *)nonce
                              privateKey:(NSData *)privateKey
                               publicKey:(NSData *)publicKey
                                   error:(NSError **)error {
    NSDictionary *jwk = @{
        @"kty": @"EC",
        @"crv": @"P-256",
        @"x": [self base64URLEncode:[publicKey subdataWithRange:NSMakeRange(1, 32)]],
        @"y": [self base64URLEncode:[publicKey subdataWithRange:NSMakeRange(33, 32)]]
    };
    
    NSDictionary *header = @{
        @"typ": @"dpop+jwt",
        @"alg": @"ES256",
        @"jwk": jwk
    };
    
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSMutableDictionary *payload = [@{
        @"jti": [[NSUUID UUID] UUIDString],
        @"htm": method,
        @"htu": uri,
        @"iat": @(now),
        @"exp": @(now + 300)
    } mutableCopy];
    
    if (nonce) {
        payload[@"nonce"] = nonce;
    }
    
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:error];
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:error];
    if (!headerData || !payloadData) return nil;
    
    NSString *headerB64 = [self base64URLEncode:headerData];
    NSString *payloadB64 = [self base64URLEncode:payloadData];
    
    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerB64, payloadB64];
    NSData *signingData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];
    
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(signingData.bytes, (CC_LONG)signingData.length, digest);
    NSData *signature = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    NSString *signatureB64 = [self base64URLEncode:signature];
    
    return [NSString stringWithFormat:@"%@.%@.%@", headerB64, payloadB64, signatureB64];
}

+ (BOOL)verifyDPoPProof:(NSString *)proof
                 method:(NSString *)method
                    uri:(NSString *)uri
              publicKey:(NSData *)publicKey
                  error:(NSError **)error {
    NSArray *parts = [proof componentsSeparatedByString:@"."];
    if (parts.count != 3) {
        if (error) {
            *error = [NSError errorWithDomain:@"DPoP" code:1 
                userInfo:@{NSLocalizedDescriptionKey: @"Invalid DPoP format"}];
        }
        return NO;
    }
    
    NSString *payloadB64 = parts[1];
    payloadB64 = [payloadB64 stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    payloadB64 = [payloadB64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (payloadB64.length % 4 != 0) {
        payloadB64 = [payloadB64 stringByAppendingString:@"="];
    }
    
    NSData *payloadData = [[NSData alloc] initWithBase64EncodedString:payloadB64 options:0];
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:error];
    if (!payload) return NO;
    
    if (![payload[@"htm"] isEqualToString:method]) {
        if (error) {
            *error = [NSError errorWithDomain:@"DPoP" code:2 
                userInfo:@{NSLocalizedDescriptionKey: @"Method mismatch"}];
        }
        return NO;
    }
    
    if (![payload[@"htu"] isEqualToString:uri]) {
        if (error) {
            *error = [NSError errorWithDomain:@"DPoP" code:3 
                userInfo:@{NSLocalizedDescriptionKey: @"URI mismatch"}];
        }
        return NO;
    }
    
    NSTimeInterval iat = [payload[@"iat"] doubleValue];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - iat > 300) {
        if (error) {
            *error = [NSError errorWithDomain:@"DPoP" code:4 
                userInfo:@{NSLocalizedDescriptionKey: @"DPoP proof expired"}];
        }
        return NO;
    }
    
    return YES;
}

+ (nullable NSString *)extractThumbprint:(NSData *)publicKey error:(NSError **)error {
    NSDictionary *jwk = @{
        @"crv": @"P-256",
        @"kty": @"EC",
        @"x": [self base64URLEncode:[publicKey subdataWithRange:NSMakeRange(1, 32)]],
        @"y": [self base64URLEncode:[publicKey subdataWithRange:NSMakeRange(33, 32)]]
    };
    
    NSData *jwkData = [NSJSONSerialization dataWithJSONObject:jwk 
                                                      options:NSJSONWritingSortedKeys 
                                                        error:error];
    if (!jwkData) return nil;
    
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(jwkData.bytes, (CC_LONG)jwkData.length, digest);
    NSData *thumbprint = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    
    return [self base64URLEncode:thumbprint];
}

+ (NSString *)base64URLEncode:(NSData *)data {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return base64;
}

@end
