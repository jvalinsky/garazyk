#import "Core/TID.h"

@interface TID ()
@property (nonatomic, strong) NSString *internalStringValue;
@property (nonatomic) uint64_t internalTimestamp;
@end

@implementation TID

+ (instancetype)tid {
    return [self tidWithTimestamp:[[NSDate date] timeIntervalSince1970] * 1000000];
}

+ (instancetype)tidWithTimestamp:(uint64_t)timestamp {
    TID *tid = [[TID alloc] init];
    tid.internalTimestamp = timestamp;
    tid.internalStringValue = [self encodeTimestamp:timestamp];
    return tid;
}

+ (instancetype)tidWithDate:(NSDate *)date {
    return [self tidWithTimestamp:[date timeIntervalSince1970] * 1000000];
}

+ (nullable instancetype)tidFromString:(NSString *)string {
    if (string.length != 13) {
        return nil;
    }
    
    uint64_t timestamp = [self decodeTimestamp:string];
    if (timestamp == 0) {
        return nil;
    }
    
    TID *tid = [[TID alloc] init];
    tid.internalTimestamp = timestamp;
    tid.internalStringValue = [string lowercaseString];
    return tid;
}

+ (NSString *)encodeTimestamp:(uint64_t)timestamp {
    uint64_t remaining = timestamp;
    char buffer[14];

    for (int i = 12; i >= 0; i--) {
        uint32_t index = remaining % 32;
        buffer[i] = kTIDBase32Alphabet[index];
        remaining /= 32;
    }
    buffer[13] = '\0';

    return [NSString stringWithUTF8String:buffer];
}

+ (uint64_t)decodeTimestamp:(NSString *)string {
    uint64_t result = 0;
    
    for (NSUInteger i = 0; i < string.length; i++) {
        char c = [string characterAtIndex:i];
        uint32_t index;
        
        if (c >= '2' && c <= '7') {
            index = c - '2';
        } else if (c >= 'a' && c <= 'z') {
            index = 5 + (c - 'a');
        } else {
            return 0;
        }
        
        result = result * 32 + index;
    }
    
    return result;
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
