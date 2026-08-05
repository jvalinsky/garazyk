// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file SSRFValidator.m

 @abstract Implements SSRF protection checks for host resolution and address classification.

 @discussion Performs hostname and IP-level safety evaluation to reject non-public or disallowed targets. Provides security guard decisions used by network callers prior to external fetch operations.
 */

#import "Network/SSRFValidator.h"
#include <arpa/inet.h>
#include <sys/socket.h>
#include <string.h>
#include <netdb.h>

#if defined(__APPLE__)
#import <CoreFoundation/CoreFoundation.h>
#endif

NSErrorDomain const SSRFValidatorErrorDomain = @"com.atproto.pds.ssrfvalidator";
NSTimeInterval const SSRFValidatorDefaultResolutionTimeout = 5.0;

@interface ATProtoSSRFResolutionResult : NSObject
@property (nonatomic, assign) BOOL succeeded;
@property (nonatomic, strong, nullable) NSArray<NSString *> *addresses;
@property (nonatomic, strong, nullable) NSError *error;
@end

@implementation ATProtoSSRFResolutionResult
@end

@implementation SSRFValidator

+ (BOOL)isPrivateIPv4Address:(uint32_t)ip {
    if ((ip & 0xFF000000) == 0x0A000000) return YES;      // 10.0.0.0/8
    if ((ip & 0xFFF00000) == 0xAC100000) return YES;      // 172.16.0.0/12
    if ((ip & 0xFFFF0000) == 0xC0A80000) return YES;      // 192.168.0.0/16
    if ((ip & 0xFF000000) == 0x7F000000) return YES;      // 127.0.0.0/8
    if ((ip & 0xFFFF0000) == 0xA9FE0000) return YES;      // 169.254.0.0/16
    if ((ip & 0xFF000000) == 0x00000000) return YES;      // 0.0.0.0/8
    if ((ip & 0xFFC00000) == 0x64400000) return YES;      // 100.64.0.0/10
    if ((ip & 0xFFFFFF00) == 0xC0000000) return YES;      // 192.0.0.0/24
    if ((ip & 0xFFFFFF00) == 0xC0000200) return YES;      // 192.0.2.0/24
    if ((ip & 0xFFFFFF00) == 0xC6336400) return YES;      // 198.51.100.0/24
    if ((ip & 0xFFFFFF00) == 0xCB007100) return YES;      // 203.0.113.0/24
    if ((ip & 0xF0000000) == 0xE0000000) return YES;      // 224.0.0.0/4
    if ((ip & 0xF0000000) == 0xF0000000) return YES;      // 240.0.0.0/4
    return NO;
}

+ (BOOL)isPrivateIPv6Address:(struct in6_addr)ip6 {
    const uint8_t *bytes = ip6.s6_addr;

    static const uint8_t kUnspecified[16] = {0};
    if (memcmp(bytes, kUnspecified, sizeof(kUnspecified)) == 0) return YES; // :: (unspecified)

    if (memcmp(&ip6, &in6addr_loopback, sizeof(struct in6_addr)) == 0) return YES;
    if ((bytes[0] & 0xFE) == 0xFC) return YES;            // fc00::/7
    if (bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80) return YES; // fe80::/10

    // IPv4-mapped IPv6 ::ffff:0:0/96
    if (memcmp(bytes, (uint8_t[]){0,0,0,0,0,0,0,0,0,0,0xFF,0xFF,0,0,0,0}, 12) == 0) {
        uint32_t ipv4;
        memcpy(&ipv4, bytes + 12, sizeof(ipv4));
        ipv4 = ntohl(ipv4);
        return [self isPrivateIPv4Address:ipv4];
    }

    // NAT64 64:ff9b::/96 -- embedded IPv4 occupies the low 32 bits.
    static const uint8_t kNAT64Prefix[12] = {0x00, 0x64, 0xFF, 0x9B, 0, 0, 0, 0, 0, 0, 0, 0};
    if (memcmp(bytes, kNAT64Prefix, sizeof(kNAT64Prefix)) == 0) {
        uint32_t ipv4;
        memcpy(&ipv4, bytes + 12, sizeof(ipv4));
        ipv4 = ntohl(ipv4);
        return [self isPrivateIPv4Address:ipv4];
    }

    // 6to4 2002::/16 -- embedded IPv4 occupies bytes 2-5 (2002:V4ADDR::/48).
    if (bytes[0] == 0x20 && bytes[1] == 0x02) {
        uint32_t ipv4;
        memcpy(&ipv4, bytes + 2, sizeof(ipv4));
        ipv4 = ntohl(ipv4);
        return [self isPrivateIPv4Address:ipv4];
    }

    return NO;
}

