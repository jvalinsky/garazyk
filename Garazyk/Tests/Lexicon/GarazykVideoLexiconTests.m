// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Lexicon/ATProtoLexiconRegistry.h"
#import "Lexicon/ATProtoLexiconValidator.h"

/*!
 * Lexicon validation for Garazyk-owned CA VOD records (WS12 Phase 7 / ADR 0036).
 */
@interface GarazykVideoLexiconTests : XCTestCase
@property (nonatomic, strong) ATProtoLexiconRegistry *registry;
@property (nonatomic, strong) ATProtoLexiconValidator *validator;
@end

@implementation GarazykVideoLexiconTests

static NSString *const kTestCID = @"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu";
static NSString *const kTestCID2 = @"bafyreie5cvv4h45feadgeuwhbcutmh6t2ceseocckahdoe6uat64zmz454";

- (NSString *)lexiconsDirectory {
    NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
    NSArray<NSString *> *candidates = @[
        [cwd stringByAppendingPathComponent:@"Garazyk/Resources/lexicons"],
        [cwd stringByAppendingPathComponent:@"../Garazyk/Resources/lexicons"],
        [cwd stringByAppendingPathComponent:@"../../Garazyk/Resources/lexicons"],
    ];
    for (NSString *path in candidates) {
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] && isDir) {
            return path;
        }
    }
    return nil;
}

- (void)setUp {
    [super setUp];
    self.registry = [[ATProtoLexiconRegistry alloc] init];
    NSString *path = [self lexiconsDirectory];
    if (!path) {
        return;
    }
    NSError *error = nil;
    BOOL ok = [self.registry loadLexiconsFromDirectory:path error:&error];
    XCTAssertTrue(ok);
    XCTAssertNil(error);
    self.validator = [[ATProtoLexiconValidator alloc] initWithRegistry:self.registry];
}

- (void)tearDown {
    [self.registry clearCache];
    self.validator = nil;
    self.registry = nil;
    [super tearDown];
}

- (void)requireLexiconsOrSkip {
    if (![self lexiconsDirectory] || !self.validator) {
        XCTSkip(@"Cannot find Garazyk/Resources/lexicons directory");
    }
}

- (NSDictionary *)validVideoRecord {
    return @{
        @"$type": @"tools.garazyk.video",
        @"manifest": @{
            @"$type": @"blob",
            @"ref": @{ @"$link": kTestCID },
            @"mimeType": @"application/vnd.ipld.dag-cbor",
            @"size": @4096
        },
        @"durationMs": @12000,
        @"aspectRatio": @{ @"width": @16, @"height": @9 },
        @"renditions": @[
            @{ @"name": @"720p", @"width": @1280, @"height": @720, @"bandwidth": @2500000 }
        ],
        @"compatMp4": @{
            @"$type": @"blob",
            @"ref": @{ @"$link": kTestCID2 },
            @"mimeType": @"video/mp4",
            @"size": @1000000
        },
        @"createdAt": @"2026-08-12T18:00:00.000Z"
    };
}

- (NSDictionary *)validPolicyRecord {
    return @{
        @"$type": @"tools.garazyk.video.distributionPolicy",
        @"subject": @{
            @"uri": @"at://did:plc:author/tools.garazyk.video/3jabcdef",
            @"cid": kTestCID
        },
        @"deleteAfter": @"2027-01-01T00:00:00.000Z",
        @"allowedBroadcasters": @[ @"did:web:mirror.example.com" ],
        @"createdAt": @"2026-08-12T18:00:00.000Z"
    };
}

- (NSDictionary *)validOriginRecord {
    return @{
        @"$type": @"tools.garazyk.video.origin",
        @"subject": @{
            @"uri": @"at://did:plc:author/tools.garazyk.video/3jabcdef",
            @"cid": kTestCID
        },
        @"server": @"did:web:mirror.example.com",
        @"watchBaseUrl": @"https://mirror.example.com",
        @"manifestCid": kTestCID,
        @"createdAt": @"2026-08-12T18:00:00.000Z",
        @"lastSeenAt": @"2026-08-12T18:05:00.000Z"
    };
}

