#import <XCTest/XCTest.h>
#import "AppView/Server/Backfill/AppViewBackfillWorker.h"
#import "AppView/Server/AppViewDatabase.h"
#import "AppView/Server/Indexers/AppViewIndexer.h"
#import "Repository/CAR.h"
#import "Repository/MST.h"
#import "Core/CID.h"
#import "Core/ATProtoDagCBOR.h"

@interface BackfillWorkerMockIndexer : NSObject <AppViewIndexer>
@property (nonatomic, strong) NSMutableArray *indexedRecords;
@end

@implementation BackfillWorkerMockIndexer
- (instancetype)init {
    self = [super init];
    if (self) {
        _indexedRecords = [NSMutableArray array];
    }
    return self;
}
- (BOOL)canIndexCollection:(NSString *)collection {
    return [collection hasPrefix:@"app.bsky."];
}
- (BOOL)indexRecord:(NSDictionary *)record did:(NSString *)did collection:(NSString *)collection rkey:(NSString *)rkey cid:(NSString *)cid error:(NSError **)error {
    [self.indexedRecords addObject:@{@"record": record, @"did": did, @"collection": collection, @"rkey": rkey, @"cid": cid ?: @""}];
    return YES;
}
@end

@interface AppViewBackfillWorker (Test)
- (nullable NSString *)_parseCARAndIndex:(NSData *)carData forDID:(NSString *)did error:(NSError **)error;
- (nullable NSString *)_resolvePDSEndpointForDID:(NSString *)did;
@end

@interface AppViewBackfillWorkerTests : XCTestCase
@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) AppViewDatabase *database;
@property (nonatomic, strong) BackfillWorkerMockIndexer *indexer;
@property (nonatomic, strong) AppViewBackfillWorker *worker;
@end

@implementation AppViewBackfillWorkerTests

- (void)setUp {
    [super setUp];
    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    
    NSString *dbPath = [self.testDirectory stringByAppendingPathComponent:@"appview_test.db"];
    NSError *error = nil;
    self.database = [[AppViewDatabase alloc] initWithPath:dbPath error:&error];
    XCTAssertNotNil(self.database, @"Failed to init database: %@", error);
    [self.database runMigrations:&error];
    
    self.indexer = [[BackfillWorkerMockIndexer alloc] init];
    self.worker = [[AppViewBackfillWorker alloc] initWithDID:@"did:plc:test"
                                                     database:self.database
                                                     indexers:@[self.indexer]
                                                     plcURL:@"http://localhost:2582"];
}

- (void)tearDown {
    [self.database close];
    [[NSFileManager defaultManager] removeItemAtPath:self.testDirectory error:nil];
    [super tearDown];
}

- (void)testParseCARAndIndex {
    // Create a proper CAR with commit → MST → record structure
    // This matches the real AT Protocol repo CAR format

    // 1. Create the record block
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Hello tests"
    };
    NSData *recordData = [ATProtoDagCBOR encodeObject:record error:nil];
    NSData *recordDigest = [CID sha256Digest:recordData];
    CID *recordCID = [CID cidWithDigest:recordDigest codec:0x71];

    // 2. Create an MST with one entry pointing to the record
    MST *mst = [[MST alloc] init];
    [mst put:@"app.bsky.feed.post/3jzf7test" valueCID:recordCID];
    NSData *mstData = [mst serializeToCBOR];
    NSData *mstDigest = [CID sha256Digest:mstData];
    CID *mstCID = [CID cidWithDigest:mstDigest codec:0x71];

    // 3. Create the commit block pointing to the MST
    NSDictionary *commit = @{
        @"version": @3,
        @"did": @"did:plc:test",
        @"rev": @"3jzf7asdf",
        @"data": mstCID,
        @"sig": [NSData dataWithBytes:"sig" length:3]
    };
    NSData *commitData = [ATProtoDagCBOR encodeObject:commit error:nil];
    NSData *commitDigest = [CID sha256Digest:commitData];
    CID *commitCID = [CID cidWithDigest:commitDigest codec:0x71];

    // 4. Build the CAR with all three blocks
    CARWriter *writer = [CARWriter writerWithRootCID:commitCID];
    [writer addBlock:[CARBlock blockWithCID:commitCID data:commitData]];
    [writer addBlock:[CARBlock blockWithCID:mstCID data:mstData]];
    [writer addBlock:[CARBlock blockWithCID:recordCID data:recordData]];
    NSData *carData = [writer serialize];

    NSError *error = nil;
    NSString *rev = [self.worker _parseCARAndIndex:carData forDID:@"did:plc:test" error:&error];

    XCTAssertNil(error, @"CAR parsing should not fail: %@", error);
    XCTAssertEqualObjects(rev, @"3jzf7asdf", @"Revision should match commit rev");
    XCTAssertEqual(self.indexer.indexedRecords.count, 1, @"Should index exactly one record");
    XCTAssertEqualObjects(self.indexer.indexedRecords[0][@"collection"], @"app.bsky.feed.post");
    XCTAssertEqualObjects(self.indexer.indexedRecords[0][@"record"][@"text"], @"Hello tests");
}

- (void)testResolvePDSEndpointForLocalhost {
    NSString *endpoint = [self.worker _resolvePDSEndpointForDID:@"did:web:localhost%3A2583"];
    XCTAssertEqualObjects(endpoint, @"http://localhost:2583");
    
    endpoint = [self.worker _resolvePDSEndpointForDID:@"did:web:127.0.0.1%3A2583"];
    XCTAssertEqualObjects(endpoint, @"http://127.0.0.1:2583");
}

@end
