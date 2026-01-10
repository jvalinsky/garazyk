#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CryptoUtils : NSObject

+ (nullable NSData *)hmacSHA1WithKey:(NSData *)key data:(NSData *)data;
+ (nullable NSData *)hmacSHA256WithKey:(NSData *)key data:(NSData *)data;
+ (nullable NSData *)sha256:(NSData *)data;
+ (nullable NSData *)randomBytes:(NSUInteger)length;
+ (NSString *)hexStringFromData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
