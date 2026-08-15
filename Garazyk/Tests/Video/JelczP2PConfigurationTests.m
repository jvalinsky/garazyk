// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Video/GZJelczP2PConfiguration.h"

@interface JelczP2PConfigurationTests : XCTestCase
@end

@implementation JelczP2PConfigurationTests

- (void)testP2PDefaultsOff {
    XCTAssertFalse([GZJelczP2PConfiguration isP2PEnabledInEnvironment:@{}]);
    XCTAssertFalse([GZJelczP2PConfiguration shouldWireIrohSidecarMirrorFetcherInEnvironment:@{}]);
}

- (void)testSidecarURLIgnoredWhenP2POff {
    NSDictionary *env = @{
        @"JELCZ_IROH_SIDECAR_URL": @"http://127.0.0.1:17352",
    };
    XCTAssertFalse([GZJelczP2PConfiguration isP2PEnabledInEnvironment:env]);
    XCTAssertFalse([GZJelczP2PConfiguration shouldWireIrohSidecarMirrorFetcherInEnvironment:env]);
}

- (void)testShouldWireWhenP2PAndLoopbackURL {
    NSDictionary *env = @{
        @"JELCZ_P2P": @"1",
        @"JELCZ_IROH_SIDECAR_URL": @"http://127.0.0.1:17352/",
        @"JELCZ_IROH_SIDECAR_CAPABILITY": @"sidecar-capability",
    };
    XCTAssertTrue([GZJelczP2PConfiguration isP2PEnabledInEnvironment:env]);
    XCTAssertEqualObjects([GZJelczP2PConfiguration irohSidecarHTTPBaseURLFromEnvironment:env],
                          @"http://127.0.0.1:17352");
    XCTAssertTrue([GZJelczP2PConfiguration shouldWireIrohSidecarMirrorFetcherInEnvironment:env]);
}

- (void)testDoesNotWireWithoutSidecarCapability {
    NSDictionary *env = @{
        @"JELCZ_P2P": @"1",
        @"JELCZ_IROH_SIDECAR_URL": @"http://127.0.0.1:17352/",
    };
    XCTAssertFalse([GZJelczP2PConfiguration shouldWireIrohSidecarMirrorFetcherInEnvironment:env]);
}

- (void)testRejectsNonLoopbackSidecarURL {
    NSDictionary *env = @{
        @"JELCZ_P2P": @"true",
        @"JELCZ_IROH_SIDECAR_URL": @"http://203.0.113.1:17352",
    };
    XCTAssertNil([GZJelczP2PConfiguration irohSidecarHTTPBaseURLFromEnvironment:env]);
    XCTAssertFalse([GZJelczP2PConfiguration shouldWireIrohSidecarMirrorFetcherInEnvironment:env]);
}

- (void)testTrustLanOnlyAllowsNamedComposeSidecars {
    for (NSString *url in @[ @"http://iroh-a:17352", @"http://iroh-b:17352", @"http://iroh-c:17352" ]) {
        NSDictionary *env = @{
            @"JELCZ_P2P": @"1",
            @"JELCZ_IROH_SIDECAR_TRUST_LAN": @"1",
            @"JELCZ_IROH_SIDECAR_URL": url,
        };
        XCTAssertNotNil([GZJelczP2PConfiguration irohSidecarHTTPBaseURLFromEnvironment:env]);
    }
    for (NSString *url in @[
        @"http://public.example:17352",
        @"http://169.254.169.254:17352",
        @"http://[fe80::1]:17352",
        @"http://iroh-a.rebind.example:17352",
    ]) {
        NSDictionary *env = @{
            @"JELCZ_P2P": @"1",
            @"JELCZ_IROH_SIDECAR_TRUST_LAN": @"1",
            @"JELCZ_IROH_SIDECAR_URL": url,
        };
        XCTAssertNil([GZJelczP2PConfiguration irohSidecarHTTPBaseURLFromEnvironment:env]);
    }
}

- (void)testUnixSidecarPathRequiresHTTPForwarderForJelcz {
    NSDictionary *env = @{
        @"JELCZ_P2P": @"1",
        @"JELCZ_IROH_SIDECAR_URL": @"unix:///tmp/jelcz-iroh.sock",
    };
    XCTAssertNil([GZJelczP2PConfiguration irohSidecarHTTPBaseURLFromEnvironment:env]);
    XCTAssertFalse([GZJelczP2PConfiguration shouldWireIrohSidecarMirrorFetcherInEnvironment:env]);
}

- (void)testTruthyP2PValues {
    for (NSString *value in @[ @"1", @"true", @"yes", @"on" ]) {
        XCTAssertTrue([GZJelczP2PConfiguration isP2PEnabledInEnvironment:@{ @"JELCZ_P2P": value }]);
    }
    XCTAssertFalse([GZJelczP2PConfiguration isP2PEnabledInEnvironment:@{ @"JELCZ_P2P": @"0" }]);
    XCTAssertFalse([GZJelczP2PConfiguration isP2PEnabledInEnvironment:@{ @"JELCZ_P2P": @"false" }]);
}

@end
