#import <XCTest/XCTest.h>
#import "App/Services/PDSRecordService.h"
#import "App/Services/PDSRepositoryService.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Pool/DatabasePool.h"
#import "Repository/CAR.h"
#import "Repository/CBOR.h"

@interface PDSRepositoryServiceTests : XCTestCase
@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) PDSDatabasePool *pool;
@property (nonatomic, strong) PDSRecordService *recordService;
@property (nonatomic, strong) PDSRepositoryService *repositoryService;
@property (nonatomic, copy) NSString *testDID;
@property (nonatomic, strong) NSISO8601DateFormatter *isoFormatter;
@end

@implementation PDSRepositoryServiceTests

- (void)setUp {
    [super setUp];

    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    self.pool = [[PDSDatabasePool alloc] initWithDbDirectory:self.testDirectory maxSize:5];
    self.recordService = [[PDSRecordService alloc] initWithDatabasePool:self.pool];
    self.repositoryService = [[PDSRepositoryService alloc] initWithDatabasePool:self.pool];
    self.testDID = @"did:web:test.repositoryservice.example.com";
    self.isoFormatter = [[NSISO8601DateFormatter alloc] init];
    
    // Generate signing key for test DID
    NSError *storeError = nil;
    PDSActorStore *store = [self.pool storeForDid:self.testDID error:&storeError];
    if (store) {
        NSError *keyError = nil;
        if (![store generateSigningKeyWithError:&keyError]) {
            NSLog(@"Warning: Failed to generate signing key for test: %@", keyError);
        }
    }
}

- (void)tearDown {
    [self.pool closeAll];
    self.pool = nil;
    self.recordService = nil;
    self.repositoryService = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.testDirectory error:nil];
    [super tearDown];
}

- (nullable NSString *)commitRevFromCARData:(NSData *)carData {
    NSError *carError = nil;
    CARReader *reader = [CARReader readFromData:carData error:&carError];
    XCTAssertNil(carError);
    XCTAssertNotNil(reader);
    if (!reader) {
        return nil;
    }

    CARBlock *commitBlock = [reader blockWithCID:reader.rootCID];
    XCTAssertNotNil(commitBlock);
    if (!commitBlock) {
        return nil;
    }

    CBORValue *commitValue = [CBORValue decode:commitBlock.data];
    XCTAssertNotNil(commitValue);
    XCTAssertEqual(commitValue.type, CBORTypeMap);
    if (!commitValue || commitValue.type != CBORTypeMap) {
        return nil;
    }

    CBORValue *revValue = commitValue.map[[CBORValue textString:@"rev"]];
    XCTAssertNotNil(revValue);
    XCTAssertEqual(revValue.type, CBORTypeTextString);
    return revValue.textString;
}

- (nullable CID *)commitDataCIDFromCARData:(NSData *)carData {
    NSError *carError = nil;
    CARReader *reader = [CARReader readFromData:carData error:&carError];
    XCTAssertNil(carError);
    XCTAssertNotNil(reader);
    if (!reader) {
        return nil;
    }

    CARBlock *commitBlock = [reader blockWithCID:reader.rootCID];
    XCTAssertNotNil(commitBlock);
    if (!commitBlock) {
        return nil;
    }

    CBORValue *commitValue = [CBORValue decode:commitBlock.data];
    XCTAssertNotNil(commitValue);
    XCTAssertEqual(commitValue.type, CBORTypeMap);
    if (!commitValue || commitValue.type != CBORTypeMap) {
        return nil;
    }

    CBORValue *dataValue = commitValue.map[[CBORValue textString:@"data"]];
    XCTAssertNotNil(dataValue);
    XCTAssertEqual(dataValue.type, CBORTypeTag);
    if (!dataValue || dataValue.type != CBORTypeTag) {
        return nil;
    }

    CBORValue *tagged = dataValue.tagValue;
    XCTAssertEqual(tagged.type, CBORTypeByteString);
    NSData *tagBytes = tagged.byteString;
    XCTAssertTrue(tagBytes.length > 1);
    if (tagged.type != CBORTypeByteString || tagBytes.length <= 1) {
        return nil;
    }

    NSData *rawCID = [tagBytes subdataWithRange:NSMakeRange(1, tagBytes.length - 1)];
    return [CID cidFromBytes:rawCID];
}

