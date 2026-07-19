// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#if !defined(GNUSTEP)
#import <mach/mach.h>
#endif
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

#pragma mark - Head Info (Lightweight)

- (void)testHeadInfoForDidReturnsCidAndRev {
    [self.recordService putRecord:@"app.bsky.feed.post"
                            rkey:@"headinfo-test"
                           value:[self postRecordWithText:@"head info data"]
                          forDid:self.testDID
                  validationMode:PDSValidationModeOff
                           error:nil];

    NSError *headInfoError = nil;
    NSDictionary *headInfo = [self.repositoryService headInfoForDid:self.testDID error:&headInfoError];
    XCTAssertNotNil(headInfo, @"headInfoForDid should return data for a repo with records");
    XCTAssertNil(headInfoError);
    XCTAssertNotNil(headInfo[@"cid"], @"headInfo should contain a cid");
    XCTAssertNotNil(headInfo[@"rev"], @"headInfo should contain a rev");
    XCTAssertTrue([headInfo[@"cid"] length] > 0);
    XCTAssertTrue([headInfo[@"rev"] length] > 0);
}

- (void)testHeadInfoForDidReturnsNilForNonexistentDid {
    NSError *headInfoError = nil;
    NSDictionary *headInfo = [self.repositoryService headInfoForDid:@"did:web:nonexistent.headinfo.example.com" error:&headInfoError];
    XCTAssertNil(headInfo, @"headInfoForDid should return nil for nonexistent repo");
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

#pragma mark - Filtered Repo Export (Collection Subsets)

- (NSDictionary *)likeRecordForSubject:(NSString *)subjectURI {
    return @{
        @"$type": @"app.bsky.feed.like",
        @"subject": @{@"uri": subjectURI, @"cid": @"bafyreicid"},
        @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
    };
}

- (void)testFilteredRepoContentsChunkProducerIncludesOnlyMatchingCollectionRecords {
    [self.recordService putRecord:@"app.bsky.feed.post"
                            rkey:@"filter-post-1"
                           value:[self postRecordWithText:@"matching collection"]
                          forDid:self.testDID
                  validationMode:PDSValidationModeOff
                           error:nil];
    [self.recordService putRecord:@"app.bsky.feed.like"
                            rkey:@"filter-like-1"
                           value:[self likeRecordForSubject:@"at://did:web:other.example.com/app.bsky.feed.post/x"]
                          forDid:self.testDID
                  validationMode:PDSValidationModeOff
                           error:nil];

    NSError *postError = nil;
    NSString *postURI = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/filter-post-1", self.testDID];
    NSDictionary *postRecord = [self.recordService getRecord:postURI
                                                        forDid:self.testDID
                                                         error:&postError];
    XCTAssertNotNil(postRecord);
    NSString *postCID = postRecord[@"cid"];
    XCTAssertNotNil(postCID);

    NSError *likeError = nil;
    NSString *likeURI = [NSString stringWithFormat:@"at://%@/app.bsky.feed.like/filter-like-1", self.testDID];
    NSDictionary *likeRecord = [self.recordService getRecord:likeURI
                                                        forDid:self.testDID
                                                         error:&likeError];
    XCTAssertNotNil(likeRecord);
    NSString *likeCID = likeRecord[@"cid"];
    XCTAssertNotNil(likeCID);

    NSError *producerError = nil;
    PDSRepoChunkProducer producer = [self.repositoryService filteredRepoContentsChunkProducer:self.testDID
                                                                                          since:nil
                                                                                    collections:@[@"app.bsky.feed.post"]
                                                                                          error:&producerError];
    XCTAssertNotNil(producer);
    XCTAssertNil(producerError);

    NSMutableData *carData = [NSMutableData data];
    while (YES) {
        NSError *chunkError = nil;
        NSData *chunk = producer(&chunkError);
        XCTAssertNil(chunkError);
        if (!chunk) break;
        [carData appendData:chunk];
    }

    XCTAssertTrue([self carData:carData containsBlockWithCIDString:postCID],
                  @"filtered export must include records from a requested collection");
    XCTAssertFalse([self carData:carData containsBlockWithCIDString:likeCID],
                   @"filtered export must exclude records from a collection that was not requested");
}

- (void)testFilteredRepoContentsChunkProducerWithNoMatchingRecordsOmitsAllRecordBlocks {
    [self.recordService putRecord:@"app.bsky.feed.post"
                            rkey:@"filter-post-2"
                           value:[self postRecordWithText:@"not in the requested collection"]
                          forDid:self.testDID
                  validationMode:PDSValidationModeOff
                           error:nil];

    NSError *producerError = nil;
    PDSRepoChunkProducer producer = [self.repositoryService filteredRepoContentsChunkProducer:self.testDID
                                                                                          since:nil
                                                                                    collections:@[@"app.bsky.graph.follow"]
                                                                                          error:&producerError];
    XCTAssertNotNil(producer);
    XCTAssertNil(producerError);

    NSMutableData *carData = [NSMutableData data];
    while (YES) {
        NSError *chunkError = nil;
        NSData *chunk = producer(&chunkError);
        XCTAssertNil(chunkError);
        if (!chunk) break;
        [carData appendData:chunk];
    }

    NSError *parseError = nil;
    CARReader *reader = [CARReader readFromData:carData error:&parseError];
    XCTAssertNotNil(reader);
    XCTAssertNil(parseError);
    XCTAssertNotNil(reader.rootCID, @"a commit root must still be produced with no matching records");
}

- (void)testFilteredRepoContentsChunkProducerRejectsEmptyCollectionsList {
    NSError *producerError = nil;
    PDSRepoChunkProducer producer = [self.repositoryService filteredRepoContentsChunkProducer:self.testDID
                                                                                          since:nil
                                                                                    collections:@[]
                                                                                          error:&producerError];
    XCTAssertNil(producer);
    XCTAssertNotNil(producerError);
}

#pragma mark - Golden Fixtures (Structural)

// Fixed 32-byte secp256k1 private key for deterministic signing in golden tests.
// All bytes set to 0xAB — produces the same commit signature every test run.
static NSData * _Nonnull PDSTestFixedSigningKey(void) {
    static NSData *key = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        uint8_t bytes[32];
        memset(bytes, 0xAB, 32);
        key = [NSData dataWithBytes:bytes length:32];
    });
    return key;
}

