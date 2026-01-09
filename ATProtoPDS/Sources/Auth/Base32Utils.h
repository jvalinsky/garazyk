#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Base32Utils : NSObject

+ (nullable NSData *)dataFromBase32String:(NSString *)base32String;
+ (NSString *)base32StringFromData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
