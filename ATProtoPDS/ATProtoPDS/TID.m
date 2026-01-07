#import "TID.h"
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>
#import <Security/Security.h>

/// TID length in characters (fixed at 13)
static const NSUInteger kTIDLength = 13;

/// Microseconds per second
static const uint64_t kMicrosecondsPerSecond = 1000000ULL;

/// Bit masks for TID components
static const uint64_t kTimestampMask = 0x001FFFFFFFFFFFFF; // 53 bits (bits 10-63)
static const uint64_t kClockIdMask = 0x00000000000003FF;   // 10 bits (bits 0-9)

@implementation TID

#pragma mark - Initialization

+ (instancetype)tid {
    return [self tidWithDate:[NSDate date]];
}

+ (instancetype)tidWithTimestamp:(uint64_t)timestamp {
    // Generate random 10-bit clock ID (0-1023)
    uint16_t clockId;
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(clockId), (uint8_t *)&clockId) != errSecSuccess) {
        // Fallback to less secure random
        clockId = (uint16_t)arc4random_uniform(1024);
    }
    clockId &= 0x03FF; // Ensure it's 10 bits
    
    // Construct 64-bit TID value
    // Top bit is always 0
    // Next 53 bits: microseconds since Unix epoch
    // Final 10 bits: clock ID
    uint64_t tidValue = ((timestamp & kTimestampMask) << 10) | clockId;
    
    // Encode as base32-sortable
    NSString *encodedString = [self base32EncodeSortable:tidValue length:kTIDLength];
    
    TID *tid = [[TID alloc] init];
    if (tid) {
        tid->_stringValue = [encodedString copy];
        tid->_timestamp = timestamp;
    }
    return tid;
}

+ (instancetype)tidWithDate:(NSDate *)date {
    // Convert to microseconds since Unix epoch
    uint64_t timestamp = (uint64_t)(date.timeIntervalSince1970 * kMicrosecondsPerSecond);
    return [self tidWithTimestamp:timestamp];
}

+ (nullable instancetype)tidFromString:(NSString *)string {
    if (!string || string.length != kTIDLength) {
        return nil;
    }
    
    // Validate character set
    NSString *alphabetString = [NSString stringWithUTF8String:kTIDBase32Alphabet];
    NSCharacterSet *validChars = [NSCharacterSet characterSetWithCharactersInString:alphabetString];
    for (NSUInteger i = 0; i < string.length; i++) {
        unichar c = [string characterAtIndex:i];
        if (![validChars characterIsMember:c]) {
            return nil;
        }
    }
    
    // Validate first character
    unichar firstChar = [string characterAtIndex:0];
    NSString *validFirstChars = @"234567abcdefghij";
    if ([validFirstChars rangeOfString:[NSString stringWithCharacters:&firstChar length:1]].location == NSNotFound) {
        return nil;
    }
    
    // Decode base32-sortable to 64-bit value
    NSNumber *decodedValue = [self base32DecodeSortable:string];
    if (!decodedValue) {
        return nil;
    }
    
    uint64_t tidValue = decodedValue.unsignedLongLongValue;
    
    // Extract timestamp (53 bits, shifted right by 10)
    uint64_t timestamp = (tidValue >> 10) & kTimestampMask;
    
    TID *tid = [[TID alloc] init];
    if (tid) {
        tid->_stringValue = [string copy];
        tid->_timestamp = timestamp;
    }
    return tid;
}

#pragma mark - Comparison

- (NSComparisonResult)compare:(TID *)other {
    if (!other) return NSOrderedDescending;
    
    if (self.timestamp < other.timestamp) {
        return NSOrderedAscending;
    } else if (self.timestamp > other.timestamp) {
        return NSOrderedDescending;
    } else {
        // Same timestamp, compare string values for tie-breaking
        return [self.stringValue compare:other.stringValue];
    }
}

- (BOOL)isBefore:(TID *)other {
    return [self compare:other] == NSOrderedAscending;
}

- (BOOL)isAfter:(TID *)other {
    return [self compare:other] == NSOrderedDescending;
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[TID class]]) return NO;
    
    TID *other = (TID *)object;
    return [self.stringValue isEqualToString:other.stringValue];
}

- (NSUInteger)hash {
    return self.stringValue.hash;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"TID(%@)", self.stringValue];
}

#pragma mark - NSCopying

- (id)copyWithZone:(nullable NSZone *)zone {
    // TID is immutable
    return self;
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.stringValue forKey:@"stringValue"];
    [coder encodeInt64:self.timestamp forKey:@"timestamp"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    NSString *stringValue = [coder decodeObjectOfClass:[NSString class] forKey:@"stringValue"];
    uint64_t timestamp = (uint64_t)[coder decodeInt64ForKey:@"timestamp"];
    
    if (!stringValue) {
        return nil;
    }
    
    self = [super init];
    if (self) {
        _stringValue = [stringValue copy];
        _timestamp = timestamp;
    }
    return self;
}

#pragma mark - Base32-Sortable Encoding/Decoding

+ (NSString *)base32EncodeSortable:(uint64_t)value length:(NSUInteger)length {
    NSMutableString *result = [NSMutableString stringWithCapacity:length];
    
    for (NSUInteger i = 0; i < length; i++) {
        NSUInteger shift = (length - 1 - i) * 5;
        NSUInteger index = (value >> shift) & 0x1F;
        [result appendFormat:@"%c", kTIDBase32Alphabet[index]];
    }
    
    return [result copy];
}

+ (NSNumber *)base32DecodeSortable:(NSString *)string {
    if (!string || string.length != kTIDLength) {
        return nil;
    }
    
    uint64_t result = 0;
    
    for (NSUInteger i = 0; i < kTIDLength; i++) {
        unichar c = [string characterAtIndex:i];
        
        const char *ptr = strchr(kTIDBase32Alphabet, (char)c);
        if (!ptr) {
            return nil; // Invalid character
        }
        
        uint8_t value = (uint8_t)(ptr - kTIDBase32Alphabet);
        result = (result << 5) | value;
    }
    
    return @(result);
}

@end