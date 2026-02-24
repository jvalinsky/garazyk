#import "Core/TID.h"
#import <Security/Security.h>

@interface TID ()
@property (nonatomic, strong) NSString *internalStringValue;
@property (nonatomic) uint64_t internalTimestamp;
@end

@implementation TID

+ (instancetype)tid {
    return [self tidWithTimestamp:0];
}

+ (instancetype)tidWithTimestamp:(uint64_t)timestamp {
    TID *tid = [[TID alloc] init];
    // ATProto TIDs are 13 characters:
    // - First 11 chars: base32-sortable timestamp (microseconds-ish)
    // - Last 2 chars: base32-sortable clock id (padded with '2')
    static uint64_t lastTimestamp = 0;
    static uint32_t timestampCount = 0;
    static uint8_t clockid = 0;
    static BOOL clockidInitialized = NO;

    uint64_t ts;
    if (timestamp > 0) {
        ts = timestamp;
    } else {
        // Match the reference JS behavior: Date.now() is milliseconds, then add a per-ms counter to get microsecond-ish.
        uint64_t nowMs = (uint64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);
        if (nowMs < lastTimestamp) {
            nowMs = lastTimestamp;
        }
        if (nowMs == lastTimestamp) {
            timestampCount += 1;
        } else {
            timestampCount = 0;
            lastTimestamp = nowMs;
        }
        ts = nowMs * 1000ULL + (uint64_t)timestampCount;
    }

    if (!clockidInitialized) {
        uint8_t rnd = 0;
        if (SecRandomCopyBytes(kSecRandomDefault, 1, &rnd) != errSecSuccess) {
            rnd = (uint8_t)arc4random();
        }
        clockid = (uint8_t)(rnd % 32);
        clockidInitialized = YES;
    }

    tid.internalTimestamp = ts;
    tid.internalStringValue = [self encodeTimestamp:ts clockid:clockid];
    return tid;
}

+ (instancetype)tidWithDate:(NSDate *)date {
    uint64_t nowMs = (uint64_t)([date timeIntervalSince1970] * 1000.0);
    return [self tidWithTimestamp:nowMs * 1000ULL];
}

+ (nullable instancetype)tidFromString:(NSString *)string {
    NSString *normalized = [[string stringByReplacingOccurrencesOfString:@"-" withString:@""] lowercaseString];
    if (normalized.length != 13) {
        return nil;
    }

    uint64_t timestamp = [self decodeTimestamp:normalized];
    if (timestamp == 0) return nil;

    TID *tid = [[TID alloc] init];
    tid.internalTimestamp = timestamp;
    tid.internalStringValue = normalized;
    return tid;
}

+ (NSString *)encodeBase32Sortable:(uint64_t)value {
    if (value == 0) {
        return @"";
    }

    uint64_t remaining = value;
    char tmp[64];
    int idx = 0;
    while (remaining > 0 && idx < (int)sizeof(tmp)) {
        uint32_t c = (uint32_t)(remaining % 32);
        tmp[idx++] = kTIDBase32Alphabet[c];
        remaining /= 32;
    }

    NSMutableString *result = [NSMutableString stringWithCapacity:(NSUInteger)idx];
    for (int i = idx - 1; i >= 0; i--) {
        [result appendFormat:@"%c", tmp[i]];
    }
    return result;
}

+ (uint64_t)decodeBase32Sortable:(NSString *)string {
    uint64_t result = 0;
    const char *alphabet = kTIDBase32Alphabet;

    for (NSUInteger i = 0; i < string.length; i++) {
        unichar uc = [string characterAtIndex:i];
        char c = (char)uc;
        const char *pos = strchr(alphabet, c);
        if (!pos) {
            return 0;
        }
        uint32_t index = (uint32_t)(pos - alphabet);
        result = result * 32ULL + (uint64_t)index;
    }

    return result;
}

+ (NSString *)encodeTimestamp:(uint64_t)timestamp clockid:(uint8_t)clockid {
    NSString *timePart = [self encodeBase32Sortable:timestamp];
    if (timePart.length > 11) {
        // Extremely large timestamp; keep last 11 chars to maintain length.
        timePart = [timePart substringFromIndex:timePart.length - 11];
    } else if (timePart.length < 11) {
        // Left pad with '2' (zero) to 11 chars to maintain invariant length.
        timePart = [[@"" stringByPaddingToLength:(11 - timePart.length) withString:@"2" startingAtIndex:0] stringByAppendingString:timePart];
    }

    NSString *clockPart = [self encodeBase32Sortable:clockid];
    if (clockPart.length > 2) {
        clockPart = [clockPart substringFromIndex:clockPart.length - 2];
    } else if (clockPart.length < 2) {
        clockPart = [[@"" stringByPaddingToLength:(2 - clockPart.length) withString:@"2" startingAtIndex:0] stringByAppendingString:clockPart];
    }

    return [timePart stringByAppendingString:clockPart];
}

+ (uint64_t)decodeTimestamp:(NSString *)string {
    if (string.length != 13) {
        return 0;
    }
    NSString *timePart = [string substringToIndex:11];
    return [self decodeBase32Sortable:timePart];
}

- (NSString *)stringValue {
    return self.internalStringValue;
}

- (uint64_t)timestamp {
    return self.internalTimestamp;
}

- (NSComparisonResult)compare:(TID *)other {
    if (self.internalTimestamp < other.internalTimestamp) {
        return NSOrderedAscending;
    } else if (self.internalTimestamp > other.internalTimestamp) {
        return NSOrderedDescending;
    }
    return NSOrderedSame;
}

- (BOOL)isBefore:(TID *)other {
    return self.internalTimestamp < other.internalTimestamp;
}

- (BOOL)isAfter:(TID *)other {
    return self.internalTimestamp > other.internalTimestamp;
}

- (id)copyWithZone:(NSZone *)zone {
    TID *copy = [[TID allocWithZone:zone] init];
    copy.internalTimestamp = self.internalTimestamp;
    copy.internalStringValue = self.internalStringValue;
    return copy;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.internalStringValue forKey:@"stringValue"];
    [coder encodeInt64:self.internalTimestamp forKey:@"timestamp"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _internalStringValue = [coder decodeObjectOfClass:[NSString class] forKey:@"stringValue"];
        _internalTimestamp = [coder decodeInt64ForKey:@"timestamp"];
    }
    return self;
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[TID class]]) return NO;
    return [self.internalStringValue isEqualToString:((TID *)object).internalStringValue];
}

- (NSUInteger)hash {
    return self.internalStringValue.hash;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"TID(%@)", self.internalStringValue];
}

@end
