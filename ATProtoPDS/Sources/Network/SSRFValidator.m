#import "Network/SSRFValidator.h"
#include <arpa/inet.h>
#include <sys/socket.h>
#include <string.h>
#import <CoreFoundation/CoreFoundation.h>

NSErrorDomain const SSRFValidatorErrorDomain = @"com.atproto.pds.ssrfvalidator";

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
    if (memcmp(&ip6, &in6addr_loopback, sizeof(struct in6_addr)) == 0) return YES;
    if ((bytes[0] & 0xFE) == 0xFC) return YES;            // fc00::/7
    if (bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80) return YES; // fe80::/10
    if (memcmp(bytes, (uint8_t[]){0,0,0,0,0,0,0,0,0,0,0xFF,0xFF}, 12) == 0) {
        uint32_t ipv4;
        memcpy(&ipv4, bytes + 12, sizeof(ipv4));
        ipv4 = ntohl(ipv4);
        return [self isPrivateIPv4Address:ipv4];
    }
    return NO;
}

+ (BOOL)validateHostResolvesToPublicIP:(NSString *)hostname error:(NSError **)error {
    if (hostname.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:SSRFValidatorErrorDomain
                                         code:SSRFValidatorErrorInvalidHost
                                     userInfo:@{NSLocalizedDescriptionKey: @"Empty hostname"}];
        }
        return NO;
    }

    CFHostRef hostRef = CFHostCreateWithName(kCFAllocatorDefault, (__bridge CFStringRef)hostname);
    if (!hostRef) {
        if (error) {
            *error = [NSError errorWithDomain:SSRFValidatorErrorDomain
                                         code:SSRFValidatorErrorResolutionFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create host resolver"}];
        }
        return NO;
    }

    CFStreamError streamError;
    if (!CFHostStartInfoResolution(hostRef, kCFHostAddresses, &streamError)) {
        CFRelease(hostRef);
        if (error) {
            *error = [NSError errorWithDomain:SSRFValidatorErrorDomain
                                         code:SSRFValidatorErrorResolutionFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to resolve hostname"}];
        }
        return NO;
    }

    CFArrayRef addresses = CFHostGetAddressing(hostRef, NULL);
    if (!addresses || CFArrayGetCount(addresses) == 0) {
        CFRelease(hostRef);
        if (error) {
            *error = [NSError errorWithDomain:SSRFValidatorErrorDomain
                                         code:SSRFValidatorErrorNoAddresses
                                     userInfo:@{NSLocalizedDescriptionKey: @"No IP addresses found for hostname"}];
        }
        return NO;
    }

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
        if (addr->sa_family == AF_INET && addressLength >= (CFIndex)sizeof(struct sockaddr_in)) {
            const struct sockaddr_in *addr4 = (const struct sockaddr_in *)addr;
            uint32_t ip = ntohl(addr4->sin_addr.s_addr);
            if ([self isPrivateIPv4Address:ip]) {
                CFRelease(hostRef);
                if (error) {
                    *error = [NSError errorWithDomain:SSRFValidatorErrorDomain
                                                 code:SSRFValidatorErrorPrivateAddress
                                             userInfo:@{NSLocalizedDescriptionKey: @"Host resolves to private IPv4 address"}];
                }
                return NO;
            }
        } else if (addr->sa_family == AF_INET6 && addressLength >= (CFIndex)sizeof(struct sockaddr_in6)) {
            const struct sockaddr_in6 *addr6 = (const struct sockaddr_in6 *)addr;
            if ([self isPrivateIPv6Address:addr6->sin6_addr]) {
                CFRelease(hostRef);
                if (error) {
                    *error = [NSError errorWithDomain:SSRFValidatorErrorDomain
                                                 code:SSRFValidatorErrorPrivateAddress
                                             userInfo:@{NSLocalizedDescriptionKey: @"Host resolves to private IPv6 address"}];
                }
                return NO;
            }
        }
    }

    CFRelease(hostRef);
    return YES;
}

@end
