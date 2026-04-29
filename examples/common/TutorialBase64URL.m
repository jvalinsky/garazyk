/*!
 @file TutorialBase64URL.m

 @abstract Base64URL encoding and decoding implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "TutorialBase64URL.h"

@implementation TutorialBase64URL

+ (NSString *)encode:(NSData *)data {
    if (!data) return @"";
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    // Replace URL-unsafe characters and remove padding
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return base64;
}

+ (nullable NSData *)decode:(NSString *)string {
    if (!string) return nil;
    // Restore standard base64 characters and padding
    NSMutableString *base64 = [string mutableCopy];
    [base64 replaceOccurrencesOfString:@"-" withString:@"+"
                            options:NSLiteralSearch
                            range:NSMakeRange(0, base64.length)];
    [base64 replaceOccurrencesOfString:@"_" withString:@"/"
                            options:NSLiteralSearch
                            range:NSMakeRange(0, base64.length)];
    // Add padding
    while (base64.length % 4 != 0) {
        [base64 appendString:@"="];
    }
    return [[NSData alloc] initWithBase64EncodedString:base64 options:0];
}

@end
