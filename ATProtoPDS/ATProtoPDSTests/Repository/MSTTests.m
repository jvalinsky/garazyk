#import "MSTTests.h"
#import "TestUtilities.h"

@implementation MSTTests

- (void)setUp {
    [super setUp];
    self.emptyMST = [[MST alloc] initWithRootCID:nil];
    self.testData = [NSMutableDictionary dictionary];
    self.testKeys = [NSMutableArray array];
    
    for (NSInteger i = 0; i < 100; i++) {
        NSString *key = [NSString stringWithFormat:@"app.bsky.actor.profile/%@",
                        [[NSUUID UUID] UUIDString]];
        CID *cid = [[TestFixture sharedFixture] generateRandomCID];
        self.testData[key] = cid;
        [self.testKeys addObject:key];
    }
}

#pragma mark - Basic Operations

- (void)testEmptyMSTHasNilRoot {
    XCTAssertNil(self.emptyMST.rootCID);
}

- (void)testEmptyMSTHasZeroEntries {
    XCTAssertEqual([self.emptyMST allEntries].count, 0);
}

- (void)testEmptyMSTHasCorrectEmptyTreeHash {
    NSData *expectedHash = [self.emptyMST emptyTreeHash];
    XCTAssertNotNil(expectedHash);
    XCTAssertEqual(expectedHash.length, 32);
}

- (void)testAddIncreasesEntryCount {
    MST *mst = self.emptyMST;
    NSArray *keys = [self.testData allKeys];
    
    for (NSInteger i = 0; i < keys.count; i++) {
        NSString *key = keys[i];
        CID *cid = self.testData[key];
        mst = [mst put:key valueCID:cid];
    }
    
    XCTAssertEqual([mst allEntries].count, self.testData.count);
}

- (void)testGetReturnsCorrectCID {
    MST *mst = self.emptyMST;
    
    for (NSString *key in self.testData) {
        CID *expectedCID = self.testData[key];
        CID *retrievedCID = [mst get:key];
        XCTAssertNil(retrievedCID);
        
        mst = [mst put:key valueCID:expectedCID];
    }
    
    for (NSString *key in self.testData) {
        CID *expectedCID = self.testData[key];
        CID *retrievedCID = [mst get:key];
        XCTAssertNotNil(retrievedCID);
        XCTAssertTrue([expectedCID isEqualToCID:retrievedCID]);
    }
}

- (void)testDeleteRemovesEntry {
    NSArray *keys = [self.testData allKeys];
    MST *mst = self.emptyMST;
    
    for (NSString *key in keys) {
        mst = [mst put:key valueCID:self.testData[key]];
    }
    
    for (NSInteger i = 0; i < keys.count / 2; i++) {
        NSString *keyToDelete = keys[i];
        mst = [mst delete:keyToDelete];
    }
    
    for (NSInteger i = 0; i < keys.count / 2; i++) {
        XCTAssertNil([mst get:keys[i]]);
    }
    
    for (NSInteger i = keys.count / 2; i < keys.count; i++) {
        CID *expectedCID = self.testData[keys[i]];
        CID *retrievedCID = [mst get:keys[i]];
        XCTAssertNotNil(retrievedCID);
        XCTAssertTrue([expectedCID isEqualToCID:retrievedCID]);
    }
}

#pragma mark - Update Operations

- (void)testUpdateReplacesExistingValue {
    NSString *key = @"app.bsky.actor.profile/self";
    CID *originalCID = [[TestFixture sharedFixture] generateRandomCID];
    CID *updatedCID = [[TestFixture sharedFixture] generateRandomCID];
    
    MST *mst = [self.emptyMST put:key valueCID:originalCID];
    XCTAssertTrue([[mst get:key] isEqualToCID:originalCID]);
    
    mst = [mst put:key valueCID:updatedCID];
    XCTAssertTrue([[mst get:key] isEqualToCID:updatedCID]);
    XCTAssertFalse([[mst get:key] isEqualToCID:originalCID]);
}

#pragma mark - Order Independence

- (void)testOrderIndependentAdd {
    NSArray *keys = [self.testData allKeys];
    NSMutableArray *shuffled = [keys mutableCopy];
    
    for (NSInteger i = shuffled.count - 1; i > 0; i--) {
        NSInteger j = arc4random_uniform((uint32_t)(i + 1));
        [shuffled exchangeObjectAtIndex:i withObjectAtIndex:j];
    }
    
    MST *mst1 = self.emptyMST;
    for (NSString *key in shuffled) {
        mst1 = [mst1 put:key valueCID:self.testData[key]];
    }
    
    NSArray *reverse = [[keys reverseObjectEnumerator] allObjects];
    MST *mst2 = self.emptyMST;
    for (NSString *key in reverse) {
        mst2 = [mst2 put:key valueCID:self.testData[key]];
    }
    
    XCTAssertEqualObjects(mst1.rootCID, mst2.rootCID);
    
    NSArray *entries1 = [mst1 allEntries];
    NSArray *entries2 = [mst2 allEntries];
    XCTAssertEqual(entries1.count, entries2.count);
}

#pragma mark - Serialization

- (void)testCARExportImport {
    MST *original = self.emptyMST;
    for (NSString *key in self.testData) {
        original = [original put:key valueCID:self.testData[key]];
    }
    
    NSData *carData = [original exportCAR];
    XCTAssertNotNil(carData);
    XCTAssertGreaterThan(carData.length, 0);
    
    MST *recovered = [MST deserializeFromCBOR:carData];
    XCTAssertNotNil(recovered);
    
    for (NSString *key in self.testData) {
        CID *originalCID = [original get:key];
        CID *recoveredCID = [recovered get:key];
        XCTAssertTrue([originalCID isEqualToCID:recoveredCID]);
    }
}

#pragma mark - Prefix Queries

- (void)testEntriesWithPrefix {
    NSString *prefix = @"app.bsky.feed.";
    NSMutableDictionary *feedEntries = [NSMutableDictionary dictionary];
    
    for (NSString *key in self.testData) {
        MST *mst = [self.emptyMST put:key valueCID:self.testData[key]];
        if ([key hasPrefix:prefix]) {
            feedEntries[key] = self.testData[key];
        }
    }
    
    NSArray *prefixEntries = [self.emptyMST entriesWithPrefix:prefix];
    
    for (MSTEntry *entry in prefixEntries) {
        XCTAssertTrue([entry.key hasPrefix:prefix]);
    }
    XCTAssertEqual(prefixEntries.count, feedEntries.count);
}

#pragma mark - Performance Tests

- (void)testBulkOperationsPerformance {
    NSUInteger count = 1000;
    NSMutableArray *keys = [NSMutableArray arrayWithCapacity:count];
    NSMutableArray *cids = [NSMutableArray arrayWithCapacity:count];
    
    for (NSUInteger i = 0; i < count; i++) {
        NSString *key = [NSString stringWithFormat:@"app.bsky.actor.profile/%08lu", (unsigned long)i];
        CID *cid = [[TestFixture sharedFixture] generateRandomCID];
        [keys addObject:key];
        [cids addObject:cid];
    }
    
    [self measureBlock:^{
        MST *mst = self.emptyMST;
        for (NSUInteger i = 0; i < count; i++) {
            mst = [mst put:keys[i] valueCID:cids[i]];
        }
        
        for (NSUInteger i = 0; i < count; i++) {
            XCTAssertNotNil([mst get:keys[i]]);
        }
    }];
}

@end