- (NSDictionary *)postRecordWithText:(NSString *)text {
    return @{
        @"$type": @"app.bsky.feed.post",
        @"text": text,
        @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
    };
}

- (BOOL)carData:(NSData *)carData containsBlockWithCIDString:(NSString *)cidString {
    NSError *parseError = nil;
    CARReader *reader = [CARReader readFromData:carData error:&parseError];
    XCTAssertNil(parseError);
    XCTAssertNotNil(reader);
    if (!reader) {
        return NO;
    }

    for (CARBlock *block in reader.blocks) {
        if ([block.cid.stringValue isEqualToString:cidString]) {
            return YES;
        }
    }
    return NO;
}

- (nullable NSString *)latestMutationRevForTestDid {
    PDSActorStore *store = [self.pool storeForDid:self.testDID error:nil];
    XCTAssertNotNil(store);
    return [store latestMutationRevisionWithError:nil];
}

- (void)testGetRepoContentsReturnsCARWithCommitRoot {
    NSError *writeError = nil;
    BOOL putOK = [self.recordService putRecord:@"app.bsky.feed.post"
                                          rkey:@"repo-test-1"
                                         value:[self postRecordWithText:@"hello repo"]
                                        forDid:self.testDID
                                validationMode:PDSValidationModeOff
                                         error:&writeError];
    XCTAssertTrue(putOK);
    XCTAssertNil(writeError);

    NSError *exportError = nil;
    NSData *carData = [self.repositoryService getRepoContents:self.testDID since:nil error:&exportError];
    XCTAssertNotNil(carData);
    XCTAssertNil(exportError);
    XCTAssertTrue(carData.length > 0);

    NSError *carError = nil;
    CARReader *reader = [CARReader readFromData:carData error:&carError];
    XCTAssertNotNil(reader);
    XCTAssertNil(carError);
    XCTAssertNotNil(reader.rootCID);
    XCTAssertTrue(reader.blocks.count > 0);
}

- (void)testGetRepoContentsSinceCurrentRevReturnsEmptyDeltaCAR {
    NSError *writeError = nil;
    BOOL putOK = [self.recordService putRecord:@"app.bsky.feed.post"
                                          rkey:@"repo-test-2"
                                         value:[self postRecordWithText:@"since baseline"]
                                        forDid:self.testDID
                                validationMode:PDSValidationModeOff
                                         error:&writeError];
    XCTAssertTrue(putOK);
    XCTAssertNil(writeError);

    NSData *fullCAR = [self.repositoryService getRepoContents:self.testDID since:nil error:nil];
    XCTAssertNotNil(fullCAR);
    NSString *currentRev = [self commitRevFromCARData:fullCAR];
    XCTAssertNotNil(currentRev);

    NSError *deltaError = nil;
    NSData *deltaCAR = [self.repositoryService getRepoContents:self.testDID since:currentRev error:&deltaError];
    XCTAssertNotNil(deltaCAR);
    XCTAssertNil(deltaError);

    NSError *parseError = nil;
    CARReader *reader = [CARReader readFromData:deltaCAR error:&parseError];
    XCTAssertNotNil(reader);
    XCTAssertNil(parseError);
    XCTAssertEqual(reader.blocks.count, 0U);
    XCTAssertNotNil(reader.rootCID);
}

