#import <XCTest/XCTest.h>
#import "Repository/MSTPersistence.h"
#import "Repository/MST.h"
#import "Repository/CAR.h"
#import "Core/CID.h"
#import "Database/PDSDatabase.h"
#import "Database/Integration/PDSDatabaseIntegrationTestUtilities.h"

@interface MSTPersistenceTests : XCTestCase

@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) MSTPersistence *persistence;

@end

@implementation MSTPersistenceTests

- (void)setUp {
    [super setUp];

    NSError *error = nil;
    self.database = [PDSDatabaseIntegrationTestUtilities createInMemoryDatabaseWithError:&error];
    XCTAssertNotNil(self.database, "Failed to create in-memory database: %@", error);
    XCTAssertTrue(self.database.isOpen, "Database should be open");

    self.persistence = [MSTPersistence shared];
    self.persistence.database = self.database;
}

- (void)tearDown {
    self.persistence.database = nil;
    [self.database close];
    self.database = nil;
    [super tearDown];
}

- (void)testLoadMSTForDidReconstructsFromCAR {
    MST *seedTree = [[MST alloc] init];
    for (NSUInteger i = 0; i < 32; i++) {
        NSString *key = [NSString stringWithFormat:@"app.bsky.feed.post/%@", [[NSUUID UUID].UUIDString substringToIndex:8]];
        CID *cid = [CID sha256:[key dataUsingEncoding:NSUTF8StringEncoding]];
        [seedTree put:key valueCID:cid];
    }

    NSData *carData = [seedTree exportCAR];
    XCTAssertNotNil(carData, "CAR export must succeed");
    CID *rootCID = seedTree.rootCID;
    XCTAssertNotNil(rootCID, "Root CID must be available");

    NSError *carError = nil;
    CARReader *reader = [CARReader readFromData:carData error:&carError];
    XCTAssertNotNil(reader, "CAR reader should parse data: %@", carError);
    XCTAssertGreaterThan(reader.blocks.count, 0, "CAR should contain blocks");

    PDSDatabaseRepo *repo = [[PDSDatabaseRepo alloc] init];
    repo.ownerDid = @"did:plc:test-mst";
    repo.rootCid = [rootCID bytes];
    repo.createdAt = [NSDate date];
    repo.updatedAt = repo.createdAt;

    NSError *dbError = nil;
    XCTAssertTrue([self.database createRepo:repo error:&dbError], "Failed to seed repo: %@", dbError);

    for (CARBlock *block in reader.blocks) {
        PDSDatabaseBlock *dbBlock = [[PDSDatabaseBlock alloc] init];
        dbBlock.cid = [block.cid bytes];
        dbBlock.repoDid = repo.ownerDid;
        dbBlock.blockData = block.data;
        dbBlock.size = block.data.length;
        dbBlock.createdAt = [NSDate date];
        XCTAssertTrue([self.database saveBlock:dbBlock error:&dbError], "Failed to save block: %@", dbError);
    }

    NSError *loadError = nil;
    MST *loaded = [self.persistence loadMSTForDid:repo.ownerDid error:&loadError];
    XCTAssertNotNil(loaded, "Loader should return MST: %@", loadError);
    XCTAssertEqualObjects(loaded.rootCID.stringValue, rootCID.stringValue);

    NSArray<MSTEntry *> *seedEntries = [seedTree allEntries];
    NSArray<MSTEntry *> *loadedEntries = [loaded allEntries];
    XCTAssertEqual(seedEntries.count, loadedEntries.count);

    for (NSUInteger idx = 0; idx < seedEntries.count; idx++) {
        MSTEntry *seedEntry = seedEntries[idx];
        MSTEntry *persistedEntry = loadedEntries[idx];
        XCTAssertEqualObjects(seedEntry.key, persistedEntry.key);
        XCTAssertEqualObjects(seedEntry.valueCID.stringValue, persistedEntry.valueCID.stringValue);
    }
}

@end