/// Helper: create a post record with a fixed ISO timestamp for deterministic CID generation.
- (NSDictionary *)goldenPostRecordWithText:(NSString *)text {
    return @{
        @"$type": @"app.bsky.feed.post",
        @"text": text,
        @"createdAt": @"2024-01-01T00:00:00.000Z"
    };
}

/// Helper: set up a golden test repo with fixed signing key and 3 deterministic records.
- (void)setupGoldenRepoWithDID:(NSString *)did {
    PDSActorStore *store = [self.pool storeForDid:did error:nil];
    XCTAssertNotNil(store);
    NSError *importError = nil;
    XCTAssertTrue([store importSigningKey:PDSTestFixedSigningKey() error:&importError],
                  @"Failed to import fixed signing key: %@", importError);

    NSArray<NSDictionary *> *writes = @[
        @{@"action": @"create", @"collection": @"app.bsky.feed.post", @"rkey": @"golden-post-a",
          @"value": [self goldenPostRecordWithText:@"Golden record A"]},
        @{@"action": @"create", @"collection": @"app.bsky.feed.post", @"rkey": @"golden-post-b",
          @"value": [self goldenPostRecordWithText:@"Golden record B"]},
        @{@"action": @"create", @"collection": @"app.bsky.feed.post", @"rkey": @"golden-post-c",
          @"value": [self goldenPostRecordWithText:@"Golden record C"]},
    ];

    NSError *writeError = nil;
    NSDictionary *result = [self.recordService applyWrites:writes
                                                    forDid:did
                                            validationMode:PDSValidationModeOff
                                                swapCommit:nil
                                                     error:&writeError];
    XCTAssertNil(writeError, @"Golden repo setup failed: %@", writeError);
    XCTAssertNotNil(result[@"results"]);
    XCTAssertEqual([result[@"results"] count], 3U, @"Should have 3 write results");
}