+ (BOOL)isPrivateAddressString:(NSString *)addressString {
    if (addressString.length == 0) {
        return YES;
    }
    const char *cstr = [addressString UTF8String];

    struct in_addr addr4;
    if (inet_pton(AF_INET, cstr, &addr4) == 1) {
        return [self isPrivateIPv4Address:ntohl(addr4.s_addr)];
    }

    struct in6_addr addr6;
    if (inet_pton(AF_INET6, cstr, &addr6) == 1) {
        return [self isPrivateIPv6Address:addr6];
    }

    return YES; // Not a parseable address literal -- treat as unsafe.
}

+ (NSError *)errorWithCode:(SSRFValidatorErrorCode)code description:(NSString *)description {
    return [NSError errorWithDomain:SSRFValidatorErrorDomain
                                code:code
                            userInfo:@{NSLocalizedDescriptionKey: description}];
}

+ (BOOL)validateHostResolvesToPublicIP:(NSString *)hostname error:(NSError **)error {
    NSArray<NSString *> *addresses = nil;
    return [self resolvePinnedAddressesForHost:hostname
                                        timeout:SSRFValidatorDefaultResolutionTimeout
                                      resolver:nil
                                      addresses:&addresses
                                          error:error];
}

+ (BOOL)resolvePinnedAddressesForHost:(NSString *)hostname
                               timeout:(NSTimeInterval)timeout
                             resolver:(SSRFResolver)resolver
                             addresses:(NSArray<NSString *> **)outAddresses
                                 error:(NSError **)error {
    if (hostname.length == 0) {
        if (error) {
            *error = [self errorWithCode:SSRFValidatorErrorInvalidHost description:@"Empty hostname"];
        }
        return NO;
    }

    SSRFResolver effectiveResolver = resolver ?: [self platformResolver];

    ATProtoSSRFResolutionResult *resolution = [[ATProtoSSRFResolutionResult alloc] init];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray<NSString *> *resolvedAddresses = nil;
        NSError *resolverError = nil;
        resolution.succeeded = effectiveResolver(hostname, timeout,
                                                 &resolvedAddresses,
                                                 &resolverError);
        resolution.addresses = resolvedAddresses;
        resolution.error = resolverError;
        dispatch_semaphore_signal(semaphore);
    });

    long waitResult = dispatch_semaphore_wait(
        semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)));
    if (waitResult != 0) {
        if (error) {
            *error = [self errorWithCode:SSRFValidatorErrorResolutionTimedOut
                              description:@"Hostname resolution timed out"];
        }
        return NO;
    }

    NSArray<NSString *> *rawAddresses = resolution.addresses;
    NSError *resolveError = resolution.error;
    if (!resolution.succeeded) {
        if (error) {
            *error = resolveError ?: [self errorWithCode:SSRFValidatorErrorResolutionFailed
                                               description:@"Failed to resolve hostname"];
        }
        return NO;
    }

    if (rawAddresses.count == 0) {
        if (error) {
            *error = [self errorWithCode:SSRFValidatorErrorNoAddresses
                              description:@"No IP addresses found for hostname"];
        }
        return NO;
    }

    // Preserve the existing classification's verdict exactly: the whole
    // host is rejected if *any* resolved address is private, not just the
    // private ones filtered out. Only once every address clears that bar do
    // we hand the full (all-public) set back for pinning.
    for (NSString *address in rawAddresses) {
        if ([self isPrivateAddressString:address]) {
            if (error) {
                *error = [self errorWithCode:SSRFValidatorErrorPrivateAddress
                                  description:[NSString stringWithFormat:@"Host resolves to private address %@", address]];
            }
            return NO;
        }
    }

    if (outAddresses) {
        *outAddresses = [rawAddresses copy];
    }
    return YES;
}

