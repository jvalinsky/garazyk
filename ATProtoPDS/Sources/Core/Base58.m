#import "Base58.h"

// Base58BTC alphabet
static const char *const kBase58Alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
static const int8_t kBase58Map[128] = {
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    -1, 0, 1, 2, 3, 4, 5, 6, 7, 8,-1,-1,-1,-1,-1,-1,
    -1, 9,10,11,12,13,14,15,16,-1,17,18,19,20,21,-1,
    22,23,24,25,26,27,28,29,30,31,32,-1,-1,-1,-1,-1,
    -1,33,34,35,36,37,38,39,40,41,42,43,-1,44,45,46,
    47,48,49,50,51,52,53,54,55,56,57,-1,-1,-1,-1,-1
};

@implementation Base58

+ (NSString *)encode:(NSData *)data {
    if (data.length == 0) return @"";
    if (data.length > 64 * 1024) return nil;
    
    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    
    // Count leading zeros
    NSUInteger zeros = 0;
    while (zeros < length && bytes[zeros] == 0) {
        zeros++;
    }
    
    // Allocate enough space
    NSUInteger size = (length - zeros) * 138 / 100 + 1;
    uint8_t *buf = calloc(size, sizeof(uint8_t));
    
    // Process the bytes
    NSUInteger i = zeros, high = size - 1;
    while (i < length) {
        NSUInteger j = size - 1;
        NSUInteger carry = bytes[i];
        while (j > high || carry != 0) {
            carry += 256 * buf[j];
            buf[j] = carry % 58;
            carry /= 58;
            if (j == 0) break;
            j--;
        }
        high = j;
        i++;
    }
    
    // Skip leading zeros in result buffer
    NSUInteger j = 0;
    while (j < size && buf[j] == 0) {
        j++;
    }
    
    NSMutableString *result = [NSMutableString stringWithCapacity:zeros + (size - j)];
    for (NSUInteger k = 0; k < zeros; k++) {
        [result appendFormat:@"%c", kBase58Alphabet[0]];
    }
    while (j < size) {
        [result appendFormat:@"%c", kBase58Alphabet[buf[j]]];
        j++;
    }
    
    free(buf);
    return result;
}

+ (NSData *)decode:(NSString *)string {
    if (string.length == 0) return [NSData data];
    if (string.length > 64 * 1024) return nil;
    
    const char *chars = string.UTF8String;
    NSUInteger length = string.length;
    
    // Check characters
    for (NSUInteger i = 0; i < length; i++) {
        if (chars[i] & 0x80) return nil; // Not ASCII
        if (kBase58Map[chars[i]] == -1) return nil; // Invalid char
    }
    
    // Count leading zeros
    NSUInteger zeros = 0;
    while (zeros < length && chars[zeros] == kBase58Alphabet[0]) {
        zeros++;
    }
    
    // Allocate enough space
    NSUInteger size = (length - zeros) * 733 / 1000 + 1;
    uint8_t *buf = calloc(size, sizeof(uint8_t));
    NSUInteger high = size - 1;
    
    NSUInteger i = zeros;
    while (i < length) {
        NSUInteger j = size - 1;
        NSUInteger carry = kBase58Map[chars[i]];
        while (j > high || carry != 0) {
            carry += 58 * buf[j];
            buf[j] = carry % 256;
            carry /= 256;
            if (j == 0) break;
            j--;
        }
        high = j;
        i++;
    }
    
    // Remove leading zeros from buffer
    NSUInteger j = 0;
    while (j < size && buf[j] == 0) {
        j++;
    }
    
    NSMutableData *result = [NSMutableData dataWithCapacity:zeros + (size - j)];
    if (zeros > 0) {
        [result increaseLengthBy:zeros]; // Zero-filled by default
    }
    if (size > j) {
        [result appendBytes:&buf[j] length:size - j];
    }
    
    free(buf);
    return result;
}

@end