- (void)testGetRepoContentsSinceOlderRevReturnsNonEmptyCAR {
    BOOL firstWrite = [self.recordService putRecord:@"app.bsky.feed.post"
                                               rkey:@"repo-test-3-a"
                                              value:[self postRecordWithText:@"rev-1"]
                                             forDid:self.testDID
                                     validationMode:PDSValidationModeOff
                                              error:nil];
    XCTAssertTrue(firstWrite);

    NSData *firstCAR = [self.repositoryService getRepoContents:self.testDID since:nil error:nil];
    NSString *firstRev = [self commitRevFromCARData:firstCAR];
    XCTAssertNotNil(firstRev);

    BOOL secondWrite = [self.recordService putRecord:@"app.bsky.feed.post"
                                                rkey:@"repo-test-3-b"
                                               value:[self postRecordWithText:@"rev-2"]
                                              forDid:self.testDID
                                      validationMode:PDSValidationModeOff
                                               error:nil];
    XCTAssertTrue(secondWrite);

    NSData *secondCAR = [self.repositoryService getRepoContents:self.testDID since:nil error:nil];
    NSString *secondRev = [self commitRevFromCARData:secondCAR];
    XCTAssertNotNil(secondRev);
    XCTAssertFalse([firstRev isEqualToString:secondRev]);

    NSError *deltaError = nil;
    NSData *deltaCAR = [self.repositoryService getRepoContents:self.testDID since:firstRev error:&deltaError];
    XCTAssertNotNil(deltaCAR);
    XCTAssertNil(deltaError);

    NSError *parseError = nil;
    CARReader *reader = [CARReader readFromData:deltaCAR error:&parseError];
    XCTAssertNotNil(reader);
    XCTAssertNil(parseError);
    XCTAssertTrue(reader.blocks.count > 0);
}

- (void)testGetRepoContentsUnknownSinceFallsBackToFullCAR {
    BOOL wrote = [self.recordService putRecord:@"app.bsky.feed.post"
                                          rkey:@"repo-test-4"
                                         value:[self postRecordWithText:@"unknown since fallback"]
                                        forDid:self.testDID
                                validationMode:PDSValidationModeOff
                                         error:nil];
    XCTAssertTrue(wrote);

    NSData *fullCAR = [self.repositoryService getRepoContents:self.testDID since:nil error:nil];
    XCTAssertNotNil(fullCAR);

    NSData *unknownSinceCAR = [self.repositoryService getRepoContents:self.testDID
                                                                since:@"3jzfcijpj2z2a"
                                                                error:nil];
    XCTAssertNotNil(unknownSinceCAR);

    NSError *fullParseError = nil;
    CARReader *fullReader = [CARReader readFromData:fullCAR error:&fullParseError];
    XCTAssertNil(fullParseError);
    XCTAssertNotNil(fullReader);

    NSError *unknownParseError = nil;
    CARReader *unknownReader = [CARReader readFromData:unknownSinceCAR error:&unknownParseError];
    XCTAssertNil(unknownParseError);
    XCTAssertNotNil(unknownReader);

    XCTAssertEqual(unknownReader.blocks.count, fullReader.blocks.count);
}