#if defined(__APPLE__)
// Apple implementation using CFHost (CFNetwork). CFHostStartInfoResolution
// is synchronous with no built-in timeout, so it runs on a background queue
// and CFHostCancelInfoResolution aborts it if the timeout elapses.
+ (SSRFResolver)platformResolver {
    return ^BOOL(NSString *hostname, NSTimeInterval timeout,
                 NSArray<NSString *> **outAddresses, NSError **error) {
        CFHostRef hostRef = CFHostCreateWithName(kCFAllocatorDefault, (__bridge CFStringRef)hostname);
        if (!hostRef) {
            if (error) {
                *error = [self errorWithCode:SSRFValidatorErrorResolutionFailed
                                  description:@"Failed to create host resolver"];
            }
            return NO;
        }

        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        __block Boolean started = false;

        CFRetain(hostRef);
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            CFStreamError streamError;
            started = CFHostStartInfoResolution(hostRef, kCFHostAddresses, &streamError);
            dispatch_semaphore_signal(sema);
            CFRelease(hostRef);
        });

        long waitResult = dispatch_semaphore_wait(
            sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)));
        if (waitResult != 0) {
            CFHostCancelInfoResolution(hostRef, kCFHostAddresses);
            CFRelease(hostRef);
            if (error) {
                *error = [self errorWithCode:SSRFValidatorErrorResolutionTimedOut
                                  description:@"Hostname resolution timed out"];
            }
            return NO;
        }

        if (!started) {
            CFRelease(hostRef);
            if (error) {
                *error = [self errorWithCode:SSRFValidatorErrorResolutionFailed
                                  description:@"Failed to resolve hostname"];
            }
            return NO;
        }

        CFArrayRef addresses = CFHostGetAddressing(hostRef, NULL);
        if (!addresses || CFArrayGetCount(addresses) == 0) {
            CFRelease(hostRef);
            if (error) {
                *error = [self errorWithCode:SSRFValidatorErrorNoAddresses
                                  description:@"No IP addresses found for hostname"];
            }
            return NO;
        }

        NSMutableArray<NSString *> *collected = [NSMutableArray array];
        for (CFIndex i = 0; i < CFArrayGetCount(addresses); i++) {
            CFDataRef addressData = (CFDataRef)CFArrayGetValueAtIndex(addresses, i);
            if (!addressData || CFGetTypeID(addressData) != CFDataGetTypeID()) {
                continue;
            }
            const UInt8 *addressBytes = CFDataGetBytePtr(addressData);
            CFIndex addressLength = CFDataGetLength(addressData);
            if (!addressBytes || addressLength < (CFIndex)sizeof(struct sockaddr)) {
                continue;
            }

            const struct sockaddr *addr = (const struct sockaddr *)addressBytes;
            char buf[INET6_ADDRSTRLEN];
            if (addr->sa_family == AF_INET && addressLength >= (CFIndex)sizeof(struct sockaddr_in)) {
                const struct sockaddr_in *addr4 = (const struct sockaddr_in *)addr;
                if (inet_ntop(AF_INET, &addr4->sin_addr, buf, sizeof(buf))) {
                    [collected addObject:[NSString stringWithUTF8String:buf]];
                }
            } else if (addr->sa_family == AF_INET6 && addressLength >= (CFIndex)sizeof(struct sockaddr_in6)) {
                const struct sockaddr_in6 *addr6 = (const struct sockaddr_in6 *)addr;
                if (inet_ntop(AF_INET6, &addr6->sin6_addr, buf, sizeof(buf))) {
                    [collected addObject:[NSString stringWithUTF8String:buf]];
                }
            }
        }

        CFRelease(hostRef);

        if (collected.count == 0) {
            if (error) {
                *error = [self errorWithCode:SSRFValidatorErrorNoAddresses
                                  description:@"No IP addresses found for hostname"];
            }
            return NO;
        }
        if (outAddresses) {
            *outAddresses = [collected copy];
        }
        return YES;
    };
}

