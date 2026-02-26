#import <XCTest/XCTest.h>
#import "Core/PDSDataPaths.h"

@interface PDSDataPathsTests : XCTestCase
@property (nonatomic, strong) NSString *tempBaseDir;
@end

@implementation PDSDataPathsTests

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
    PDSDataPaths *paths = [[PDSDataPaths alloc] initWithBaseDirectory:@"/tmp/pds"];
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
    PDSDataPaths *paths = [PDSDataPaths pathsForBaseDirectory:@"/tmp/factory"];
    XCTAssertEqualObjects(paths.baseDirectory, @"/tmp/factory");
    XCTAssertEqualObjects(paths.keysDirectory, @"/tmp/factory/keys");
}

- (void)testCreateDirectoriesCreatesAllExpectedPaths {
    PDSDataPaths *paths = [[PDSDataPaths alloc] initWithBaseDirectory:self.tempBaseDir];
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
    PDSDataPaths *paths = [[PDSDataPaths alloc] initWithBaseDirectory:self.tempBaseDir];
    NSError *error = nil;
    XCTAssertTrue([paths createDirectoriesWithError:&error]);
    XCTAssertNil(error);
    XCTAssertTrue([paths createDirectoriesWithError:&error]);
    XCTAssertNil(error);
}

- (void)testActorStorePathForStandardDidShardsByMethodAndPrefix {
    PDSDataPaths *paths = [[PDSDataPaths alloc] initWithBaseDirectory:@"/var/pds"];
    NSString *result = [paths actorStorePathForDid:@"did:plc:abcdef1234"];
    XCTAssertEqualObjects(result, @"/var/pds/plc/ab/did:plc:abcdef1234");
}

- (void)testActorStorePathForNonStandardDidFallsBackToPrefixOnly {
    PDSDataPaths *paths = [[PDSDataPaths alloc] initWithBaseDirectory:@"/var/pds"];
    NSString *result = [paths actorStorePathForDid:@"abc"];
    XCTAssertEqualObjects(result, @"/var/pds/ab/abc");
}

- (void)testActorStorePathForEmptyDidUsesFallbackSafely {
    PDSDataPaths *paths = [[PDSDataPaths alloc] initWithBaseDirectory:@"/var/pds"];
    NSString *result = [paths actorStorePathForDid:@""];
    XCTAssertEqualObjects(result, @"/var/pds");
}

- (void)testKeyPathForDid {
    PDSDataPaths *paths = [[PDSDataPaths alloc] initWithBaseDirectory:@"/tmp/pds"];
    NSString *result = [paths keyPathForDid:@"did:plc:abc"];
    XCTAssertEqualObjects(result, @"/tmp/pds/keys/did:plc:abc");
}

@end
