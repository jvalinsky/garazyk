#import "Auth/PKCEUtil.h"
#import <CommonCrypto/CommonDigest.h>
#if defined(__linux__) || defined(__GNUstep__)
#import <Security/Security.h>
#endif

static NSString * const kBase64URLAlphabet = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

@implementation PKCEUtil

+ (NSString *)generateCodeVerifier {
    NSData *randomData = [self randomBytes:32];
    return [self base64URLEncode:randomData];
}

+ (NSString *)generateCodeChallengeWithVerifier:(NSString *)verifier {
    NSData *verifierData = [self base64URLDecode:verifier];
    if (!verifierData) {
        return nil;
    }

    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(verifierData.bytes, (CC_LONG)verifierData.length, hash);

    NSData *hashData = [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
    return [self base64URLEncode:hashData];
}

+ (BOOL)verifyCodeChallenge:(NSString *)challenge withVerifier:(NSString *)verifier {
    NSString *expectedChallenge = [self generateCodeChallengeWithVerifier:verifier];
    return [challenge isEqualToString:expectedChallenge];
}

+ (NSData *)randomBytes:(NSUInteger)length {
    NSMutableData *data = [NSMutableData dataWithLength:length];
    int result = SecRandomCopyBytes(kSecRandomDefault, length, data.mutableBytes);
    if (result != errSecSuccess) {
        return nil;
    }
    return data;
}

+ (NSString *)base64URLEncode:(NSData *)data {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    while ([base64 hasSuffix:@"="]) {
        base64 = [base64 substringToIndex:base64.length - 1];
    }
    return base64;
}

+ (NSData *)base64URLDecode:(NSString *)string {
    NSMutableString *base64 = [string mutableCopy];
    NSUInteger remainder = base64.length % 4;
    if (remainder > 0) {
        [base64 appendString:[@"====" substringToIndex:remainder]];
    }
    base64 = [[base64 stringByReplacingOccurrencesOfString:@"-" withString:@"+"] mutableCopy];
    base64 = [[base64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"] mutableCopy];
    return [[NSData alloc] initWithBase64EncodedData:[base64 dataUsingEncoding:NSUTF8StringEncoding] options:0];
}

@end