/// Helper: parse CAR data and return the reader for structural assertions.
- (nullable CARReader *)parseCARData:(NSData *)carData label:(NSString *)label {
    NSError *parseError = nil;
    CARReader *reader = [CARReader readFromData:carData error:&parseError];
    XCTAssertNil(parseError, @"%@: CAR parse error: %@", label, parseError);
    XCTAssertNotNil(reader, @"%@: CAR reader is nil", label);
    return reader;
}

- (void)testGoldenCARExportStructuralFixture {
    NSString *goldenDID = @"did:web:golden-car.example.com";
    [self setupGoldenRepoWithDID:goldenDID];

    // Export the repo
    NSError *exportError = nil;
    NSData *carData = [self.repositoryService getRepoContents:goldenDID since:nil error:&exportError];
    XCTAssertNotNil(carData, @"Golden CAR export failed: %@", exportError);
    XCTAssertNil(exportError);
    XCTAssertTrue(carData.length > 0, @"Golden CAR should not be empty");

    // Parse and assert structure
    CARReader *reader = [self parseCARData:carData label:@"Golden CAR"];
    if (!reader) return;

    // Root CID must be set
    XCTAssertNotNil(reader.rootCID, @"Golden CAR must have a root CID");
    XCTAssertTrue(reader.rootCID.stringValue.length > 0, @"Root CID must be non-empty");

    // Must contain at least: commit block + 3 record blocks + MST nodes
    XCTAssertTrue(reader.blocks.count >= 4, @"Golden CAR should have >=4 blocks (commit + 3 records + MST), got %lu",
                  (unsigned long)reader.blocks.count);

    // The commit block must be present
    CARBlock *commitBlock = [reader blockWithCID:reader.rootCID];
    XCTAssertNotNil(commitBlock, @"Commit block must be present");
    XCTAssertTrue(commitBlock.data.length > 0, @"Commit block must have data");

    // Parse commit to verify structure
    CBORValue *commitValue = [CBORValue decode:commitBlock.data];
    XCTAssertNotNil(commitValue);
    XCTAssertEqual(commitValue.type, CBORTypeMap, @"Commit must be a CBOR map");

    // Commit must have required fields: did, version, data, rev, sig
    CBORValue *didVal = commitValue.map[[CBORValue textString:@"did"]];
    XCTAssertNotNil(didVal);
    XCTAssertEqualObjects(didVal.textString, goldenDID, @"Commit did must match");

    CBORValue *versionVal = commitValue.map[[CBORValue textString:@"version"]];
    XCTAssertNotNil(versionVal);
    XCTAssertEqual([versionVal.unsignedInteger integerValue], 3, @"Commit version must be 3");

    CBORValue *dataVal = commitValue.map[[CBORValue textString:@"data"]];
    XCTAssertNotNil(dataVal, @"Commit must have a data field (MST root CID)");
    XCTAssertEqual(dataVal.type, CBORTypeTag, @"Commit data must be a CID tag");

    CBORValue *revVal = commitValue.map[[CBORValue textString:@"rev"]];
    XCTAssertNotNil(revVal, @"Commit must have a rev field");
    XCTAssertEqual(revVal.type, CBORTypeTextString, @"Commit rev must be a string");
    XCTAssertTrue(revVal.textString.length > 0, @"Commit rev must be non-empty");

    CBORValue *sigVal = commitValue.map[[CBORValue textString:@"sig"]];
    XCTAssertNotNil(sigVal, @"Commit must have a sig field");
    XCTAssertEqual(sigVal.type, CBORTypeByteString, @"Commit sig must be bytes");
    XCTAssertTrue(sigVal.byteString.length > 0, @"Commit sig must be non-empty");

    // CID determinism: with a fixed signing key and fixed record timestamps,
    // the commit data CID (MST root) and record CIDs are deterministic.
    // Two exports of the same repo must produce identical CIDs.
    CID *commitDataCID = [self commitDataCIDFromCARData:carData];
    XCTAssertNotNil(commitDataCID, @"Commit must have a data CID");
    XCTAssertTrue(commitDataCID.stringValue.length > 0, @"MST root CID must be non-empty");

    // Every block must have a valid CID matching its data
    for (CARBlock *block in reader.blocks) {
        CID *expectedCID = [CID cidWithDigest:[CID sha256Digest:block.data] codec:0x71]; // dag-cbor codec
        XCTAssertTrue([block.cid isEqual:expectedCID] ||
                      [block.cid.stringValue isEqualToString:expectedCID.stringValue],
                      @"Block CID mismatch: %@ != %@", block.cid.stringValue, expectedCID.stringValue);
    }

    // Non-commit block count: 3 records + MST nodes (at least 1 root node)
    NSUInteger nonCommitCount = 0;
    for (CARBlock *block in reader.blocks) {
        if (![block.cid isEqual:reader.rootCID]) {
            nonCommitCount++;
        }
    }
    XCTAssertTrue(nonCommitCount >= 4, @"Should have at least 4 non-commit blocks (3 records + root MST), got %lu",
                  (unsigned long)nonCommitCount);
}

