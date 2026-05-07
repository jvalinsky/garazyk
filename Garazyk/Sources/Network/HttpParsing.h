/*!
 @file HttpParsing.h

 @abstract Provides shared HTTP parsing types and helpers for protocol components.

 @discussion Declares parsing primitives and related utilities reused by parser and session code. Keeps parsing contracts explicit and avoids coupling to transport sockets or route handlers.
 */

#import <Foundation/Foundation.h>
#import "Network/HttpRequest.h"

NS_ASSUME_NONNULL_BEGIN

@interface HttpParsing : NSObject

+ (NSDictionary<NSString *, id> *)parseQueryString:(NSString *)queryString;
+ (NSString *)urlDecode:(NSString *)string;
+ (HttpMethod)methodFromString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