- (void)testGetRepoContentsDeltaIncludesOnlyPostSinceRecordBlocks {
    BOOL firstWrite = [self.recordService putRecord:@"app.bsky.feed.post"
                                               rkey:@"repo-test-5-a"
                                              value:[self postRecordWithText:@"before since"]
                                             forDid:self.testDID
                                     validationMode:PDSValidationModeOff
                                              error:nil];
    XCTAssertTrue(firstWrite);

    NSString *firstURI = [NSString stringWithFormat:@"at://%@/%@/%@", self.testDID, @"app.bsky.feed.post", @"repo-test-5-a"];
    NSDictionary *firstRecord = [self.recordService getRecord:firstURI forDid:self.testDID error:nil];
    NSString *firstCID = firstRecord[@"cid"];
    XCTAssertNotNil(firstCID);

    NSData *firstCAR = [self.repositoryService getRepoContents:self.testDID since:nil error:nil];
    NSString *firstRev = [self commitRevFromCARData:firstCAR];
    XCTAssertNotNil(firstRev);

    BOOL secondWrite = [self.recordService putRecord:@"app.bsky.feed.post"
                                                rkey:@"repo-test-5-b"
                                               value:[self postRecordWithText:@"after since"]
                                              forDid:self.testDID
                                      validationMode:PDSValidationModeOff
                                               error:nil];
    XCTAssertTrue(secondWrite);

    NSString *secondURI = [NSString stringWithFormat:@"at://%@/%@/%@", self.testDID, @"app.bsky.feed.post", @"repo-test-5-b"];
    NSDictionary *secondRecord = [self.recordService getRecord:secondURI forDid:self.testDID error:nil];
    NSString *secondCID = secondRecord[@"cid"];
    XCTAssertNotNil(secondCID);

    NSData *deltaCAR = [self.repositoryService getRepoContents:self.testDID since:firstRev error:nil];
    XCTAssertNotNil(deltaCAR);

    XCTAssertTrue([self carData:deltaCAR containsBlockWithCIDString:secondCID]);
    XCTAssertFalse([self carData:deltaCAR containsBlockWithCIDString:firstCID]);
}

- (void)testGetRepoContentsDeltaIncludesCommitDataRootBlock {
    BOOL firstWrite = [self.recordService putRecord:@"app.bsky.feed.post"
                                               rkey:@"repo-test-rootproof-a"
                                              value:[self postRecordWithText:@"root proof baseline"]
                                             forDid:self.testDID
                                     validationMode:PDSValidationModeOff
                                              error:nil];
    XCTAssertTrue(firstWrite);

    NSData *firstCAR = [self.repositoryService getRepoContents:self.testDID since:nil error:nil];
    NSString *firstRev = [self commitRevFromCARData:firstCAR];
    XCTAssertNotNil(firstRev);

    BOOL secondWrite = [self.recordService putRecord:@"app.bsky.feed.post"
                                                rkey:@"repo-test-rootproof-b"
                                               value:[self postRecordWithText:@"root proof delta"]
                                              forDid:self.testDID
                                      validationMode:PDSValidationModeOff
                                               error:nil];
    XCTAssertTrue(secondWrite);

    NSData *deltaCAR = [self.repositoryService getRepoContents:self.testDID since:firstRev error:nil];
    XCTAssertNotNil(deltaCAR);

    CID *dataCID = [self commitDataCIDFromCARData:deltaCAR];
    XCTAssertNotNil(dataCID);

    NSError *parseError = nil;
    CARReader *reader = [CARReader readFromData:deltaCAR error:&parseError];
    XCTAssertNil(parseError);
    XCTAssertNotNil(reader);
    XCTAssertNotNil([reader blockWithCID:dataCID]);
}

- (void)testGetRepoContentsDeltaIsSmallerThanFullSnapshotAfterSingleChange {
    for (NSUInteger i = 0; i < 40; i++) {
        NSString *rkey = [NSString stringWithFormat:@"repo-test-many-%lu", (unsigned long)i];
        NSString *text = [NSString stringWithFormat:@"seed %lu", (unsigned long)i];
        BOOL wrote = [self.recordService putRecord:@"app.bsky.feed.post"
                                              rkey:rkey
                                             value:[self postRecordWithText:text]
                                            forDid:self.testDID
                                    validationMode:PDSValidationModeOff
                                             error:nil];
        XCTAssertTrue(wrote);
    }

    NSData *baselineCAR = [self.repositoryService getRepoContents:self.testDID since:nil error:nil];
    NSString *baselineRev = [self commitRevFromCARData:baselineCAR];
    XCTAssertNotNil(baselineRev);

    BOOL wroteDelta = [self.recordService putRecord:@"app.bsky.feed.post"
                                               rkey:@"repo-test-many-delta"
                                              value:[self postRecordWithText:@"single delta mutation"]
                                             forDid:self.testDID
                                     validationMode:PDSValidationModeOff
                                              error:nil];
    XCTAssertTrue(wroteDelta);

    NSData *deltaCAR = [self.repositoryService getRepoContents:self.testDID since:baselineRev error:nil];
    NSData *fullAfterCAR = [self.repositoryService getRepoContents:self.testDID since:nil error:nil];
    XCTAssertNotNil(deltaCAR);
    XCTAssertNotNil(fullAfterCAR);

    NSError *deltaParseError = nil;
    CARReader *deltaReader = [CARReader readFromData:deltaCAR error:&deltaParseError];
    XCTAssertNil(deltaParseError);
    XCTAssertNotNil(deltaReader);

    NSError *fullParseError = nil;
    CARReader *fullReader = [CARReader readFromData:fullAfterCAR error:&fullParseError];
    XCTAssertNil(fullParseError);
    XCTAssertNotNil(fullReader);

    XCTAssertLessThan(deltaReader.blocks.count, fullReader.blocks.count);
}

