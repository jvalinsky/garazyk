#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TOTPGenerator : NSObject

- (instancetype)initWithSecret:(NSData *)secret
                        digits:(NSUInteger)digits
                        period:(NSTimeInterval)period
                     algorithm:(NSString *)algorithm;

- (instancetype)initWithSecret:(NSData *)secret; // Defaults: 6 digits, 30s, SHA256

- (nullable NSString *)generateOTPForDate:(NSDate *)date;
- (nullable NSString *)generateOTP; // Uses [NSDate date]

@end

NS_ASSUME_NONNULL_END
