#import "Auth/TOTPGenerator.h"
#import "Auth/CryptoUtils.h"

@interface TOTPGenerator ()
@property (nonatomic, strong) NSData *secret;
@property (nonatomic, assign) NSUInteger digits;
@property (nonatomic, assign) NSTimeInterval period;
@property (nonatomic, copy) NSString *algorithm;
@end

@implementation TOTPGenerator

- (instancetype)initWithSecret:(NSData *)secret
                        digits:(NSUInteger)digits
                        period:(NSTimeInterval)period
                     algorithm:(NSString *)algorithm {
    self = [super init];
    if (self) {
        _secret = secret;
        _digits = digits;
        _period = period;
        _algorithm = algorithm;
    }
    return self;
}

- (instancetype)initWithSecret:(NSData *)secret {
    return [self initWithSecret:secret digits:6 period:30.0 algorithm:@"SHA1"];
}

- (nullable NSString *)generateOTP {
    return [self generateOTPForDate:[NSDate date]];
}

- (nullable NSString *)generateOTPForDate:(NSDate *)date {
    if (!_secret || _period <= 0) return nil;
    
    // 1. Calculate counter T
    NSTimeInterval timestamp = [date timeIntervalSince1970];
    uint64_t counter = (uint64_t)(timestamp / _period);
    
    // 2. Convert counter to big-endian (network byte order) 8 bytes
    counter = CFSwapInt64HostToBig(counter);
    NSData *counterData = [NSData dataWithBytes:&counter length:sizeof(counter)];
    
    // 3. HMAC-SHA1
    NSData *hash = [CryptoUtils hmacSHA1WithKey:_secret data:counterData];
    if (!hash) return nil;
    
    const uint8_t *hashBytes = hash.bytes;
    
    // 4. Dynamic Truncation
    int offset = hashBytes[hash.length - 1] & 0x0f;
    
    int binary = ((hashBytes[offset] & 0x7f) << 24) |
                 ((hashBytes[offset + 1] & 0xff) << 16) |
                 ((hashBytes[offset + 2] & 0xff) << 8) |
                 (hashBytes[offset + 3] & 0xff);
    
    // 5. Compute OTP
    int otp = binary % (int)pow(10, _digits);
    
    // 6. Format
    NSString *format = [NSString stringWithFormat:@"%%0%lulu", (unsigned long)_digits];
    return [NSString stringWithFormat:format, (unsigned long)otp];
}

@end
