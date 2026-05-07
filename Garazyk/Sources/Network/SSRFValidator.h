/*!
 @file SSRFValidator.h

 @abstract Defines SSRF validation interfaces for host and address safety checks.

 @discussion Declares validation APIs used to block private, loopback, or otherwise unsafe network destinations before outbound requests are attempted. Encapsulates SSRF boundary checks for reuse.
 */

#import <Foundation/Foundation.h>
#include <netinet/in.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const SSRFValidatorErrorDomain;

typedef NS_ENUM(NSInteger, SSRFValidatorErrorCode) {
    SSRFValidatorErrorInvalidHost = 1,
    SSRFValidatorErrorResolutionFailed = 2,
    SSRFValidatorErrorNoAddresses = 3,
    SSRFValidatorErrorPrivateAddress = 4,
};

@interface SSRFValidator : NSObject

+ (BOOL)isPrivateIPv4Address:(uint32_t)ip;
+ (BOOL)isPrivateIPv6Address:(struct in6_addr)ip6;
+ (BOOL)validateHostResolvesToPublicIP:(NSString *)hostname error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
