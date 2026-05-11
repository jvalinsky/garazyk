// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "ATProtoBase32.h"

@implementation ATProtoBase32

+ (NSString *)encodeData:(NSData *)data {
    if (data.length == 0) return @"";

    static const char *alphabet = "abcdefghijklmnopqrstuvwxyz234567";
    NSMutableString *result = [NSMutableString stringWithCapacity:(data.length * 8 + 4) / 5];
    
    const unsigned char *input = data.bytes;
    NSUInteger length = data.length;
    NSUInteger bits = 0;
    unsigned int buffer = 0;
    
    for (NSUInteger i = 0; i < length; i++) {
        buffer = (buffer << 8) | input[i];
        bits += 8;
        while (bits >= 5) {
            bits -= 5;
            [result appendFormat:@"%c", alphabet[(buffer >> bits) & 0x1F]];
        }
    }
    
    if (bits > 0) {
        buffer <<= (5 - bits);
        [result appendFormat:@"%c", alphabet[buffer & 0x1F]];
    }
    
    return result;
}

+ (nullable NSData *)decodeString:(NSString *)string {
    if (string.length == 0) return [NSData data];
    
    static const char *alphabet = "abcdefghijklmnopqrstuvwxyz234567";
    NSMutableData *result = [NSMutableData dataWithCapacity:string.length * 5 / 8];
    
    unsigned int buffer = 0;
    int bits = 0;
    
    for (NSUInteger i = 0; i < string.length; i++) {
        unichar c = [string characterAtIndex:i];
        const char *p = strchr(alphabet, tolower(c));
        if (!p) continue; // Skip invalid characters
        
        buffer = (buffer << 5) | (p - alphabet);
        bits += 5;
        
        if (bits >= 8) {
            bits -= 8;
            uint8_t byte = (buffer >> bits) & 0xFF;
            [result appendBytes:&byte length:1];
        }
    }
    
    return result;
}

@end
