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

@end
