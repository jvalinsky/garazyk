#import "Security/PDSSecurityCompare.h"

@implementation PDSSecurityCompare

+ (BOOL)constantTimeEqualData:(NSData *)a data:(NSData *)b {
    if (a == nil && b == nil) {
        return YES;
    }
    if (a == nil || b == nil) {
        return NO;
    }

    const uint8_t *aBytes = a.bytes;
    const uint8_t *bBytes = b.bytes;
    NSUInteger maxLen = MAX(a.length, b.length);
    volatile uint8_t diff = (uint8_t)(a.length ^ b.length);

    for (NSUInteger i = 0; i < maxLen; i++) {
        uint8_t aByte = i < a.length ? aBytes[i] : 0;
        uint8_t bByte = i < b.length ? bBytes[i] : 0;
        diff |= (uint8_t)(aByte ^ bByte);
    }

    return diff == 0;
}

+ (BOOL)constantTimeEqualString:(NSString *)a string:(NSString *)b {
    if (a == nil && b == nil) {
        return YES;
    }
    if (a == nil || b == nil) {
        return NO;
    }

    NSData *aData = [a dataUsingEncoding:NSUTF8StringEncoding];
    NSData *bData = [b dataUsingEncoding:NSUTF8StringEncoding];
    if (!aData || !bData) {
        return NO;
    }
    return [self constantTimeEqualData:aData data:bData];
}

@end
