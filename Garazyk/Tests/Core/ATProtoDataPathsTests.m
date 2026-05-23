// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Core/ATProtoDataPaths.h"

@interface ATProtoDataPathsTests : XCTestCase
@property (nonatomic, strong) NSString *tempBaseDir;
@end

@implementation ATProtoDataPathsTests

- (void)setUp {
    [super setUp];
    NSString *uuid = [[NSUUID UUID] UUIDString];
    self.tempBaseDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                        [NSString stringWithFormat:@"pds-data-paths-tests-%@", uuid]];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.tempBaseDir error:nil];
    [super tearDown];
}

- (void)testInitDerivesExpectedDirectories {
    ATProtoDataPaths *paths = [[ATProtoDataPaths alloc] initWithBaseDirectory:@"/tmp/pds"];
    XCTAssertEqualObjects(paths.baseDirectory, @"/tmp/pds");
    XCTAssertEqualObjects(paths.serviceDirectory, @"/tmp/pds/service");
    XCTAssertEqualObjects(paths.didCacheDirectory, @"/tmp/pds/did_cache");
    XCTAssertEqualObjects(paths.sequencerDirectory, @"/tmp/pds/sequencer");
    XCTAssertEqualObjects(paths.blobsDirectory, @"/tmp/pds/blobs");
    XCTAssertEqualObjects(paths.lexiconsDirectory, @"/tmp/pds/lexicons");
    XCTAssertEqualObjects(paths.keysDirectory, @"/tmp/pds/keys");
    XCTAssertEqualObjects(paths.exploreCacheDirectory, @"/tmp/pds/cache/explore");
}

- (void)testFactoryMatchesInitializer {
    ATProtoDataPaths *paths = [ATProtoDataPaths pathsForBaseDirectory:@"/tmp/factory"];
    XCTAssertEqualObjects(paths.baseDirectory, @"/tmp/factory");
    XCTAssertEqualObjects(paths.keysDirectory, @"/tmp/factory/keys");
}

- (void)testCreateDirectoriesCreatesAllExpectedPaths {
    ATProtoDataPaths *paths = [[ATProtoDataPaths alloc] initWithBaseDirectory:self.tempBaseDir];
    NSError *error = nil;
    XCTAssertTrue([paths createDirectoriesWithError:&error]);
    XCTAssertNil(error);

    NSArray<NSString *> *expected = @[
        paths.baseDirectory,
        paths.serviceDirectory,
        paths.didCacheDirectory,
        paths.sequencerDirectory,
        paths.blobsDirectory,
        paths.lexiconsDirectory,
        paths.keysDirectory,
        paths.exploreCacheDirectory
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *dir in expected) {
        BOOL isDir = NO;
        XCTAssertTrue([fm fileExistsAtPath:dir isDirectory:&isDir]);
        XCTAssertTrue(isDir);
    }
}

- (void)testCreateDirectoriesIsIdempotent {
    ATProtoDataPaths *paths = [[ATProtoDataPaths alloc] initWithBaseDirectory:self.tempBaseDir];
    NSError *error = nil;
    XCTAssertTrue([paths createDirectoriesWithError:&error]);
    XCTAssertNil(error);
    XCTAssertTrue([paths createDirectoriesWithError:&error]);
    XCTAssertNil(error);
}

- (void)testActorStorePathForStandardDidShardsByMethodAndPrefix {
    ATProtoDataPaths *paths = [[ATProtoDataPaths alloc] initWithBaseDirectory:@"/var/pds"];
    NSString *result = [paths actorStorePathForDid:@"did:plc:abcdefghijklmnopqrstuvwx"];
    XCTAssertEqualObjects(result, @"/var/pds/plc/ab/did:plc:abcdefghijklmnopqrstuvwx");
}

- (void)testActorStorePathRejectsNonDidInput {
    ATProtoDataPaths *paths = [[ATProtoDataPaths alloc] initWithBaseDirectory:@"/var/pds"];
    NSString *result = [paths actorStorePathForDid:@"abc"];
    XCTAssertNil(result);
}

- (void)testActorStorePathRejectsEmptyDid {
    ATProtoDataPaths *paths = [[ATProtoDataPaths alloc] initWithBaseDirectory:@"/var/pds"];
    NSString *result = [paths actorStorePathForDid:@""];
    XCTAssertNil(result);
}

- (void)testActorStorePathRejectsTraversalDid {
    ATProtoDataPaths *paths = [[ATProtoDataPaths alloc] initWithBaseDirectory:@"/var/pds"];
    NSString *result = [paths actorStorePathForDid:@"did:plc:../../service"];
    XCTAssertNil(result);
}

- (void)testKeyPathForDid {
    ATProtoDataPaths *paths = [[ATProtoDataPaths alloc] initWithBaseDirectory:@"/tmp/pds"];
    NSString *result = [paths keyPathForDid:@"did:plc:abcdefghijklmnopqrstuvwx"];
    XCTAssertEqualObjects(result, @"/tmp/pds/keys/did:plc:abcdefghijklmnopqrstuvwx");
}

@end
