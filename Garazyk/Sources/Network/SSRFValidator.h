// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file SSRFValidator.h

 @abstract Defines SSRF validation interfaces for host and address safety checks.

 @discussion Declares validation APIs used to block private, loopback, or otherwise unsafe network destinations before outbound requests are attempted. Encapsulates SSRF boundary checks for reuse.
 */

#import <Foundation/Foundation.h>
#include <netinet/in.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const SSRFValidatorErrorDomain;

/**
 * @abstract Defines SSRFValidatorErrorCode values exposed by this API.
 */
typedef NS_ENUM(NSInteger, SSRFValidatorErrorCode) {
    SSRFValidatorErrorInvalidHost = 1,
    SSRFValidatorErrorResolutionFailed = 2,
    SSRFValidatorErrorNoAddresses = 3,
    SSRFValidatorErrorPrivateAddress = 4,
};

/**
 * @abstract Declares the SSRFValidator public API.
 */
@interface SSRFValidator : NSObject

/**
 * @abstract Performs the isPrivateIPv4Address operation.
 */
+ (BOOL)isPrivateIPv4Address:(uint32_t)ip;
/**
 * @abstract Performs the isPrivateIPv6Address operation.
 */
+ (BOOL)isPrivateIPv6Address:(struct in6_addr)ip6;
/**
 * @abstract Performs the validateHostResolvesToPublicIP operation.
 */
+ (BOOL)validateHostResolvesToPublicIP:(NSString *)hostname error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