- (void)testSchemasAreRegistered {
    [self requireLexiconsOrSkip];
    XCTAssertTrue([self.registry hasSchemaForNSID:@"tools.garazyk.video"]);
    XCTAssertTrue([self.registry hasSchemaForNSID:@"tools.garazyk.video.defs"]);
    XCTAssertTrue([self.registry hasSchemaForNSID:@"tools.garazyk.video.distributionPolicy"]);
    XCTAssertTrue([self.registry hasSchemaForNSID:@"tools.garazyk.video.origin"]);
    // Prerequisite: Streamplace VOD lexicons already vendored.
    XCTAssertTrue([self.registry hasSchemaForNSID:@"place.stream.video"]);
    XCTAssertTrue([self.registry hasSchemaForNSID:@"place.stream.media.track"]);
    XCTAssertTrue([self.registry hasSchemaForNSID:@"place.stream.media.origin"]);
}

- (void)testValidVideoRecordPasses {
    [self requireLexiconsOrSkip];
    NSError *error = nil;
    BOOL ok = [self.validator validateRecord:[self validVideoRecord]
                                 collection:@"tools.garazyk.video"
                                       mode:ATProtoValidationModeRequired
                                      error:&error];
    XCTAssertTrue(ok);
    XCTAssertNil(error);
}

- (void)testVideoRecordMissingManifestFails {
    [self requireLexiconsOrSkip];
    NSMutableDictionary *record = [[self validVideoRecord] mutableCopy];
    [record removeObjectForKey:@"manifest"];
    NSError *error = nil;
    BOOL ok = [self.validator validateRecord:record
                                 collection:@"tools.garazyk.video"
                                       mode:ATProtoValidationModeRequired
                                      error:&error];
    XCTAssertFalse(ok);
    XCTAssertNotNil(error);
}

- (void)testValidDistributionPolicyPasses {
    [self requireLexiconsOrSkip];
    NSError *error = nil;
    BOOL ok = [self.validator validateRecord:[self validPolicyRecord]
                                 collection:@"tools.garazyk.video.distributionPolicy"
                                       mode:ATProtoValidationModeRequired
                                      error:&error];
    XCTAssertTrue(ok);
    XCTAssertNil(error);
}

- (void)testDistributionPolicyMissingSubjectFails {
    [self requireLexiconsOrSkip];
    NSMutableDictionary *record = [[self validPolicyRecord] mutableCopy];
    [record removeObjectForKey:@"subject"];
    NSError *error = nil;
    BOOL ok = [self.validator validateRecord:record
                                 collection:@"tools.garazyk.video.distributionPolicy"
                                       mode:ATProtoValidationModeRequired
                                      error:&error];
    XCTAssertFalse(ok);
    XCTAssertNotNil(error);
}

- (void)testValidOriginRecordPasses {
    [self requireLexiconsOrSkip];
    NSError *error = nil;
    BOOL ok = [self.validator validateRecord:[self validOriginRecord]
                                 collection:@"tools.garazyk.video.origin"
                                       mode:ATProtoValidationModeRequired
                                      error:&error];
    XCTAssertTrue(ok);
    XCTAssertNil(error);
}

- (void)testOriginRecordInvalidWatchUrlFails {
    [self requireLexiconsOrSkip];
    NSMutableDictionary *record = [[self validOriginRecord] mutableCopy];
    record[@"watchBaseUrl"] = @"ftp://mirror.example.com";
    NSError *error = nil;
    BOOL ok = [self.validator validateRecord:record
                                 collection:@"tools.garazyk.video.origin"
                                       mode:ATProtoValidationModeRequired
                                      error:&error];
    XCTAssertFalse(ok);
    XCTAssertNotNil(error);
}

@end
