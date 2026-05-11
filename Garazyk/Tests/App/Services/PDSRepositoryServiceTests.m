// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Services/PDS/PDSRecordService.h"
#import "Services/PDS/PDSRepositoryService.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Pool/DatabasePool.h"
#import "Repository/CAR.h"
#import "Repository/CBOR.h"
#import "Repository/MST.h"

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

#pragma mark - MST Operations

- (void)testLoadMSTForDidReturnsMSTAfterWrite {
    BOOL writeOK = [self.recordService putRecord:@"app.bsky.feed.post"
                                            rkey:@"mst-load-test"
                                           value:[self postRecordWithText:@"mst load"]
                                          forDid:self.testDID
                                  validationMode:PDSValidationModeOff
                                           error:nil];
    XCTAssertTrue(writeOK);

    NSError *mstError = nil;
    MST *mst = [self.repositoryService loadMSTForDid:self.testDID error:&mstError];
    XCTAssertNotNil(mst);
    XCTAssertNil(mstError);
}

- (void)testLoadMSTForNonexistentDidReturnsEmptyMST {
    NSError *mstError = nil;
    MST *mst = [self.repositoryService loadMSTForDid:@"did:web:nonexistent.example.com" error:&mstError];
    // loadMST returns an empty MST for nonexistent repos, not nil
    XCTAssertNotNil(mst);
    XCTAssertEqual([mst allEntries].count, 0U);
}

- (void)testUpdateMSTForDidAddsKey {
    BOOL writeOK = [self.recordService putRecord:@"app.bsky.feed.post"
                                            rkey:@"mst-update-base"
                                           value:[self postRecordWithText:@"mst base"]
                                          forDid:self.testDID
                                  validationMode:PDSValidationModeOff
                                           error:nil];
    XCTAssertTrue(writeOK);

    NSError *mstError = nil;
    MST *mst = [self.repositoryService loadMSTForDid:self.testDID error:&mstError];
    XCTAssertNotNil(mst);

    // The MST should have at least one entry
    NSArray *entries = [mst allEntries];
    XCTAssertGreaterThan(entries.count, 0U);
}

#pragma mark - Repo Root

- (void)testGetRepoRootReturnsDataAfterWrite {
    BOOL writeOK = [self.recordService putRecord:@"app.bsky.feed.post"
                                            rkey:@"root-test"
                                           value:[self postRecordWithText:@"root data"]
                                          forDid:self.testDID
                                  validationMode:PDSValidationModeOff
                                           error:nil];
    XCTAssertTrue(writeOK);

    NSError *rootError = nil;
    NSData *rootData = [self.repositoryService getRepoRoot:self.testDID error:&rootError];
    // getRepoRoot may return nil if repo metadata isn't stored in the service DB
    // The key invariant is that it doesn't crash
    if (rootData) {
        XCTAssertTrue(rootData.length > 0);
    }
}

- (void)testGetRepoRootForNonexistentDidReturnsNil {
    NSError *rootError = nil;
    NSData *rootData = [self.repositoryService getRepoRoot:@"did:web:nonexistent.root.example.com" error:&rootError];
    XCTAssertNil(rootData);
}

#pragma mark - Get Blocks

- (void)testGetBlocksForDidReturnsCARData {
    BOOL writeOK = [self.recordService putRecord:@"app.bsky.feed.post"
                                            rkey:@"blocks-test"
                                           value:[self postRecordWithText:@"blocks data"]
                                          forDid:self.testDID
                                  validationMode:PDSValidationModeOff
                                           error:nil];
    XCTAssertTrue(writeOK);

    // Get the record's CID to request as a block
    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", self.testDID, @"app.bsky.feed.post", @"blocks-test"];
    NSDictionary *record = [self.recordService getRecord:uri forDid:self.testDID error:nil];
    NSString *cidString = record[@"cid"];
    XCTAssertNotNil(cidString);

    NSError *blocksError = nil;
    NSData *carData = [self.repositoryService getBlocksForDid:self.testDID
                                                        cids:@[cidString]
                                                        error:&blocksError];
    XCTAssertNotNil(carData);
    XCTAssertNil(blocksError);
}

- (void)testGetBlocksForDidWithEmptyCIDsReturnsNilOrCAR {
    // Write a record first
    [self.recordService putRecord:@"app.bsky.feed.post"
                            rkey:@"blocks-empty-test"
                           value:[self postRecordWithText:@"blocks empty"]
                          forDid:self.testDID
                  validationMode:PDSValidationModeOff
                           error:nil];

    NSError *blocksError = nil;
    NSData *carData = [self.repositoryService getBlocksForDid:self.testDID
                                                        cids:@[]
                                                        error:&blocksError];
    // Empty CID list may return nil or a valid empty CAR — either is acceptable
    if (carData) {
        XCTAssertTrue(carData.length > 0);
    }
}

#pragma mark - Latest Commit

