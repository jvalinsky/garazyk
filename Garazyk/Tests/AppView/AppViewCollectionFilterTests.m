// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "AppView/Server/Config/AppViewCollectionFilter.h"

@interface AppViewCollectionFilterTests : XCTestCase
@end

@implementation AppViewCollectionFilterTests

// Empty allowlist => allow all
- (void)testEmptyAllowlistAllowsAll {
    GZAppViewCollectionFilter *f = [[GZAppViewCollectionFilter alloc] initWithAllowlist:@[]];
    XCTAssertTrue([f shouldIndexCollection:@"app.bsky.feed.post"]);
    XCTAssertTrue([f shouldIndexCollection:@"site.standard.document"]);
    XCTAssertTrue([f shouldIndexCollection:@"anything.at.all"]);
}

// Exact match
- (void)testExactMatch {
    GZAppViewCollectionFilter *f = [[GZAppViewCollectionFilter alloc] initWithAllowlist:@[
        @"site.standard.document"
    ]];
    XCTAssertTrue([f shouldIndexCollection:@"site.standard.document"]);
    XCTAssertFalse([f shouldIndexCollection:@"site.standard.publication"]);
    XCTAssertFalse([f shouldIndexCollection:@"pub.leaflet.document"]);
}

// Prefix match (trailing dot)
- (void)testPrefixMatch {
    GZAppViewCollectionFilter *f = [[GZAppViewCollectionFilter alloc] initWithAllowlist:@[
        @"site.standard."
    ]];
    XCTAssertTrue([f shouldIndexCollection:@"site.standard.document"]);
    XCTAssertTrue([f shouldIndexCollection:@"site.standard.publication"]);
    XCTAssertTrue([f shouldIndexCollection:@"site.standard.graph.subscription"]);
    XCTAssertFalse([f shouldIndexCollection:@"pub.leaflet.document"]);
    XCTAssertFalse([f shouldIndexCollection:@"app.bsky.feed.post"]);
}

// Strict prefix: "site.standard." must NOT match "site.standardX.document"
- (void)testPrefixDoesNotMatchSuperstring {
    GZAppViewCollectionFilter *f = [[GZAppViewCollectionFilter alloc] initWithAllowlist:@[
        @"site.standard."
    ]];
    // "site.standardX.document" does NOT start with "site.standard." because
    // the char after "site.standard" is 'X', not '.'
    XCTAssertFalse([f shouldIndexCollection:@"site.standardX.document"]);
}

// Multiple entries: exact + prefix
- (void)testMultipleEntries {
    GZAppViewCollectionFilter *f = [[GZAppViewCollectionFilter alloc] initWithAllowlist:@[
        @"site.standard.",
        @"pub.leaflet.document"
    ]];
    XCTAssertTrue([f shouldIndexCollection:@"site.standard.document"]);
    XCTAssertTrue([f shouldIndexCollection:@"site.standard.publication"]);
    XCTAssertTrue([f shouldIndexCollection:@"pub.leaflet.document"]);
    XCTAssertFalse([f shouldIndexCollection:@"pub.leaflet.publication"]);
    XCTAssertFalse([f shouldIndexCollection:@"blog.pckt.document"]);
}

// Empty NSID => NO
- (void)testEmptyCollection {
    GZAppViewCollectionFilter *f = [[GZAppViewCollectionFilter alloc] initWithAllowlist:@[]];
    XCTAssertFalse([f shouldIndexCollection:@""]);
    XCTAssertFalse([f shouldIndexCollection:nil]);
}

// Non-match with non-empty allowlist
- (void)testNonMatch {
    GZAppViewCollectionFilter *f = [[GZAppViewCollectionFilter alloc] initWithAllowlist:@[
        @"site.standard."
    ]];
    XCTAssertFalse([f shouldIndexCollection:@"app.bsky.feed.post"]);
    XCTAssertFalse([f shouldIndexCollection:@"pub.leaflet.document"]);
}

// Allowlist entry without trailing dot that is a prefix of the NSID
// should NOT match (only exact match for non-dot entries)
- (void)testExactEntryDoesNotPrefixMatch {
    GZAppViewCollectionFilter *f = [[GZAppViewCollectionFilter alloc] initWithAllowlist:@[
        @"site.standard"
    ]];
    // "site.standard" (no trailing dot) => exact match only
    XCTAssertTrue([f shouldIndexCollection:@"site.standard"]);
    XCTAssertFalse([f shouldIndexCollection:@"site.standard.document"]);
    XCTAssertFalse([f shouldIndexCollection:@"site.standardX"]);
}

// Allowlist with empty strings should be skipped
- (void)testEmptyStringEntriesSkipped {
    GZAppViewCollectionFilter *f = [[GZAppViewCollectionFilter alloc] initWithAllowlist:@[
        @"",
        @"site.standard."
    ]];
    XCTAssertTrue([f shouldIndexCollection:@"site.standard.document"]);
    XCTAssertFalse([f shouldIndexCollection:@"app.bsky.feed.post"]);
}

@end
