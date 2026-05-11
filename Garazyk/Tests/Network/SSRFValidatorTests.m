// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Network/SSRFValidator.h"
#include <arpa/inet.h>

@interface SSRFValidatorTests : XCTestCase
@end

@implementation SSRFValidatorTests

#pragma mark - IPv4 Private Ranges

- (void)testPrivateIPv4_10Network {
    uint32_t ip = ntohl(inet_addr("10.0.0.1"));
    XCTAssertTrue([SSRFValidator isPrivateIPv4Address:ip]);
}

- (void)testPrivateIPv4_10NetworkUpperBound {
    uint32_t ip = ntohl(inet_addr("10.255.255.255"));
    XCTAssertTrue([SSRFValidator isPrivateIPv4Address:ip]);
}

- (void)testPrivateIPv4_172_16 {
    uint32_t ip = ntohl(inet_addr("172.16.0.1"));
    XCTAssertTrue([SSRFValidator isPrivateIPv4Address:ip]);
}

- (void)testPrivateIPv4_172_31 {
    uint32_t ip = ntohl(inet_addr("172.31.255.255"));
    XCTAssertTrue([SSRFValidator isPrivateIPv4Address:ip]);
}

- (void)testPrivateIPv4_192_168 {
    uint32_t ip = ntohl(inet_addr("192.168.0.1"));
    XCTAssertTrue([SSRFValidator isPrivateIPv4Address:ip]);
}

- (void)testPrivateIPv4_Loopback {
    uint32_t ip = ntohl(inet_addr("127.0.0.1"));
    XCTAssertTrue([SSRFValidator isPrivateIPv4Address:ip]);
}

- (void)testPrivateIPv4_LoopbackHigh {
    uint32_t ip = ntohl(inet_addr("127.255.255.255"));
    XCTAssertTrue([SSRFValidator isPrivateIPv4Address:ip]);
}

- (void)testPrivateIPv4_LinkLocal {
    uint32_t ip = ntohl(inet_addr("169.254.0.1"));
    XCTAssertTrue([SSRFValidator isPrivateIPv4Address:ip]);
}

- (void)testPrivateIPv4_ZeroNetwork {
    uint32_t ip = ntohl(inet_addr("0.0.0.0"));
    XCTAssertTrue([SSRFValidator isPrivateIPv4Address:ip]);
}

- (void)testPrivateIPv4_CGNAT {
    uint32_t ip = ntohl(inet_addr("100.64.0.1"));
    XCTAssertTrue([SSRFValidator isPrivateIPv4Address:ip]);
}

- (void)testPrivateIPv4_IETF_Protocol {
    uint32_t ip = ntohl(inet_addr("192.0.0.1"));
    XCTAssertTrue([SSRFValidator isPrivateIPv4Address:ip]);
}

- (void)testPrivateIPv4_TestNet1 {
    uint32_t ip = ntohl(inet_addr("192.0.2.1"));
    XCTAssertTrue([SSRFValidator isPrivateIPv4Address:ip]);
}

- (void)testPrivateIPv4_TestNet2 {
    uint32_t ip = ntohl(inet_addr("198.51.100.1"));
    XCTAssertTrue([SSRFValidator isPrivateIPv4Address:ip]);
}

- (void)testPrivateIPv4_TestNet3 {
    uint32_t ip = ntohl(inet_addr("203.0.113.1"));
    XCTAssertTrue([SSRFValidator isPrivateIPv4Address:ip]);
}

- (void)testPrivateIPv4_Multicast {
    uint32_t ip = ntohl(inet_addr("224.0.0.1"));
    XCTAssertTrue([SSRFValidator isPrivateIPv4Address:ip]);
}

- (void)testPrivateIPv4_Reserved {
    uint32_t ip = ntohl(inet_addr("240.0.0.1"));
    XCTAssertTrue([SSRFValidator isPrivateIPv4Address:ip]);
}

#pragma mark - IPv4 Public Addresses

- (void)testPublicIPv4_GoogleDNSReturnsFalse {
    uint32_t ip = ntohl(inet_addr("8.8.8.8"));
    XCTAssertFalse([SSRFValidator isPrivateIPv4Address:ip]);
}

- (void)testPublicIPv4_CloudflareReturnsFalse {
    uint32_t ip = ntohl(inet_addr("1.1.1.1"));
    XCTAssertFalse([SSRFValidator isPrivateIPv4Address:ip]);
}

- (void)testPublicIPv4_OpenDNSReturnsFalse {
    uint32_t ip = ntohl(inet_addr("208.67.222.222"));
    XCTAssertFalse([SSRFValidator isPrivateIPv4Address:ip]);
}

- (void)testPublicIPv4_172_32ReturnsFalse {
    uint32_t ip = ntohl(inet_addr("172.32.0.1"));
    XCTAssertFalse([SSRFValidator isPrivateIPv4Address:ip]);
}

#pragma mark - IPv6

- (void)testPrivateIPv6_Loopback {
    struct in6_addr ip6 = in6addr_loopback;
    XCTAssertTrue([SSRFValidator isPrivateIPv6Address:ip6]);
}

- (void)testPrivateIPv6_ULA {
    struct in6_addr ip6 = {};
    ip6.s6_addr[0] = 0xFC;
    ip6.s6_addr[1] = 0x00;
    XCTAssertTrue([SSRFValidator isPrivateIPv6Address:ip6]);
}

- (void)testPrivateIPv6_ULA_FD {
    struct in6_addr ip6 = {};
    ip6.s6_addr[0] = 0xFD;
    ip6.s6_addr[1] = 0x12;
    XCTAssertTrue([SSRFValidator isPrivateIPv6Address:ip6]);
}

- (void)testPrivateIPv6_LinkLocal {
    struct in6_addr ip6 = {};
    ip6.s6_addr[0] = 0xFE;
    ip6.s6_addr[1] = 0x80;
    XCTAssertTrue([SSRFValidator isPrivateIPv6Address:ip6]);
}

- (void)testPrivateIPv6_MappedPrivateIPv4 {
    struct in6_addr ip6 = {};
    memset(ip6.s6_addr, 0, 10);
    ip6.s6_addr[10] = 0xFF;
    ip6.s6_addr[11] = 0xFF;
    // 10.0.0.1 in network byte order
    ip6.s6_addr[12] = 10;
    ip6.s6_addr[13] = 0;
    ip6.s6_addr[14] = 0;
    ip6.s6_addr[15] = 1;
    XCTAssertTrue([SSRFValidator isPrivateIPv6Address:ip6]);
}

- (void)testPublicIPv6_MappedPublicIPv4ReturnsFalse {
    struct in6_addr ip6 = {};
    memset(ip6.s6_addr, 0, 10);
    ip6.s6_addr[10] = 0xFF;
    ip6.s6_addr[11] = 0xFF;
    // 8.8.8.8 in network byte order
    ip6.s6_addr[12] = 8;
    ip6.s6_addr[13] = 8;
    ip6.s6_addr[14] = 8;
    ip6.s6_addr[15] = 8;
    XCTAssertFalse([SSRFValidator isPrivateIPv6Address:ip6]);
}

- (void)testPublicIPv6_GlobalUnicastReturnsFalse {
    struct in6_addr ip6 = {};
    ip6.s6_addr[0] = 0x20;
    ip6.s6_addr[1] = 0x01;
    XCTAssertFalse([SSRFValidator isPrivateIPv6Address:ip6]);
}

@end
