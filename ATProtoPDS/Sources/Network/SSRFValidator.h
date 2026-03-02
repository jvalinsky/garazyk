#import <Foundation/Foundation.h>
#include <netinet/in.h>

NS_ASSUME_NONNULL_BEGIN

@interface SSRFValidator : NSObject

+ (BOOL)isPrivateIPv4Address:(uint32_t)ip;
+ (BOOL)isPrivateIPv6Address:(struct in6_addr)ip6;

@end

NS_ASSUME_NONNULL_END
