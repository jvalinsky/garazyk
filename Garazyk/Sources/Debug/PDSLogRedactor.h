#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PDSLogRedactor : NSObject

+ (NSString *)redactString:(nullable NSString *)message;
+ (NSString *)redactURLString:(nullable NSString *)urlString;

@end

NS_ASSUME_NONNULL_END
