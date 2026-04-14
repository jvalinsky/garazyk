/*!
 @file AuthCryptoBase64URL.m

 @abstract Base64URL encoding and decoding implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AuthCrypto/AuthCryptoBase64URL.h"

@implementation AuthCryptoBase64URL

+ (NSString *)encode:(NSData *)data {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    while ([base64 hasSuffix:@"="]) {
        base64 = [base64 substringToIndex:base64.length - 1];
    }
    return base64;
}

+ (nullable NSData *)decode:(NSString *)string {
    if (!string || string.length == 0) return nil;

    if ([string hasSuffix:@"="]) {
        return nil;
    }

    NSMutableString *base64 = [string mutableCopy];
    NSUInteger remainder = base64.length % 4;
    if (remainder > 0) {
        [base64 appendString:[@"====" substringToIndex:(4 - remainder)]];
    }
    [base64 replaceOccurrencesOfString:@"-" withString:@"+" options:0 range:NSMakeRange(0, base64.length)];
    [base64 replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0, base64.length)];
    return [[NSData alloc] initWithBase64EncodedData:[base64 dataUsingEncoding:NSUTF8StringEncoding] options:0];
}

@end
