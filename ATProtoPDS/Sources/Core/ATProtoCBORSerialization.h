#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ATProtoCBORSerialization : NSObject

+ (NSData *)encodeDataWithJSONObject:(id)obj error:(NSError **)error;
+ (id)JSONObjectWithData:(NSData *)data error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
