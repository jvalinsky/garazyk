#import "Identity/Base58.h"

static const char *kBase58Alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

@implementation Base58

+ (NSString *)encodeData:(NSData *)data {
    if (data.length == 0) return @"";
    
    const uint8_t *input = data.bytes;
    NSUInteger inputLen = data.length;
    
    // Count leading zeros
    NSUInteger zeros = 0;
    while (zeros < inputLen && input[zeros] == 0) {
        zeros++;
    }
    
    // Allocate enough space for base58 output
    // Base58 can be at most 138% of input length + 1
    NSUInteger outputSize = (inputLen - zeros) * 138 / 100 + 1;
    uint8_t *output = calloc(outputSize, 1);
    if (!output) return @"";
    
    NSUInteger outputLen = 0;
    
    for (NSUInteger i = zeros; i < inputLen; i++) {
        int carry = input[i];
        for (NSUInteger j = 0; j < outputLen || carry; j++) {
            if (j == outputLen) outputLen++;
            carry += 256 * output[j];
            output[j] = carry % 58;
            carry /= 58;
        }
    }
    
    // Build result string (reverse order + leading '1's for zeros)
    NSMutableString *result = [NSMutableString stringWithCapacity:zeros + outputLen];
    
    // Add '1' for each leading zero byte
    for (NSUInteger i = 0; i < zeros; i++) {
        [result appendString:@"1"];
    }
    
    // Add encoded bytes (in reverse order)
    for (NSUInteger i = outputLen; i > 0; i--) {
        [result appendFormat:@"%c", kBase58Alphabet[output[i - 1]]];
    }
    
    free(output);
    return result;
}

+ (nullable NSData *)decodeString:(NSString *)string {
    if (string.length == 0) return [NSData data];
    
    const char *input = [string UTF8String];
    NSUInteger inputLen = strlen(input);
    
    // Build reverse lookup table
    static int8_t decodeTable[256];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        memset(decodeTable, -1, sizeof(decodeTable));
        for (int i = 0; i < 58; i++) {
            decodeTable[(uint8_t)kBase58Alphabet[i]] = i;
        }
    });
    
    // Count leading '1's (which decode to zero bytes)
    NSUInteger zeros = 0;
    while (zeros < inputLen && input[zeros] == '1') {
        zeros++;
    }
    
    // Allocate output buffer
    NSUInteger outputSize = inputLen * 733 / 1000 + 1; // log(58)/log(256)
    uint8_t *output = calloc(outputSize, 1);
    if (!output) return nil;
    
    NSUInteger outputLen = 0;
    
    for (NSUInteger i = zeros; i < inputLen; i++) {
        int8_t digit = decodeTable[(uint8_t)input[i]];
        if (digit < 0) {
            free(output);
            return nil; // Invalid character
        }
        
        int carry = digit;
        for (NSUInteger j = 0; j < outputLen || carry; j++) {
            if (j == outputLen) outputLen++;
            carry += 58 * output[j];
            output[j] = carry % 256;
            carry /= 256;
        }
    }
    
    // Build result (reverse order + leading zeros)
    NSMutableData *result = [NSMutableData dataWithCapacity:zeros + outputLen];
    
    // Add zero bytes for leading '1's
    uint8_t zeroByte = 0;
    for (NSUInteger i = 0; i < zeros; i++) {
        [result appendBytes:&zeroByte length:1];
    }
    
    // Add decoded bytes (in reverse order)
    for (NSUInteger i = outputLen; i > 0; i--) {
        [result appendBytes:&output[i - 1] length:1];
    }
    
    free(output);
    return result;
}

+ (NSString *)encodeMultibase:(NSData *)data {
    return [NSString stringWithFormat:@"z%@", [self encodeData:data]];
}

+ (nullable NSData *)decodeMultibase:(NSString *)string {
    if (string.length == 0) return nil;
    
    unichar prefix = [string characterAtIndex:0];
    if (prefix != 'z') {
        return nil; // Only base58btc (z prefix) supported
    }
    
    return [self decodeString:[string substringFromIndex:1]];
}

@end
