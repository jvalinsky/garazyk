// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "AppView/Server/Backfill/AppViewBackfillWorker.h"
#import "AppView/Server/AppViewDatabase.h"
#import "AppView/Server/Indexers/AppViewIndexer.h"
#import "Repository/CAR.h"
#import "Repository/STAR.h"
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
- (nullable NSString *)_parseRepoArchiveAndIndex:(NSData *)archiveData
                                          forDID:(NSString *)did
                                           error:(NSError **)error;
- (nullable NSString *)_resolvePDSEndpointForDID:(NSString *)did;
- (NSMutableURLRequest *)_repoRequestForPDSEndpoint:(NSString *)pdsEndpoint
                                                did:(NSString *)did
                                           sinceRev:(nullable NSString *)sinceRev;
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
    NSData *recordDigest = [ATProtoCID sha256Digest:recordData];
    ATProtoCID *recordCID = [ATProtoCID cidWithDigest:recordDigest codec:0x71];

    // 2. Create an MST with one entry pointing to the record
    MST *mst = [[MST alloc] init];
    [mst put:@"app.bsky.feed.post/3jzf7test" valueCID:recordCID];
    NSData *mstData = [mst serializeToCBOR];
    NSData *mstDigest = [ATProtoCID sha256Digest:mstData];
    ATProtoCID *mstCID = [ATProtoCID cidWithDigest:mstDigest codec:0x71];

    // 3. Create the commit block pointing to the MST
    NSDictionary *commit = @{
        @"version": @3,
        @"did": @"did:plc:test",
        @"rev": @"3jzf7asdf",
        @"data": mstCID,
        @"sig": [NSData dataWithBytes:"sig" length:3]
    };
    NSData *commitData = [ATProtoDagCBOR encodeObject:commit error:nil];
    NSData *commitDigest = [ATProtoCID sha256Digest:commitData];
    ATProtoCID *commitCID = [ATProtoCID cidWithDigest:commitDigest codec:0x71];

    // 4. Build the CAR with all three blocks
    CARWriter *writer = [CARWriter writerWithRootCID:commitCID];
    [writer addBlock:[CARBlock blockWithCID:commitCID data:commitData]];
    [writer addBlock:[CARBlock blockWithCID:mstCID data:mstData]];
    [writer addBlock:[CARBlock blockWithCID:recordCID data:recordData]];
    NSData *carData = [writer serialize];

    NSError *error = nil;
    NSString *rev = [self.worker _parseRepoArchiveAndIndex:carData
                                                    forDID:@"did:plc:test"
                                                     error:&error];

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

- (void)testRepoRequestPrefersSTARL0WithCARFallback {
    NSMutableURLRequest *request =
        [self.worker _repoRequestForPDSEndpoint:@"https://pds.example"
                                           did:@"did:plc:test"
                                      sinceRev:@"3jzf7asdf"];

    XCTAssertEqualObjects(
        [request valueForHTTPHeaderField:@"Accept"],
        @"application/vnd.atproto.star, application/vnd.ipld.car;q=0.9");
    XCTAssertTrue([request.URL.query containsString:@"since=3jzf7asdf"]);
}

- (void)testParseSTARL0AndIndex {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Hello STAR"
    };
    NSData *recordData = [ATProtoDagCBOR encodeObject:record error:nil];
    ATProtoCID *recordCID =
        [ATProtoCID cidWithDigest:[ATProtoCID sha256Digest:recordData] codec:0x71];

    MST *mst = [[MST alloc] init];
    [mst put:@"app.bsky.feed.post/3jzf7star" valueCID:recordCID];

    STARCommit *commit =
        [STARCommit commitWithDid:@"did:plc:test"
                          version:3
                             data:mst.rootCID
                              rev:@"3jzf7starrev"
                             prev:nil
                              sig:[@"test-signature"
                                  dataUsingEncoding:NSUTF8StringEncoding]];
    STARL0Writer *writer = [[STARL0Writer alloc] initWithCommit:commit];
    NSError *writeError = nil;
    BOOL wrote = [writer writeFromMST:mst
                        blockProvider:^NSData * _Nullable(ATProtoCID *cid) {
        return [cid.stringValue isEqualToString:recordCID.stringValue]
            ? recordData
            : nil;
    }
                                 error:&writeError];
    XCTAssertTrue(wrote, @"STAR write failed: %@", writeError);

    NSData *starData = [writer serialize];
    NSError *parseError = nil;
    NSString *rev = [self.worker _parseRepoArchiveAndIndex:starData
                                                    forDID:@"did:plc:test"
                                                     error:&parseError];

    XCTAssertNil(parseError, @"STAR parsing should not fail: %@", parseError);
    XCTAssertEqualObjects(rev, @"3jzf7starrev");
    XCTAssertEqual(self.indexer.indexedRecords.count, 1U);
    XCTAssertEqualObjects(self.indexer.indexedRecords[0][@"record"][@"text"],
                          @"Hello STAR");
}

@end
