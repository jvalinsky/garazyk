#import "SimpleCIDGenerator.h"
#import <CommonCrypto/CommonDigest.h>

@implementation SimpleCIDGenerator

+ (NSString *)generateCIDForData:(NSData *)data {
    // SHA-256 hash
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    
    // Convert to base32 (simplified - in production use proper CID encoding)
    NSMutableString *cid = [NSMutableString stringWithString:@"bafyrei"];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [cid appendFormat:@"%02x", digest[i]];
    }
    
    return cid;
}

+ (NSString *)generateCIDForJSON:(NSDictionary *)json {
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingSortedKeys error:nil];
    return [self generateCIDForData:data];
}

@end