- (void)testGetRepoContentsSincePreDeleteRevIncludesDeltaWithoutDeletedRecordBlock {
    BOOL writeOK = [self.recordService putRecord:@"app.bsky.feed.post"
                                            rkey:@"repo-test-delete-delta"
                                           value:[self postRecordWithText:@"delete me"]
                                          forDid:self.testDID
                                  validationMode:PDSValidationModeOff
                                           error:nil];
    XCTAssertTrue(writeOK);

    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", self.testDID, @"app.bsky.feed.post", @"repo-test-delete-delta"];
    NSDictionary *record = [self.recordService getRecord:uri forDid:self.testDID error:nil];
    NSString *deletedCID = record[@"cid"];
    XCTAssertNotNil(deletedCID);

    NSData *beforeDeleteCAR = [self.repositoryService getRepoContents:self.testDID since:nil error:nil];
    NSString *beforeDeleteRev = [self commitRevFromCARData:beforeDeleteCAR];
    XCTAssertNotNil(beforeDeleteRev);

    BOOL deleteOK = [self.recordService deleteRecord:@"app.bsky.feed.post"
                                                rkey:@"repo-test-delete-delta"
                                              forDid:self.testDID
                                               error:nil];
    XCTAssertTrue(deleteOK);

    NSData *deltaCAR = [self.repositoryService getRepoContents:self.testDID since:beforeDeleteRev error:nil];
    XCTAssertNotNil(deltaCAR);
    XCTAssertFalse([self carData:deltaCAR containsBlockWithCIDString:deletedCID]);

    NSError *deltaParseError = nil;
    CARReader *deltaReader = [CARReader readFromData:deltaCAR error:&deltaParseError];
    XCTAssertNil(deltaParseError);
    XCTAssertNotNil(deltaReader);
    XCTAssertGreaterThan(deltaReader.blocks.count, 0U);

    CID *dataCID = [self commitDataCIDFromCARData:deltaCAR];
    XCTAssertNotNil(dataCID);
    XCTAssertNotNil([deltaReader blockWithCID:dataCID]);
}

- (void)testGetRepoContentsSinceCreateMutationRevReturnsEmptyDelta {
    BOOL writeOK = [self.recordService putRecord:@"app.bsky.feed.post"
                                            rkey:@"repo-test-6-a"
                                           value:[self postRecordWithText:@"create rev baseline"]
                                          forDid:self.testDID
                                  validationMode:PDSValidationModeOff
                                           error:nil];
    XCTAssertTrue(writeOK);

    NSString *latestRev = [self latestMutationRevForTestDid];
    XCTAssertNotNil(latestRev);
    XCTAssertTrue(latestRev.length > 0);

    NSError *deltaError = nil;
    NSData *deltaCAR = [self.repositoryService getRepoContents:self.testDID since:latestRev error:&deltaError];
    XCTAssertNotNil(deltaCAR);
    XCTAssertNil(deltaError);

    NSError *parseError = nil;
    CARReader *reader = [CARReader readFromData:deltaCAR error:&parseError];
    XCTAssertNotNil(reader);
    XCTAssertNil(parseError);
    XCTAssertEqual(reader.blocks.count, 0U);
}

