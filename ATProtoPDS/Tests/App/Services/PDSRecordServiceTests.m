#import <XCTest/XCTest.h>
#import "App/Services/PDSRecordService.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/Service/ServiceDatabases.h"

@interface PDSRecordServiceTests : XCTestCase
@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) PDSDatabasePool *pool;
@property (nonatomic, strong) PDSRecordService *service;
@property (nonatomic, copy) NSString *testDID;
@end

@implementation PDSRecordServiceTests

- (void)setUp {
    [super setUp];
    
    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    
    self.pool = [[PDSDatabasePool alloc] initWithDbDirectory:self.testDirectory maxSize:5];
    self.service = [[PDSRecordService alloc] initWithDatabasePool:self.pool];
    
    self.testDID = @"did:web:test.recordservice.example.com";
}

- (void)tearDown {
    [self.pool closeAll];
    self.pool = nil;
    self.service = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.testDirectory error:nil];
    [super tearDown];
}

- (void)testServiceInitialization {
    XCTAssertNotNil(self.service);
    XCTAssertEqual(self.service.databasePool, self.pool);
}

- (void)testGetRecordNotFound {
    NSError *error = nil;
    NSDictionary *record = [self.service getRecord:@"at://did:plc:nonexistent/app.bsky.feed.post/123"
                                           forDid:self.testDID
                                             error:&error];
    XCTAssertNil(record);
}

- (void)testPutRecord {
    NSDictionary *value = @{
        @"text": @"Hello, Record Service!",
        @"createdAt": [[NSDate date] description]
    };
    
    NSError *error = nil;
    BOOL success = [self.service putRecord:@"app.bsky.feed.post"
                                      rkey:@"test-rkey-1"
                                     value:value
                                    forDid:self.testDID
                                     error:&error];
    
    XCTAssertTrue(success);
    XCTAssertNil(error);
}

- (void)testPutRecordWithValidationOff {
    NSDictionary *value = @{
        @"text": @"No validation needed",
        @"unknownField": @"should be allowed"
    };
    
    NSError *error = nil;
    BOOL success = [self.service putRecord:@"app.bsky.feed.post"
                                      rkey:@"test-rkey-2"
                                     value:value
                                    forDid:self.testDID
                            validationMode:PDSValidationModeOff
                                     error:&error];
    
    XCTAssertTrue(success);
    XCTAssertNil(error);
}

- (void)testPutAndGetRecord {
    NSDictionary *value = @{
        @"text": @"Test record content",
        @"createdAt": [[NSDate date] description]
    };
    
    NSError *error = nil;
    BOOL putSuccess = [self.service putRecord:@"app.bsky.feed.post"
                                         rkey:@"test-rkey-3"
                                        value:value
                                       forDid:self.testDID
                                        error:&error];
    XCTAssertTrue(putSuccess);
    
    error = nil;
    NSDictionary *record = [self.service getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/test-rkey-3", self.testDID]
                                           forDid:self.testDID
                                             error:&error];
    
    XCTAssertNotNil(record);
    XCTAssertEqualObjects(record[@"collection"], @"app.bsky.feed.post");
    XCTAssertEqualObjects(record[@"rkey"], @"test-rkey-3");
}

- (void)testPutRecordDuplicate {
    NSDictionary *value = @{
        @"text": @"Duplicate record",
        @"createdAt": [[NSDate date] description]
    };
    
    NSError *error = nil;
    BOOL first = [self.service putRecord:@"app.bsky.feed.post"
                                    rkey:@"dup-test"
                                   value:value
                                  forDid:self.testDID
                                   error:&error];
    XCTAssertTrue(first);
    
    error = nil;
    BOOL second = [self.service putRecord:@"app.bsky.feed.post"
                                     rkey:@"dup-test"
                                    value:value
                                   forDid:self.testDID
                                    error:&error];
    XCTAssertTrue(second);
}

- (void)testDeleteRecord {
    NSDictionary *value = @{
        @"text": @"Record to delete",
        @"createdAt": [[NSDate date] description]
    };
    
    NSError *error = nil;
    [self.service putRecord:@"app.bsky.feed.post"
                       rkey:@"delete-test"
                      value:value
                     forDid:self.testDID
                      error:&error];
    
    error = nil;
    BOOL deleted = [self.service deleteRecord:@"app.bsky.feed.post"
                                        rkey:@"delete-test"
                                      forDid:self.testDID
                                         error:&error];
    XCTAssertTrue(deleted);
    
    NSDictionary *record = [self.service getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/delete-test", self.testDID]
                                           forDid:self.testDID
                                             error:&error];
    XCTAssertNil(record);
}

- (void)testDeleteNonexistentRecord {
    NSError *error = nil;
    BOOL result = [self.service deleteRecord:@"app.bsky.feed.post"
                                       rkey:@"nonexistent-rkey"
                                     forDid:self.testDID
                                        error:&error];
    XCTAssertFalse(result);
}

- (void)testListRecordsEmpty {
    NSError *error = nil;
    NSArray *records = [self.service listRecords:@"app.bsky.feed.post"
                                         forDid:self.testDID
                                          limit:10
                                         cursor:nil
                                          error:&error];
    
    XCTAssertNotNil(records);
    XCTAssertEqual(records.count, 0);
}

