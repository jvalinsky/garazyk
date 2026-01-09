#import "Auth/Base32Utils.h"

@implementation Base32Utils

+ (nullable NSData *)dataFromBase32String:(NSString *)base32String {
    if (!base32String) return nil;
    
    // Remove padding and uppercase
    NSString *cleanString = [[base32String stringByReplacingOccurrencesOfString:@"=" withString:@""] uppercaseString];
    NSData *data = [cleanString dataUsingEncoding:NSASCIIStringEncoding];
    if (!data) return nil;
    
    const char *chars = data.bytes;
    size_t length = data.length;
    
    NSMutableData *result = [NSMutableData dataWithLength:(length * 5) / 8];
    uint8_t *resultBytes = result.mutableBytes;
    
    int buffer = 0;
    int bitsLeft = 0;
    int count = 0;
    
    for (size_t i = 0; i < length; i++) {
        char c = chars[i];
        int val = 0;
        
        if (c >= 'A' && c <= 'Z') {
            val = c - 'A';
        } else if (c >= '2' && c <= '7') {
            val = c - '2' + 26;
        } else {
            return nil; // Invalid character
        }
        
        buffer <<= 5;
        buffer |= val;
        bitsLeft += 5;
        
        if (bitsLeft >= 8) {
            resultBytes[count++] = (uint8_t)(buffer >> (bitsLeft - 8));
            bitsLeft -= 8;
        }
    }
    
    // Resize to actual length
    [result setLength:count];
    return result;
}

+ (NSString *)base32StringFromData:(NSData *)data {
    if (!data || data.length == 0) return @"";
    
    const uint8_t *bytes = data.bytes;
    size_t length = data.length;
    
    NSMutableString *result = [NSMutableString stringWithCapacity:(length * 8 + 4) / 5];
    const char *alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
    
    int buffer = 0;
    int bitsLeft = 0;
    
    for (size_t i = 0; i < length; i++) {
        buffer <<= 8;
        buffer |= bytes[i];
        bitsLeft += 8;
        
        while (bitsLeft >= 5) {
            int index = (buffer >> (bitsLeft - 5)) & 0x1F;
            [result appendFormat:@"%c", alphabet[index]];
            bitsLeft -= 5;
        }
    }
    
    if (bitsLeft > 0) {
        int index = (buffer << (5 - bitsLeft)) & 0x1F;
        [result appendFormat:@"%c", alphabet[index]];
    }
    
    // Add padding
    while (result.length % 8 != 0) {
        [result appendString:@"="];
    }
    
    return result;
}

@end
