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

/** Default bound on hostname resolution, in seconds. */
extern NSTimeInterval const SSRFValidatorDefaultResolutionTimeout;

/**
 * @abstract Defines SSRFValidatorErrorCode values exposed by this API.
 */
typedef NS_ENUM(NSInteger, SSRFValidatorErrorCode) {
    SSRFValidatorErrorInvalidHost = 1,
    SSRFValidatorErrorResolutionFailed = 2,
    SSRFValidatorErrorNoAddresses = 3,
    SSRFValidatorErrorPrivateAddress = 4,
    SSRFValidatorErrorResolutionTimedOut = 5,
};

/**
 * @abstract A pluggable hostname resolver: given a hostname and a timeout,
 * returns the resolved address strings (dotted IPv4 or literal IPv6) or an
 * error. Used both for the real platform resolver and to inject a
 * deterministic resolver in tests (rebinding, slow-resolver timeout cases).
 */
typedef BOOL (^SSRFResolver)(NSString *hostname,
                              NSTimeInterval timeout,
                              NSArray<NSString *> * _Nullable * _Nonnull outAddresses,
                              NSError * _Nullable * _Nullable error);

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
 * @abstract Classifies a dotted IPv4 or literal IPv6 address string using
 * the same rules as isPrivateIPv4Address:/isPrivateIPv6Address:. Returns YES
 * (private/unsafe) if the string cannot be parsed as an address at all.
 */
+ (BOOL)isPrivateAddressString:(NSString *)addressString;

/**
 * @abstract Resolves hostname and validates every returned address is
 * public. Kept for callers that only need a verdict, not the addresses to
 * pin. Uses SSRFValidatorDefaultResolutionTimeout.
 */
+ (BOOL)validateHostResolvesToPublicIP:(NSString *)hostname error:(NSError **)error;

/**
 * @abstract Resolves hostname within the given timeout and returns every
 * vetted public address. Callers pin the outbound connection to one of
 * these addresses (with failover across the rest of the set on connect
 * failure) instead of re-resolving, closing the DNS-rebinding gap between
 * validation and connection.
 */
+ (BOOL)resolvePinnedAddressesForHost:(NSString *)hostname
                               timeout:(NSTimeInterval)timeout
                             resolver:(nullable SSRFResolver)resolver
                             addresses:(NSArray<NSString *> * _Nullable * _Nonnull)outAddresses
                                 error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
