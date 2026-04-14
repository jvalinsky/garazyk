#import <XCTest/XCTest.h>
#import "Repository/MSTPersistence.h"
#import "Repository/MST.h"
#import "Repository/CAR.h"
#import "Repository/CBOR.h"
#import "Core/CID.h"
#import "Database/PDSDatabase.h"
#import "Database/Integration/PDSDatabaseIntegrationTestUtilities.h"

@interface MSTPersistenceTests : XCTestCase

@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) MSTPersistence *persistence;

@end

@implementation MSTPersistenceTests

- (nullable NSString *)carFixturePathNamed:(NSString *)filename {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *cwd = fm.currentDirectoryPath;
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *bundlePath = [bundle resourcePath];

    NSArray<NSString *> *candidates = @[
        [@"Garazyk/Tests/fixtures/mst" stringByAppendingPathComponent:filename],
        [@"Tests/fixtures/mst" stringByAppendingPathComponent:filename],
        [@"fixtures/mst" stringByAppendingPathComponent:filename],
        [bundlePath stringByAppendingPathComponent:filename],
        [@"../Garazyk/Tests/fixtures/mst" stringByAppendingPathComponent:filename],
        [@"../../Garazyk/Tests/fixtures/mst" stringByAppendingPathComponent:filename],
        [@"../../../Garazyk/Tests/fixtures/mst" stringByAppendingPathComponent:filename],
        [@"reference/indigo/testing/testdata" stringByAppendingPathComponent:filename],
        [@"../reference/indigo/testing/testdata" stringByAppendingPathComponent:filename],
        [@"../../reference/indigo/testing/testdata" stringByAppendingPathComponent:filename],
        [@"../../../reference/indigo/testing/testdata" stringByAppendingPathComponent:filename]
    ];

    for (NSString *candidate in candidates) {
        NSString *path = [cwd stringByAppendingPathComponent:candidate];
        if ([fm fileExistsAtPath:path]) {
            return path;
        }
        NSString *absolutePath = candidate;
        if (![candidate hasPrefix:@"/"]) {
            absolutePath = [cwd stringByAppendingPathComponent:candidate];
        }
        if ([fm fileExistsAtPath:absolutePath]) {
            return absolutePath;
        }
    }
    return nil;
}

- (nullable CID *)cidFromTaggedValue:(CBORValue *)value {
    if (!value || value.type != CBORTypeTag || !value.tagValue || value.tagValue.type != CBORTypeByteString) {
        return nil;
    }

    NSData *bytes = value.tagValue.byteString;
    if (!bytes || bytes.length <= 1) {
        return nil;
    }

    NSData *cidBytes = [bytes subdataWithRange:NSMakeRange(1, bytes.length - 1)];
    return [CID cidFromBytes:cidBytes];
}

- (CID *)mstRootCIDForReader:(CARReader *)reader {
    CARBlock *rootBlock = [reader blockWithCID:reader.rootCID];
    if (!rootBlock) {
        return reader.rootCID;
    }

    CBORValue *decoded = [CBORValue decode:rootBlock.data];
    if (!decoded || decoded.type != CBORTypeMap) {
        return reader.rootCID;
    }

    CBORValue *entries = decoded.map[[CBORValue textString:@"e"]];
    CBORValue *left = decoded.map[[CBORValue textString:@"l"]];
    if ((entries && entries.type == CBORTypeArray) || left) {
        return reader.rootCID;
    }

    CBORValue *dataValue = decoded.map[[CBORValue textString:@"data"]];
    if (!dataValue) {
        return reader.rootCID;
    }

    CID *dataCID = nil;
    if (dataValue.type == CBORTypeTextString) {
        dataCID = [CID cidFromString:dataValue.textString];
    } else if (dataValue.type == CBORTypeTag) {
        dataCID = [self cidFromTaggedValue:dataValue];
    }

    return dataCID ?: reader.rootCID;
}

- (void)setUp {
    [super setUp];

    NSError *error = nil;
    self.database = [PDSDatabaseIntegrationTestUtilities createInMemoryDatabaseWithError:&error];
    XCTAssertNotNil(self.database, "Failed to create in-memory database: %@", error);
    XCTAssertTrue(self.database.isOpen, "Database should be open");

    // Use a fresh instance, NOT the singleton, to avoid state pollution between tests
    self.persistence = [[MSTPersistence alloc] init];
    self.persistence.database = self.database;
}

- (void)tearDown {
    self.persistence.database = nil;
    self.persistence = nil;
    [self.database close];
    self.database = nil;
    [super tearDown];
}

