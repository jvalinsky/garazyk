#import <XCTest/XCTest.h>
#import <stdlib.h>
#import "App/Explore/ExploreCache.h"

@interface ExploreCache (Testing)
@property (nonatomic, copy) NSString *cacheDirectory;
@property (nonatomic, copy) NSString *didCacheDir;
@property (nonatomic, copy) NSString *plcCacheDir;
@property (nonatomic, copy) NSString *accountCachePath;
- (NSString *)pathForDidDocument:(NSString *)did;
@end

@interface ExploreCacheTests : XCTestCase
@property (nonatomic, strong) ExploreCache *cache;
@property (nonatomic, copy) NSString *tempDir;
@property (nonatomic, copy) NSString *previousEnv;
@end

@implementation ExploreCacheTests

- (void)setUp {
    [super setUp];

    const char *existing = getenv("PDS_EXPLORE_CACHE_DIR");
    if (existing) {
        self.previousEnv = [NSString stringWithUTF8String:existing];
    }

    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    setenv("PDS_EXPLORE_CACHE_DIR", self.tempDir.UTF8String, 1);
    self.cache = [[ExploreCache alloc] init];
}

- (void)tearDown {
    if (self.previousEnv.length > 0) {
        setenv("PDS_EXPLORE_CACHE_DIR", self.previousEnv.UTF8String, 1);
    } else {
        unsetenv("PDS_EXPLORE_CACHE_DIR");
    }

    if (self.tempDir.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    }

    self.cache = nil;
    self.tempDir = nil;
    self.previousEnv = nil;
    [super tearDown];
}

- (void)testUsesEnvironmentOverrideForCacheDirectory {
    XCTAssertEqualObjects(self.cache.cacheDirectory, self.tempDir);
}

- (void)testDidDocumentRoundTrip {
    NSString *did = @"did:plc:test123";
    NSString *document = @"{\"id\":\"did:plc:test123\"}";

    [self.cache setDidDocument:did value:document];
    NSString *cached = [self.cache getDidDocument:did];

    XCTAssertEqualObjects(cached, document);
}

- (void)testAccountListRoundTrip {
    NSString *accountList = @"[{\"did\":\"did:plc:test\",\"handle\":\"test.example.com\"}]";

    [self.cache setAccountList:accountList];
    NSString *cached = [self.cache getAccountList];

    XCTAssertEqualObjects(cached, accountList);
}

- (void)testAccountListFallsBackToDiskWhenMemoryEntryExpired {
    NSString *freshDiskValue = @"[{\"did\":\"did:plc:fresh\",\"handle\":\"fresh.example.com\"}]";
    [self.cache setAccountList:freshDiskValue];

    NSCache *memoryCache = [self.cache valueForKey:@"memoryCache"];
    [memoryCache setObject:@{
        @"value": @"[{\"did\":\"did:plc:stale\",\"handle\":\"stale.example.com\"}]",
        @"timestamp": [NSDate dateWithTimeIntervalSinceNow:-3600.0]
    } forKey:@"accounts:list"];

    NSString *cached = [self.cache getAccountList];
    XCTAssertEqualObjects(cached, freshDiskValue);
}

- (void)testClearExpiredEntriesRemovesOldDidCache {
    NSString *did = @"did:plc:expired";
    NSString *document = @"{\"id\":\"did:plc:expired\"}";

    [self.cache setDidDocument:did value:document];
    NSString *path = [self.cache pathForDidDocument:did];

    NSDate *expired = [NSDate dateWithTimeIntervalSinceNow:-(7200.0)];
    [[NSFileManager defaultManager] setAttributes:@{NSFileModificationDate: expired}
                                     ofItemAtPath:path
                                            error:nil];

    [self.cache clearExpiredEntries];

    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path];
    XCTAssertFalse(exists, @"Expired DID cache should be removed");
}

@end