- (void)testGetRepoContentsSinceDeleteMutationRevReturnsEmptyDelta {
    BOOL writeOK = [self.recordService putRecord:@"app.bsky.feed.post"
                                            rkey:@"repo-test-7-a"
                                           value:[self postRecordWithText:@"delete rev baseline"]
                                          forDid:self.testDID
                                  validationMode:PDSValidationModeOff
                                           error:nil];
    XCTAssertTrue(writeOK);

    BOOL deleteOK = [self.recordService deleteRecord:@"app.bsky.feed.post"
                                                rkey:@"repo-test-7-a"
                                              forDid:self.testDID
                                               error:nil];
    XCTAssertTrue(deleteOK);

    NSString *latestRev = [self latestMutationRevForTestDid];
    XCTAssertNotNil(latestRev);
    XCTAssertTrue(latestRev.length > 0);

    NSError *deltaError = nil;
    NSData *deltaCAR = [self.repositoryService getRepoContents:self.testDID since:latestRev error:&deltaError];
    XCTAssertNotNil(deltaCAR);
    XCTAssertNil(deltaError);

    NSError *parseError = nil;
    CARReader *reader = [CARReader readFromData:deltaCAR error:&parseError];
    XCTAssertNotNil(reader);
    XCTAssertNil(parseError);
    XCTAssertEqual(reader.blocks.count, 0U);
}

- (void)testWriteRepoContentsToPathRoundTripsCAR {
    BOOL writeOK = [self.recordService putRecord:@"app.bsky.feed.post"
                                            rkey:@"repo-test-writepath"
                                           value:[self postRecordWithText:@"write to path"]
                                          forDid:self.testDID
                                  validationMode:PDSValidationModeOff
                                           error:nil];
    XCTAssertTrue(writeOK);

    NSString *fullPath = [self.testDirectory stringByAppendingPathComponent:@"repo-full.car"];
    NSError *fullWriteError = nil;
    BOOL fullExported = [self.repositoryService writeRepoContents:self.testDID
                                                            since:nil
                                                           toPath:fullPath
                                                            error:&fullWriteError];
    XCTAssertTrue(fullExported);
    XCTAssertNil(fullWriteError);

    NSError *fullReadError = nil;
    CARReader *fullReader = [CARReader readFromPath:fullPath error:&fullReadError];
    XCTAssertNotNil(fullReader);
    XCTAssertNil(fullReadError);
    XCTAssertNotNil(fullReader.rootCID);
    XCTAssertTrue(fullReader.blocks.count > 0);

    NSString *currentRev = [self commitRevFromCARData:[self.repositoryService getRepoContents:self.testDID since:nil error:nil]];
    XCTAssertNotNil(currentRev);

    NSString *deltaPath = [self.testDirectory stringByAppendingPathComponent:@"repo-delta-empty.car"];
    NSError *deltaWriteError = nil;
    BOOL deltaExported = [self.repositoryService writeRepoContents:self.testDID
                                                             since:currentRev
                                                            toPath:deltaPath
                                                             error:&deltaWriteError];
    XCTAssertTrue(deltaExported);
    XCTAssertNil(deltaWriteError);

    NSError *deltaReadError = nil;
    CARReader *deltaReader = [CARReader readFromPath:deltaPath error:&deltaReadError];
    XCTAssertNotNil(deltaReader);
    XCTAssertNil(deltaReadError);
    XCTAssertEqual(deltaReader.blocks.count, 0U);
    XCTAssertNotNil(deltaReader.rootCID);
}

@end