#else
// GNUstep/Linux implementation using getaddrinfo(). POSIX getaddrinfo has
// no cancellation primitive, so a hostile authoritative server cannot be
// aborted mid-lookup the way CFHostCancelInfoResolution allows on Apple
// platforms. The lookup runs on a background queue; if it hasn't completed
// within the timeout, this call reports a timeout and abandons it rather
// than blocking the caller for the resolver's full (potentially unbounded)
// duration. The abandoned lookup still completes and frees its own
// resources in the background; its result is simply discarded.
+ (SSRFResolver)platformResolver {
    return ^BOOL(NSString *hostname, NSTimeInterval timeout,
                 NSArray<NSString *> **outAddresses, NSError **error) {
        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        __block NSArray<NSString *> *collected = nil;
        __block int gaiErrorCode = 0;

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            struct addrinfo hints;
            memset(&hints, 0, sizeof(hints));
            hints.ai_family = AF_UNSPEC;     // IPv4 or IPv6
            hints.ai_socktype = SOCK_STREAM;
            hints.ai_protocol = IPPROTO_TCP;

            struct addrinfo *result = NULL;
            int gaiError = getaddrinfo([hostname UTF8String], NULL, &hints, &result);
            gaiErrorCode = gaiError;

            NSMutableArray<NSString *> *addrs = [NSMutableArray array];
            if (gaiError == 0 && result != NULL) {
                for (struct addrinfo *rp = result; rp != NULL; rp = rp->ai_next) {
                    char buf[INET6_ADDRSTRLEN];
                    if (rp->ai_family == AF_INET && rp->ai_addrlen >= (socklen_t)sizeof(struct sockaddr_in)) {
                        const struct sockaddr_in *addr4 = (const struct sockaddr_in *)rp->ai_addr;
                        if (inet_ntop(AF_INET, &addr4->sin_addr, buf, sizeof(buf))) {
                            [addrs addObject:[NSString stringWithUTF8String:buf]];
                        }
                    } else if (rp->ai_family == AF_INET6 && rp->ai_addrlen >= (socklen_t)sizeof(struct sockaddr_in6)) {
                        const struct sockaddr_in6 *addr6 = (const struct sockaddr_in6 *)rp->ai_addr;
                        if (inet_ntop(AF_INET6, &addr6->sin6_addr, buf, sizeof(buf))) {
                            [addrs addObject:[NSString stringWithUTF8String:buf]];
                        }
                    }
                }
                freeaddrinfo(result);
            }
            collected = [addrs copy];
            dispatch_semaphore_signal(sema);
        });

        long waitResult = dispatch_semaphore_wait(
            sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)));
        if (waitResult != 0) {
            if (error) {
                *error = [self errorWithCode:SSRFValidatorErrorResolutionTimedOut
                                  description:@"Hostname resolution timed out"];
            }
            return NO;
        }

        if (gaiErrorCode != 0) {
            if (error) {
                NSString *message = [NSString stringWithUTF8String:gai_strerror(gaiErrorCode)] ?: @"Failed to resolve hostname";
                *error = [self errorWithCode:SSRFValidatorErrorResolutionFailed description:message];
            }
            return NO;
        }
        if (collected.count == 0) {
            if (error) {
                *error = [self errorWithCode:SSRFValidatorErrorNoAddresses
                                  description:@"No IP addresses found for hostname"];
            }
            return NO;
        }

        if (outAddresses) {
            *outAddresses = collected;
        }
        return YES;
    };
}
#endif

@end