- (void)testLoadMSTForDidReconstructsFromCAR {
    // Use deterministic keys with proper TID-format rkeys
    // TIDs are base32-sortable timestamp identifiers (13 chars, lowercase alphanumeric)
    MST *seedTree = [[MST alloc] init];
    NSArray *tidRkeys = @[
        @"3jzfcijpj2z2a", @"3jzfcijpj2z2b", @"3jzfcijpj2z2c", @"3jzfcijpj2z2d",
        @"3jzfcijpj2z2e", @"3jzfcijpj2z2f", @"3jzfcijpj2z2g", @"3jzfcijpj2z2h",
        @"3jzfcijpj2z2i", @"3jzfcijpj2z2j", @"3jzfcijpj2z2k", @"3jzfcijpj2z2l",
        @"3jzfcijpj2z2m", @"3jzfcijpj2z2n", @"3jzfcijpj2z2o", @"3jzfcijpj2z2p",
        @"3jzfcijpj2z2q", @"3jzfcijpj2z2r", @"3jzfcijpj2z2s", @"3jzfcijpj2z2t",
        @"3jzfcijpj2z2u", @"3jzfcijpj2z2v", @"3jzfcijpj2z2w", @"3jzfcijpj2z2x",
        @"3jzfcijpj2z2y", @"3jzfcijpj2z2z", @"3jzfcijpj2z3a", @"3jzfcijpj2z3b",
        @"3jzfcijpj2z3c", @"3jzfcijpj2z3d", @"3jzfcijpj2z3e", @"3jzfcijpj2z3f"
    ];
    for (NSUInteger i = 0; i < tidRkeys.count; i++) {
        NSString *key = [NSString stringWithFormat:@"app.bsky.feed.post/%@", tidRkeys[i]];
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
    // Use a unique DID per test run to avoid conflicts with stale data
    repo.ownerDid = [NSString stringWithFormat:@"did:plc:msttest-%@", [[NSUUID UUID] UUIDString]];
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

- (void)testLoadMSTForDidReconstructsFromRealCARFixture {
    NSString *carPath = [self carFixturePathNamed:@"greenground.repo.car"];
    XCTAssertNotNil(carPath, @"Fixture CAR file should exist");

    NSError *carError = nil;
    CARReader *reader = [CARReader readFromPath:carPath error:&carError];
    XCTAssertNotNil(reader, @"CAR reader should parse fixture: %@", carError);
    XCTAssertNotNil(reader.rootCID, @"Fixture CAR should contain root CID");
    XCTAssertGreaterThan(reader.blocks.count, 0, @"Fixture CAR should have blocks");

    CID *mstRootCID = [self mstRootCIDForReader:reader];
    XCTAssertNotNil(mstRootCID, @"Fixture CAR should resolve MST root CID");

    PDSDatabaseRepo *repo = [[PDSDatabaseRepo alloc] init];
    repo.ownerDid = [NSString stringWithFormat:@"did:plc:mstfixture-%@", [[NSUUID UUID] UUIDString]];
    repo.rootCid = [mstRootCID bytes];
    repo.createdAt = [NSDate date];
    repo.updatedAt = repo.createdAt;

    NSError *dbError = nil;
    XCTAssertTrue([self.database createRepo:repo error:&dbError], @"Failed to seed fixture repo: %@", dbError);

    for (CARBlock *block in reader.blocks) {
        PDSDatabaseBlock *dbBlock = [[PDSDatabaseBlock alloc] init];
        dbBlock.cid = [block.cid bytes];
        dbBlock.repoDid = repo.ownerDid;
        dbBlock.blockData = block.data;
        dbBlock.size = block.data.length;
        dbBlock.createdAt = [NSDate date];
        XCTAssertTrue([self.database saveBlock:dbBlock error:&dbError], @"Failed to save fixture block: %@", dbError);
    }

    NSError *loadError = nil;
    MST *loaded = [self.persistence loadMSTForDid:repo.ownerDid error:&loadError];
    XCTAssertNotNil(loaded, @"Loader should return MST for fixture CAR: %@", loadError);
    XCTAssertEqualObjects(loaded.rootCID.stringValue, mstRootCID.stringValue);

    NSArray<MSTEntry *> *entries = [loaded allEntries];
    XCTAssertGreaterThan(entries.count, 0, @"Fixture CAR should yield MST entries");

    for (MSTEntry *entry in entries) {
        XCTAssertGreaterThan(entry.key.length, 0, @"Fixture entries must have keys");
        XCTAssertNotNil(entry.valueCID, @"Fixture entries must have value CIDs");
    }
}

@end
