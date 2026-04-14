#import <Foundation/Foundation.h>
#import "Network/HttpRequest.h"

NS_ASSUME_NONNULL_BEGIN

@interface HttpParsing : NSObject

+ (NSDictionary<NSString *, id> *)parseQueryString:(NSString *)queryString;
+ (NSString *)urlDecode:(NSString *)string;
+ (HttpMethod)methodFromString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