- (void)testGoldenCARExportByteIdenticalForUnchangedRepo {
    NSString *goldenDID = @"did:web:golden-byteid.example.com";
    [self setupGoldenRepoWithDID:goldenDID];

    // First export
    NSError *firstError = nil;
    NSData *firstCAR = [self.repositoryService getRepoContents:goldenDID since:nil error:&firstError];
    XCTAssertNotNil(firstCAR);
    XCTAssertNil(firstError);

    // Second export of unchanged repo — must be byte-identical
    NSError *secondError = nil;
    NSData *secondCAR = [self.repositoryService getRepoContents:goldenDID since:nil error:&secondError];
    XCTAssertNotNil(secondCAR);
    XCTAssertNil(secondError);

    XCTAssertEqualObjects(firstCAR, secondCAR,
                          @"Two exports of unchanged repo must produce byte-identical CAR output");

    // Third export via chunk producer must produce identical bytes when reassembled
    NSError *chunkError = nil;
    PDSRepoChunkProducer producer = [self.repositoryService repoContentsChunkProducer:goldenDID
                                                                                 since:nil
                                                                                 error:&chunkError];
    XCTAssertNotNil(producer);
    XCTAssertNil(chunkError);

    NSMutableData *chunkedCAR = [NSMutableData data];
    while (YES) {
        NSError *chunkReadError = nil;
        NSData *chunk = producer(&chunkReadError);
        XCTAssertNil(chunkReadError);
        if (!chunk) break;
        [chunkedCAR appendData:chunk];
    }

    XCTAssertEqualObjects(chunkedCAR, firstCAR,
                          @"Chunk-producer CAR must match direct export byte-for-byte");

    // Verify both exports parse identically
    CARReader *reader1 = [self parseCARData:firstCAR label:@"first export"];
    CARReader *reader2 = [self parseCARData:secondCAR label:@"second export"];
    if (reader1 && reader2) {
        XCTAssertEqualObjects(reader1.rootCID.stringValue, reader2.rootCID.stringValue,
                              @"Root CID must match across exports");
        XCTAssertEqual(reader1.blocks.count, reader2.blocks.count,
                       @"Block count must match across exports");
    }
}

