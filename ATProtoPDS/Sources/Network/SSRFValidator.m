#import "Network/SSRFValidator.h"
#include <arpa/inet.h>
#include <string.h>

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

@end
