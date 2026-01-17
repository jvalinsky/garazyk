#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Base58 : NSObject

+ (NSString *)encode:(NSData *)data;
+ (NSData *)decode:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