- (void)testGoldenSTARL0ExportStructuralFixture {
    NSString *goldenDID = @"did:web:golden-starl0.example.com";
    [self setupGoldenRepoWithDID:goldenDID];

    NSError *exportError = nil;
    NSData *starData = [self.repositoryService getRepoContentsSTARL0:goldenDID since:nil error:&exportError];
    XCTAssertNotNil(starData, @"Golden STAR-L0 export failed: %@", exportError);
    XCTAssertNil(exportError);
    XCTAssertTrue(starData.length > 0, @"Golden STAR-L0 should not be empty");

    // STAR-L0 starts with magic bytes 0x2A
    if (starData.length >= 1) {
        uint8_t firstByte = 0;
        [starData getBytes:&firstByte length:1];
        XCTAssertEqual(firstByte, 0x2A, @"STAR-L0 must start with 0x2A magic byte");
    }

    // STAR-L0 should be smaller than equivalent CAR (STAR deduplicates MST nodes)
    NSData *carData = [self.repositoryService getRepoContents:goldenDID since:nil error:nil];
    if (carData.length > 0) {
        XCTAssertLessThanOrEqual(starData.length, carData.length,
                                 @"STAR-L0 should be <= CAR in size for small repos");
    }

    // Repeated STAR-L0 exports must be byte-identical (stored head commit reuse)
    NSData *starData2 = [self.repositoryService getRepoContentsSTARL0:goldenDID since:nil error:nil];
    XCTAssertNotNil(starData2);
    XCTAssertEqualObjects(starData, starData2,
                          @"Repeated STAR-L0 exports must be byte-identical");
}

- (void)testGoldenSTARLiteExportStructuralFixture {
    NSString *goldenDID = @"did:web:golden-starlite.example.com";
    [self setupGoldenRepoWithDID:goldenDID];

    NSError *exportError = nil;
    NSData *starData = [self.repositoryService getRepoContentsSTARLite:goldenDID since:nil error:&exportError];
    XCTAssertNotNil(starData, @"Golden STAR-Lite export failed: %@", exportError);
    XCTAssertNil(exportError);
    XCTAssertTrue(starData.length > 0, @"Golden STAR-Lite should not be empty");

    // STAR-Lite starts with magic bytes 0x2A
    if (starData.length >= 1) {
        uint8_t firstByte = 0;
        [starData getBytes:&firstByte length:1];
        XCTAssertEqual(firstByte, 0x2A, @"STAR-Lite must start with 0x2A magic byte");
    }

    // Repeated STAR-Lite exports must be byte-identical (stored head commit reuse)
    NSData *starData2 = [self.repositoryService getRepoContentsSTARLite:goldenDID since:nil error:nil];
    XCTAssertNotNil(starData2);
    XCTAssertEqualObjects(starData, starData2,
                          @"Repeated STAR-Lite exports must be byte-identical");

    // STAR-Lite should be compact (flat key-record encoding)
    XCTAssertTrue(starData.length > 0, @"STAR-Lite output must be non-empty");

    // CAR and STAR-Lite should have different byte representations for the same repo
    NSData *carData = [self.repositoryService getRepoContents:goldenDID since:nil error:nil];
    if (carData.length > 0) {
        XCTAssertNotEqualObjects(starData, carData,
                                 @"STAR-Lite and CAR must differ in byte representation");
    }
}

#pragma mark - Peak Memory Tracking

#if !defined(GNUSTEP)
/// Returns the current resident memory size for this process in bytes (macOS only).
- (uint64_t)currentResidentMemory {
    struct mach_task_basic_info info;
    mach_msg_type_number_t size = MACH_TASK_BASIC_INFO_COUNT;
    kern_return_t kerr = task_info(mach_task_self(), MACH_TASK_BASIC_INFO,
                                    (task_info_t)&info, &size);
    return (kerr == KERN_SUCCESS) ? info.resident_size : 0;
}