- (void)testListRecordsWithData {
    NSError *error = nil;
    for (int i = 0; i < 3; i++) {
        NSDictionary *value = @{
            @"text": [NSString stringWithFormat:@"Record %d", i],
            @"createdAt": [[NSDate date] description]
        };
        [self.service putRecord:@"app.bsky.feed.post"
                           rkey:[NSString stringWithFormat:@"list-test-%d", i]
                          value:value
                         forDid:self.testDID
                          error:&error];
    }
    
    error = nil;
    NSArray *records = [self.service listRecords:@"app.bsky.feed.post"
                                         forDid:self.testDID
                                          limit:10
                                         cursor:nil
                                          error:&error];
    
    XCTAssertNotNil(records);
    XCTAssertEqual(records.count, 3);
}

- (void)testListRecordsWithLimit {
    NSError *error = nil;
    for (int i = 0; i < 5; i++) {
        NSDictionary *value = @{
            @"text": [NSString stringWithFormat:@"Limited record %d", i],
            @"createdAt": [[NSDate date] description]
        };
        [self.service putRecord:@"app.bsky.feed.post"
                           rkey:[NSString stringWithFormat:@"limit-test-%d", i]
                          value:value
                         forDid:self.testDID
                          error:&error];
    }
    
    error = nil;
    NSArray *records = [self.service listRecords:@"app.bsky.feed.post"
                                         forDid:self.testDID
                                          limit:2
                                         cursor:nil
                                          error:&error];
    
    XCTAssertNotNil(records);
    XCTAssertEqual(records.count, 2);
}

- (void)testListRecordsDifferentCollections {
    NSError *error = nil;
    NSDictionary *feedValue = @{@"text": @"Feed post", @"createdAt": [[NSDate date] description]};
    NSDictionary *profileValue = @{
        @"displayName": @"Test User",
        @"description": @"Profile description"
    };
    
    [self.service putRecord:@"app.bsky.feed.post"
                       rkey:@"feed-1"
                      value:feedValue
                     forDid:self.testDID
                      error:&error];
    
    [self.service putRecord:@"app.bsky.actor.profile"
                       rkey:@"self"
                      value:profileValue
                     forDid:self.testDID
                      error:&error];
    
    NSArray *feedRecords = [self.service listRecords:@"app.bsky.feed.post"
                                             forDid:self.testDID
                                              limit:10
                                             cursor:nil
                                              error:&error];
    NSArray *profileRecords = [self.service listRecords:@"app.bsky.actor.profile"
                                                 forDid:self.testDID
                                                  limit:10
                                                 cursor:nil
                                                  error:&error];
    
    XCTAssertEqual(feedRecords.count, 1);
    XCTAssertEqual(profileRecords.count, 1);
}

- (void)testGetRepoStatsEmpty {
    NSError *error = nil;
    NSDictionary *stats = [self.service getRepoStatsForDid:self.testDID error:&error];
    
    XCTAssertNotNil(stats);
    XCTAssertEqualObjects(stats[@"did"], self.testDID);
    XCTAssertEqualObjects(stats[@"recordCount"], @(0));
}

- (void)testGetRepoStatsWithRecords {
    NSError *error = nil;
    for (int i = 0; i < 3; i++) {
        NSDictionary *value = @{@"text": [NSString stringWithFormat:@"Stat test %d", i]};
        [self.service putRecord:@"app.bsky.feed.post"
                           rkey:[NSString stringWithFormat:@"stat-%d", i]
                          value:value
                         forDid:self.testDID
                          error:&error];
    }
    
    error = nil;
    NSDictionary *stats = [self.service getRepoStatsForDid:self.testDID error:&error];
    
    XCTAssertNotNil(stats);
    XCTAssertEqualObjects(stats[@"recordCount"], @(3));
}

- (void)testGetRepoStatsNonexistentDID {
    NSError *error = nil;
    NSDictionary *stats = [self.service getRepoStatsForDid:@"did:plc:nonexistent" error:&error];
    XCTAssertNil(stats);
}

- (void)testPutRecordInvalidCollectionNSID {
    NSDictionary *value = @{@"text": @"test"};
    
    NSError *error = nil;
    BOOL success = [self.service putRecord:@"invalid.collection.id"
                                      rkey:@"test"
                                     value:value
                                    forDid:self.testDID
                                     error:&error];
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
}

- (void)testPutRecordWithEmptyRkey {
    NSDictionary *value = @{@"text": @"test"};
    
    NSError *error = nil;
    BOOL success = [self.service putRecord:@"app.bsky.feed.post"
                                      rkey:@""
                                     value:value
                                    forDid:self.testDID
                                     error:&error];
    XCTAssertFalse(success);
}

- (void)testRecordDIDIsolation {
    NSString *did1 = @"did:web:user1.example.com";
    NSString *did2 = @"did:web:user2.example.com";
    
    NSError *error = nil;
    NSDictionary *value = @{@"text": @"Shared content"};
    
    [self.service putRecord:@"app.bsky.feed.post"
                       rkey:@"shared-1"
                      value:value
                     forDid:did1
                      error:&error];
    
    [self.service putRecord:@"app.bsky.feed.post"
                       rkey:@"shared-1"
                      value:value
                     forDid:did2
                      error:&error];
    
    NSArray *did1Records = [self.service listRecords:@"app.bsky.feed.post"
                                             forDid:did1
                                              limit:10
                                             cursor:nil
                                              error:nil];
    NSArray *did2Records = [self.service listRecords:@"app.bsky.feed.post"
                                             forDid:did2
                                              limit:10
                                             cursor:nil
                                              error:nil];
    
    XCTAssertEqual(did1Records.count, 1);
    XCTAssertEqual(did2Records.count, 1);
}

@end
