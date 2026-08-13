// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Video/GZJelczStreamplaceOriginHints.h"

@interface JelczStreamplaceOriginHintsTests : XCTestCase
@end

@implementation JelczStreamplaceOriginHintsTests

- (void)testMergesStreamplaceBaseFirst {
    NSArray *providers =
        [GZJelczStreamplaceOriginHints providersByMergingStreamplaceBase:@"stream.place"
                                                      existingProviders:@[ @"https://other.example/" ]];
    XCTAssertEqual(providers.count, 2u);
    XCTAssertEqualObjects(providers[0], @"https://stream.place");
    XCTAssertEqualObjects(providers[1], @"https://other.example");
}

- (void)testOriginRecordCIDMatchUsesConfiguredBase {
    NSDictionary *record = @{
        @"blob": @"bafkr4itestcid",
        @"size": @12,
        @"mimeType": @"video/mp4",
    };
    NSArray *providers =
        [GZJelczStreamplaceOriginHints providersForCIDString:@"bafkr4itestcid"
                                               originRecord:record
                                         configuredBaseURL:@"https://prod-sea0.stream.place"];
    XCTAssertEqualObjects(providers, (@[ @"https://prod-sea0.stream.place" ]));
}

- (void)testOriginRecordMismatchReturnsNil {
    NSDictionary *record = @{@"blob": @"bafkr4iother", @"size": @1, @"mimeType": @"video/mp4"};
    NSArray *providers =
        [GZJelczStreamplaceOriginHints providersForCIDString:@"bafkr4itest"
                                               originRecord:record
                                         configuredBaseURL:@"https://stream.place"];
    XCTAssertNil(providers);
}

- (void)testOriginRecordBuilder {
    NSDictionary *rec =
        [GZJelczStreamplaceOriginHints originRecordForBlobCID:@"bafkr4ix"
                                                         size:99
                                                     mimeType:@"video/mp4"];
    XCTAssertEqualObjects(rec[@"$type"], @"place.stream.media.origin");
    XCTAssertEqualObjects(rec[@"blob"], @"bafkr4ix");
    XCTAssertEqualObjects(rec[@"size"], @99);
}

@end
