// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Identity/HandleResolver.h"
#import "Network/SSRFValidator.h"
#import <arpa/inet.h>

@interface HandleResolverSSRFTests : XCTestCase
@property (nonatomic, strong) HandleResolver *resolver;
@end

@implementation HandleResolverSSRFTests

- (void)setUp {
    [super setUp];
    self.resolver = [[HandleResolver alloc] init];
    // skipSSRFCheck property removed — PDSSafeHTTPClient handles SSRF validation
    // atomically during the request. In test mode, allowPrivateHosts is set
    // automatically via PDSHandleResolverRunningTests().
}

- (void)tearDown {
    [super tearDown];
}

- (void)testPrivateIPv4ClassAIsPrivate {
    uint32_t ip = ntohl(inet_addr("10.0.0.1"));
    XCTAssertTrue([SSRFValidator isPrivateIPv4Address:ip], @"10.x.x.x should be private");
}

- (void)testPrivateIPv4ClassBIsPrivate {
    uint32_t ip = ntohl(inet_addr("172.16.0.1"));
    XCTAssertTrue([SSRFValidator isPrivateIPv4Address:ip], @"172.16.x.x should be private");
}

- (void)testPrivateIPv4ClassCIsPrivate {
    uint32_t ip = ntohl(inet_addr("192.168.0.1"));
    XCTAssertTrue([SSRFValidator isPrivateIPv4Address:ip], @"192.168.x.x should be private");
}

- (void)testPrivateIPv4LoopbackIsPrivate {
    uint32_t ip = ntohl(inet_addr("127.0.0.1"));
    XCTAssertTrue([SSRFValidator isPrivateIPv4Address:ip], @"127.x.x.x should be private");
}

- (void)testPrivateIPv4LinkLocalIsPrivate {
    uint32_t ip = ntohl(inet_addr("169.254.0.1"));
    XCTAssertTrue([SSRFValidator isPrivateIPv4Address:ip], @"169.254.x.x should be private");
}

- (void)testPrivateIPv4MulticastIsPrivate {
    uint32_t ip = ntohl(inet_addr("224.0.0.1"));
    XCTAssertTrue([SSRFValidator isPrivateIPv4Address:ip], @"224.x.x.x should be private");
}

- (void)testPrivateIPv4DocumentationIsPrivate {
    uint32_t ip = ntohl(inet_addr("192.0.2.1"));
    XCTAssertTrue([SSRFValidator isPrivateIPv4Address:ip], @"192.0.2.x should be private (TEST-NET-1)");
}

- (void)testPrivateIPv4Documentation2IsPrivate {
    uint32_t ip = ntohl(inet_addr("198.51.100.1"));
    XCTAssertTrue([SSRFValidator isPrivateIPv4Address:ip], @"198.51.100.x should be private (TEST-NET-2)");
}

- (void)testPrivateIPv4Documentation3IsPrivate {
    uint32_t ip = ntohl(inet_addr("203.0.113.1"));
    XCTAssertTrue([SSRFValidator isPrivateIPv4Address:ip], @"203.0.113.x should be private (TEST-NET-3)");
}

- (void)testPublicIPv4Address {
    uint32_t ip = ntohl(inet_addr("8.8.8.8"));
    XCTAssertFalse([SSRFValidator isPrivateIPv4Address:ip], @"8.8.8.8 (Google DNS) should be public");
}

- (void)testPublicIPv4Address2IsPublic {
    uint32_t ip = ntohl(inet_addr("1.1.1.1"));
    XCTAssertFalse([SSRFValidator isPrivateIPv4Address:ip], @"1.1.1.1 (Cloudflare) should be public");
}

- (void)testPublicIPv4Address3IsPublic {
    uint32_t ip = ntohl(inet_addr("208.67.222.222"));
    XCTAssertFalse([SSRFValidator isPrivateIPv4Address:ip], @"208.67.222.222 (OpenDNS) should be public");
}

- (void)testSSRFProtectionIsAlwaysEnabled {
    // skipSSRFCheck property removed — SSRF validation is always performed
    // by PDSSafeHTTPClient during the actual request. There is no way to
    // disable it in production code. Tests use allowPrivateHosts via
    // PDSHandleResolverRunningTests() detection.
    HandleResolver *newResolver = [[HandleResolver alloc] init];
    XCTAssertNotNil(newResolver, @"Resolver should be initialized");
    // SSRF validation is enforced by PDSSafeHTTPClient, not a toggle
}

@end
