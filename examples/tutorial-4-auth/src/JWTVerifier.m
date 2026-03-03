#import "JWTVerifier.h"
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonHMAC.h>

@interface JWTVerifier ()
@property (nonatomic, copy) NSString *issuer;
@property (nonatomic, strong) NSData *publicKey;
@end

@implementation JWTVerifier

- (instancetype)initWithIssuer:(NSString *)issuer publicKey:(NSData *)publicKey {
    self = [super init];
    if (!self) return nil;
    
    self.issuer = issuer;
    self.publicKey = publicKey;
    
    return self;
}

- (nullable NSDictionary *)verifyToken:(NSString *)token error:(NSError **)error {
    NSDictionary *payload = [self extractPayload:token error:error];
    if (!payload) return nil;
    
    if (![self verifySignature:token withPublicKey:self.publicKey error:error]) {
        return nil;
    }
    
    if (![payload[@"iss"] isEqualToString:self.issuer]) {
        if (error) {
            *error = [NSError errorWithDomain:@"JWT" code:3 
                userInfo:@{NSLocalizedDescriptionKey: @"Invalid issuer"}];
        }
        return nil;
    }
    
    NSTimeInterval exp = [payload[@"exp"] doubleValue];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (exp < now) {
        if (error) {
            *error = [NSError errorWithDomain:@"JWT" code:4 
                userInfo:@{NSLocalizedDescriptionKey: @"Token expired"}];
        }
        return nil;
    }
    
    return payload;
}

- (BOOL)verifySignature:(NSString *)token withPublicKey:(NSData *)publicKey error:(NSError **)error {
    NSArray *parts = [token componentsSeparatedByString:@"."];
    if (parts.count != 3) {
        if (error) {
            *error = [NSError errorWithDomain:@"JWT" code:1 
                userInfo:@{NSLocalizedDescriptionKey: @"Invalid token format"}];
        }
        return NO;
    }
    
    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", parts[0], parts[1]];
    NSData *signingData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];
    
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, publicKey.bytes, publicKey.length, 
           signingData.bytes, signingData.length, digest);
    NSData *expectedSignature = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    NSString *expectedB64 = [self base64URLEncode:expectedSignature];
    
    if (![parts[2] isEqualToString:expectedB64]) {
        if (error) {
            *error = [NSError errorWithDomain:@"JWT" code:2 
                userInfo:@{NSLocalizedDescriptionKey: @"Invalid signature"}];
        }
        return NO;
    }
    
    return YES;
}

- (nullable NSDictionary *)extractPayload:(NSString *)token error:(NSError **)error {
    NSArray *parts = [token componentsSeparatedByString:@"."];
    if (parts.count != 3) {
        if (error) {
            *error = [NSError errorWithDomain:@"JWT" code:1 
                userInfo:@{NSLocalizedDescriptionKey: @"Invalid token format"}];
        }
        return nil;
    }
    
    NSString *payload = parts[1];
    payload = [payload stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    payload = [payload stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    
    while (payload.length % 4 != 0) {
        payload = [payload stringByAppendingString:@"="];
    }
    
    NSData *data = [[NSData alloc] initWithBase64EncodedString:payload options:0];
    if (!data) {
        if (error) {
            *error = [NSError errorWithDomain:@"JWT" code:5 
                userInfo:@{NSLocalizedDescriptionKey: @"Failed to decode payload"}];
        }
        return nil;
    }
    
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
}

- (NSString *)base64URLEncode:(NSData *)data {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return base64;
}

@end