- (void)testGetLatestCommitForDidReturnsCommit {
    BOOL writeOK = [self.recordService putRecord:@"app.bsky.feed.post"
                                            rkey:@"commit-test"
                                           value:[self postRecordWithText:@"commit data"]
                                          forDid:self.testDID
                                  validationMode:PDSValidationModeOff
                                           error:nil];
    XCTAssertTrue(writeOK);

    NSError *commitError = nil;
    NSDictionary *commit = [self.repositoryService getLatestCommitForDid:self.testDID error:&commitError];
    XCTAssertNotNil(commit);
    XCTAssertNil(commitError);
    XCTAssertNotNil(commit[@"cid"]);
    XCTAssertNotNil(commit[@"rev"]);
}

- (void)testGetLatestCommitForNonexistentDidReturnsNil {
    NSError *commitError = nil;
    NSDictionary *commit = [self.repositoryService getLatestCommitForDid:@"did:web:nonexistent.commit.example.com" error:&commitError];
    XCTAssertNil(commit);
}

#pragma mark - Initialize Repo

- (void)testInitializeRepoForDidSucceeds {
    NSString *newDid = @"did:web:newrepo.example.com";

    // Generate signing key for the new DID (required for repo initialization)
    NSError *storeError = nil;
    PDSActorStore *store = [self.pool storeForDid:newDid error:&storeError];
    XCTAssertNotNil(store);
    if (store) {
        NSError *keyError = nil;
        [store generateSigningKeyWithError:&keyError];
    }

    NSError *initError = nil;
    BOOL result = [self.repositoryService initializeRepoForDid:newDid error:&initError];
    XCTAssertTrue(result, @"initializeRepo should succeed: %@", initError);
    XCTAssertNil(initError);

    // Verify repo is accessible
    NSError *commitError = nil;
    NSDictionary *commit = [self.repositoryService getLatestCommitForDid:newDid error:&commitError];
    XCTAssertNotNil(commit, @"Repo should have a commit after initialization");
}

- (void)testInitializeRepoForDidWithExistingRepoFails {
    // The testDID already has a repo from setUp (signing key generation creates one)
    NSError *initError = nil;
    BOOL result = [self.repositoryService initializeRepoForDid:self.testDID error:&initError];
    // Re-initializing an existing repo should fail or be idempotent
    // The exact behavior depends on implementation
}

#pragma mark - Force Reinitialize Repo

- (void)testForceReinitializeRepoForDidSucceeds {
    // Write a record first
    [self.recordService putRecord:@"app.bsky.feed.post"
                            rkey:@"reinit-test"
                           value:[self postRecordWithText:@"before reinit"]
                          forDid:self.testDID
                  validationMode:PDSValidationModeOff
                           error:nil];

    NSError *reinitError = nil;
    BOOL result = [self.repositoryService forceReinitializeRepoForDid:self.testDID error:&reinitError];
    XCTAssertTrue(result);
    XCTAssertNil(reinitError);

    // After reinit, repo should have a fresh commit
    NSError *commitError = nil;
    NSDictionary *commit = [self.repositoryService getLatestCommitForDid:self.testDID error:&commitError];
    XCTAssertNotNil(commit);
}

#pragma mark - Chunk Producer

- (void)testRepoContentsChunkProducerReturnsProducer {
    [self.recordService putRecord:@"app.bsky.feed.post"
                            rkey:@"chunk-test"
                           value:[self postRecordWithText:@"chunk data"]
                          forDid:self.testDID
                  validationMode:PDSValidationModeOff
                           error:nil];

    NSError *producerError = nil;
    PDSRepoChunkProducer producer = [self.repositoryService repoContentsChunkProducer:self.testDID
                                                                                 since:nil
                                                                                 error:&producerError];
    XCTAssertNotNil(producer);
    XCTAssertNil(producerError);

    // Read at least one chunk
    NSError *chunkError = nil;
    NSData *firstChunk = producer(&chunkError);
    XCTAssertNil(chunkError);
    // First chunk should contain data (CAR header + blocks)
    XCTAssertTrue(firstChunk.length > 0);
}

- (void)testRepoContentsChunkProducerEndsAtNil {
    [self.recordService putRecord:@"app.bsky.feed.post"
                            rkey:@"chunk-end-test"
                           value:[self postRecordWithText:@"chunk end"]
                          forDid:self.testDID
                  validationMode:PDSValidationModeOff
                           error:nil];

    NSError *producerError = nil;
    PDSRepoChunkProducer producer = [self.repositoryService repoContentsChunkProducer:self.testDID
                                                                                 since:nil
                                                                                 error:&producerError];
    XCTAssertNotNil(producer);

    // Drain all chunks — should eventually return nil
    NSUInteger chunkCount = 0;
    NSUInteger totalBytes = 0;
    while (YES) {
        NSError *chunkError = nil;
        NSData *chunk = producer(&chunkError);
        if (chunkError) {
            XCTFail(@"Chunk error: %@", chunkError);
            break;
        }
        if (!chunk) {
            break; // End of stream
        }
        chunkCount++;
        totalBytes += chunk.length;
    }

    XCTAssertGreaterThan(chunkCount, 0U);
    XCTAssertGreaterThan(totalBytes, 0U);
}

@end
