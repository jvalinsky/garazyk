#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ATProtoBase32 : NSObject

+ (NSString *)encodeData:(NSData *)data;
+ (nullable NSData *)decodeString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