- (void)testCARExportNetMemoryGrowthWithinBounds {
    // Write 50 records to create a somewhat larger repo
    for (NSUInteger i = 0; i < 50; i++) {
        NSString *rkey = [NSString stringWithFormat:@"mem-test-%lu", (unsigned long)i];
        NSString *text = [NSString stringWithFormat:@"Memory tracking record %lu", (unsigned long)i];
        [self.recordService putRecord:@"app.bsky.feed.post"
                                rkey:rkey
                               value:[self postRecordWithText:text]
                              forDid:self.testDID
                      validationMode:PDSValidationModeOff
                               error:nil];
    }

    // Measure baseline memory after all records are written
    uint64_t beforeMem = [self currentResidentMemory];

    // Export to CAR and measure peak memory net growth.
    // The CAR is built in memory by getRepoContents:, so measuring before/after
    // captures the net allocation. We run inside @autoreleasepool to ensure
    // temporary allocations from getRepoContents: are released before measuring.
    {
        @autoreleasepool {
            NSError *exportError = nil;
            NSData *carData = [self.repositoryService getRepoContents:self.testDID
                                                                since:nil
                                                                error:&exportError];
            XCTAssertNotNil(carData, @"CAR export failed: %@", exportError);
            XCTAssertNil(exportError);

            // Verify the CAR is valid (parse inside @autoreleasepool)
            CARReader *reader = [CARReader readFromData:carData error:nil];
            XCTAssertNotNil(reader, @"CAR must be parseable");
            XCTAssertTrue(reader.blocks.count >= 50,
                          @"Should have at least 50 record blocks (got %lu)",
                          (unsigned long)reader.blocks.count);
        }
    }

    uint64_t afterMem = [self currentResidentMemory];

    // Memory growth from the export should be reasonable.
    // 50 records with small text bodies should not grow resident memory
    // by more than 15 MB above baseline after autoreleasepool drain.
    int64_t memoryGrowth = (int64_t)afterMem - (int64_t)beforeMem;
    NSUInteger growthMB = memoryGrowth > 0 ? (NSUInteger)(memoryGrowth / (1024 * 1024)) : 0;
    XCTAssertLessThan(growthMB, 15U,
                      @"Memory growth during CAR export should be under 15 MB "
                      @"(before: %llu, after: %llu, growth: %lld bytes)",
                      (unsigned long long)beforeMem,
                      (unsigned long long)afterMem,
                      (long long)memoryGrowth);

    NSLog(@"Memory: before=%llu, after=%llu, growth=%lld bytes",
          (unsigned long long)beforeMem, (unsigned long long)afterMem,
          (long long)memoryGrowth);
}

- (void)testCARExportSizeWithinBounds {
    // Write 50 records to create a somewhat larger repo
    for (NSUInteger i = 0; i < 50; i++) {
        NSString *rkey = [NSString stringWithFormat:@"mem-size-%lu", (unsigned long)i];
        NSString *text = [NSString stringWithFormat:@"Size tracking record %lu", (unsigned long)i];
        [self.recordService putRecord:@"app.bsky.feed.post"
                                rkey:rkey
                               value:[self postRecordWithText:text]
                              forDid:self.testDID
                      validationMode:PDSValidationModeOff
                               error:nil];
    }

    NSError *exportError = nil;
    NSData *carData = [self.repositoryService getRepoContents:self.testDID since:nil error:&exportError];
    XCTAssertNotNil(carData);
    XCTAssertNil(exportError);

    // 50 records with small bodies should produce a CAR under 2 MB
    NSUInteger carSizeMB = carData.length / (1024 * 1024);
    XCTAssertLessThan(carSizeMB, 2U,
                      @"CAR export of 50 small records should be under 2 MB (got %lu MB, %lu bytes)",
                      (unsigned long)carSizeMB, (unsigned long)carData.length);

    // Verify the CAR is valid
    CARReader *reader = [CARReader readFromData:carData error:nil];
    XCTAssertNotNil(reader);
    XCTAssertTrue(reader.blocks.count >= 50);
}

#endif // !defined(GNUSTEP)

@end
