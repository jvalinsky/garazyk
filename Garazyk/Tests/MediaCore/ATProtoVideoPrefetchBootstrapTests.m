// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "MediaCore/ATProtoVideoPrefetchBootstrap.h"
#import "Lexicon/ATProtoLexiconRegistry.h"

@interface ATProtoVideoPrefetchBootstrapTests : XCTestCase
@end

@implementation ATProtoVideoPrefetchBootstrapTests

static NSString *const kCID1 = @"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu";
static NSString *const kCID2 = @"bafyreie5cvv4h45feadgeuwhbcutmh6t2ceseocckahdoe6uat64zmz454";

- (NSDictionary *)itemAtIndex:(NSInteger)i {
    NSString *cid = (i % 2 == 0) ? kCID1 : kCID2;
    return @{
        @"uri": [NSString stringWithFormat:@"at://did:plc:author/tools.garazyk.video/item%ld", (long)i],
        @"cid": cid,
        @"manifestCid": cid,
        @"playlist": [NSString stringWithFormat:@"https://origin.example/watch/did:plc:author/%@/playlist.m3u8", cid],
        @"watchBaseUrl": @"https://origin.example",
        @"firstSegmentPath": @"/720p/video.fmp4",
        @"firstSegmentRange": @{ @"offset": @0, @"length": @65536 },
        @"firstSegmentBytes": @(65536),
        @"providers": @[ @"https://origin.example" ]
    };
}

- (void)testSingleResponseYieldsNextNBootstrap {
    NSArray *inputs = @[ [self itemAtIndex:0], [self itemAtIndex:1], [self itemAtIndex:2] ];
    NSError *error = nil;
    NSDictionary *response =
        [ATProtoVideoPrefetchBootstrap responseForItems:inputs
                                              maxWindow:ATProtoVideoPrefetchDefaultWindowSize
                                                  error:&error];
    XCTAssertNotNil(response);
    XCTAssertNil(error);
    NSInteger windowSize = [response[@"windowSize"] integerValue];
    XCTAssertEqual(windowSize, 2);
    NSArray *items = response[@"items"];
    XCTAssertEqual(items.count, (NSUInteger)2);
    XCTAssertEqualObjects(items[0][@"uri"], @"at://did:plc:author/tools.garazyk.video/item0");
    XCTAssertEqualObjects(items[1][@"manifestCid"], kCID2);
    XCTAssertNotNil(items[0][@"firstSegmentPath"]);
    XCTAssertNotNil(items[0][@"providers"]);
    NSUInteger ceiling = [response[@"wasteCeilingBytes"] unsignedIntegerValue];
    XCTAssertTrue(ceiling > 0);
    XCTAssertTrue(ceiling <= ATProtoVideoPrefetchWasteCeilingBytes);
}

- (void)testEmptyItemsFails {
    NSError *error = nil;
    NSDictionary *response =
        [ATProtoVideoPrefetchBootstrap responseForItems:@[] maxWindow:2 error:&error];
    XCTAssertNil(response);
    XCTAssertNotNil(error);
}

- (void)testMissingRequiredFieldFails {
    NSError *error = nil;
    NSDictionary *bad = @{ @"uri": @"at://did:plc:x/tools.garazyk.video/y", @"cid": kCID1 };
    NSDictionary *response =
        [ATProtoVideoPrefetchBootstrap responseForItems:@[ bad ] maxWindow:2 error:&error];
    XCTAssertNil(response);
    XCTAssertNotNil(error);
}

- (void)testPrefetchWasteCeilingWhenAllSwipedPast {
    NSArray *inputs = @[ [self itemAtIndex:0], [self itemAtIndex:1] ];
    NSError *error = nil;
    NSDictionary *response =
        [ATProtoVideoPrefetchBootstrap responseForItems:inputs maxWindow:2 error:&error];
    XCTAssertNotNil(response);
    NSArray *items = response[@"items"];
    NSUInteger waste =
        [ATProtoVideoPrefetchBootstrap prefetchWasteBytesForItems:items playedCount:0];
    XCTAssertEqual(waste, (NSUInteger)(65536ULL * 2ULL));
    XCTAssertTrue(waste <= ATProtoVideoPrefetchWasteCeilingBytes);
    NSUInteger wasteOnePlayed =
        [ATProtoVideoPrefetchBootstrap prefetchWasteBytesForItems:items playedCount:1];
    XCTAssertEqual(wasteOnePlayed, (NSUInteger)65536ULL);
    NSUInteger wasteAllPlayed =
        [ATProtoVideoPrefetchBootstrap prefetchWasteBytesForItems:items playedCount:2];
    XCTAssertEqual(wasteAllPlayed, (NSUInteger)0);
}

- (void)testBootstrapReducesDiscoveryRTTsAcrossConsecutivePlays {
    NSInteger naive =
        [ATProtoVideoPrefetchBootstrap discoveryRTTCountForPlayCount:2 usingBootstrap:NO];
    NSInteger boot =
        [ATProtoVideoPrefetchBootstrap discoveryRTTCountForPlayCount:2 usingBootstrap:YES];
    XCTAssertEqual(naive, 6);
    XCTAssertEqual(boot, 1);
    XCTAssertTrue(boot < naive);
}

- (void)testLexiconQueryIsRegistered {
    NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
    NSString *path = [cwd stringByAppendingPathComponent:@"Garazyk/Resources/lexicons"];
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] || !isDir) {
        XCTSkip(@"Cannot find Garazyk/Resources/lexicons directory");
    }
    ATProtoLexiconRegistry *registry = [[ATProtoLexiconRegistry alloc] init];
    NSError *error = nil;
    XCTAssertTrue([registry loadLexiconsFromDirectory:path error:&error]);
    XCTAssertTrue([registry hasSchemaForNSID:@"xyz.garazyk.video.getPrefetchBootstrap"]);
    XCTAssertTrue([registry hasSchemaForNSID:@"tools.garazyk.video.defs"]);
}

@end
