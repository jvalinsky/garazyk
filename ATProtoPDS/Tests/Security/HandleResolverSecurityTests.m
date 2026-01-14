#import <XCTest/XCTest.h>
#import "Identity/HandleResolver.h"
#import <arpa/inet.h>

@interface HandleResolver (Testing)
- (BOOL)isPrivateIPv4Address:(uint32_t)ip;
- (BOOL)isPrivateIPv6Address:(struct in6_addr)ip6;
@end

@interface HandleResolverSecurityTests : XCTestCase
@property (nonatomic, strong) HandleResolver *resolver;
@end

@implementation HandleResolverSecurityTests

- (void)setUp {
    [super setUp];
    self.resolver = [[HandleResolver alloc] init];
}

- (void)testPrivateIPv4Ranges {
    // 127.0.0.1 (Loopback)
    XCTAssertTrue([self checkIPv4:"127.0.0.1"], @"127.0.0.1 should be private");
    
    // 10.0.0.1 (Private)
    XCTAssertTrue([self checkIPv4:"10.0.0.1"], @"10.0.0.1 should be private");
    
    // 172.16.0.1 (Private)
    XCTAssertTrue([self checkIPv4:"172.16.0.1"], @"172.16.0.1 should be private");
    XCTAssertTrue([self checkIPv4:"172.31.255.255"], @"172.31.255.255 should be private");
    
    // 192.168.0.1 (Private)
    XCTAssertTrue([self checkIPv4:"192.168.0.1"], @"192.168.0.1 should be private");
    
    // 169.254.1.1 (Link-local)
    XCTAssertTrue([self checkIPv4:"169.254.1.1"], @"169.254.1.1 should be private");
    
    // 0.0.0.0 (Current network)
    XCTAssertTrue([self checkIPv4:"0.0.0.0"], @"0.0.0.0 should be private");
    
    // 8.8.8.8 (Public)
    XCTAssertFalse([self checkIPv4:"8.8.8.8"], @"8.8.8.8 should be public");
}

- (void)testPrivateIPv6Ranges {
    // ::1 (Loopback)
    XCTAssertTrue([self checkIPv6:"::1"], @"::1 should be private");
    
    // fc00::1 (Unique Local)
    XCTAssertTrue([self checkIPv6:"fc00::1"], @"fc00::1 should be private");
    
    // fe80::1 (Link-local)
    XCTAssertTrue([self checkIPv6:"fe80::1"], @"fe80::1 should be private");
    
    // IPv4-mapped private
    XCTAssertTrue([self checkIPv6:"::ffff:127.0.0.1"], @"IPv4-mapped loopback should be private");
    
    // 2001:4860:4860::8888 (Public - Google DNS)
    XCTAssertFalse([self checkIPv6:"2001:4860:4860::8888"], @"Google DNS IPv6 should be public");
}

#pragma mark - Helpers

- (BOOL)checkIPv4:(const char *)ipStr {
    struct in_addr addr;
    inet_pton(AF_INET, ipStr, &addr);
    uint32_t ip = ntohl(addr.s_addr);
    return [self.resolver isPrivateIPv4Address:ip];
}

- (BOOL)checkIPv6:(const char *)ipStr {
    struct in6_addr addr;
    inet_pton(AF_INET6, ipStr, &addr);
    return [self.resolver isPrivateIPv6Address:addr];
}

@end
