// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Network/XrpcAppBskyGraphHelpers.h"

@interface XrpcAppBskyGraphHelpersTests : XCTestCase
@end

@implementation XrpcAppBskyGraphHelpersTests

- (void)testParseAtURI_ValidURI {
    NSString *did, *collection, *rkey;
    BOOL result = XrpcParseAtURI(@"at://did:plc:abc/app.bsky.feed.post/3k4", &did, &collection, &rkey);

    XCTAssertTrue(result);
    XCTAssertEqualObjects(did, @"did:plc:abc");
    XCTAssertEqualObjects(collection, @"app.bsky.feed.post");
    XCTAssertEqualObjects(rkey, @"3k4");
}

- (void)testParseAtURI_InvalidURI_Empty {
    NSString *did, *collection, *rkey;
    BOOL result = XrpcParseAtURI(@"", &did, &collection, &rkey);

    XCTAssertFalse(result);
}

- (void)testParseAtURI_InvalidURI_Short {
    NSString *did, *collection, *rkey;
    BOOL result = XrpcParseAtURI(@"at://did/test", &did, &collection, &rkey);

    XCTAssertFalse(result);
}

- (void)testParseAtURI_MissingScheme {
    NSString *did, *collection, *rkey;
    BOOL result = XrpcParseAtURI(@"did:plc:abc/app.bsky.feed.post/3k4", &did, &collection, &rkey);

    XCTAssertFalse(result);
}

- (void)testConstant_GraphMuteStatePreferenceType {
    XCTAssertNotNil(kXrpcGraphMuteStatePreferenceType);
    XCTAssertTrue([kXrpcGraphMuteStatePreferenceType containsString:@"graph"]);
}

@end