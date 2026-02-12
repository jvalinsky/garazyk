#import <XCTest/XCTest.h>
#import "App/Services/PDSRecordService.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/Service/ServiceDatabases.h"

@interface PDSRecordServiceTests : XCTestCase
@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) PDSDatabasePool *pool;
@property (nonatomic, strong) PDSRecordService *service;
@property (nonatomic, copy) NSString *testDID;
@property (nonatomic, strong) NSISO8601DateFormatter *isoFormatter;
@end

@implementation PDSRecordServiceTests

- (void)setUp {
    [super setUp];
    
    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    
    self.pool = [[PDSDatabasePool alloc] initWithDbDirectory:self.testDirectory maxSize:5];
    self.service = [[PDSRecordService alloc] initWithDatabasePool:self.pool];
    
    self.testDID = @"did:web:test.recordservice.example.com";
    
    self.isoFormatter = [[NSISO8601DateFormatter alloc] init];
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
        @"$type": @"app.bsky.feed.post",
        @"text": @"Hello, Record Service!",
        @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
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
        @"$type": @"app.bsky.feed.post",
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
        @"$type": @"app.bsky.feed.post",
        @"text": @"Test record content",
        @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
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
        @"$type": @"app.bsky.feed.post",
        @"text": @"Duplicate record",
        @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
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
        @"$type": @"app.bsky.feed.post",
        @"text": @"Record to delete",
        @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
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
    XCTAssertTrue(result);
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
            @"$type": @"app.bsky.feed.post",
            @"text": [NSString stringWithFormat:@"Record %d", i],
            @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
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
            @"$type": @"app.bsky.feed.post",
            @"text": [NSString stringWithFormat:@"Limited record %d", i],
            @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
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
    NSDate *now = [NSDate date];
    NSDictionary *feedValue = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Feed post",
        @"createdAt": [self.isoFormatter stringFromDate:now]
    };
    NSDictionary *profileValue = @{
        @"$type": @"app.bsky.actor.profile",
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
        NSDictionary *value = @{
            @"$type": @"app.bsky.feed.post",
            @"text": [NSString stringWithFormat:@"Stat test %d", i],
            @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
        };
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
    XCTAssertNotNil(stats);
    XCTAssertEqualObjects(stats[@"did"], @"did:plc:nonexistent");
    XCTAssertEqualObjects(stats[@"recordCount"], @(0));
}

- (void)testPutRecordInvalidCollectionNSID {
    NSDictionary *value = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"test"
    };

    NSError *error = nil;
    BOOL success = [self.service putRecord:@"invalid.collection.id"
                                      rkey:@"test"
                                     value:value
                                    forDid:self.testDID
                                     error:&error];
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
}

#pragma mark - applyWrites Atomicity Tests

- (void)testApplyWritesAtomicSuccess {
    NSArray *writes = @[
        @{
            @"action": @"create",
            @"collection": @"app.bsky.feed.post",
            @"rkey": @"atomic-1",
            @"value": @{
                @"$type": @"app.bsky.feed.post",
                @"text": @"First atomic write",
                @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
            }
        },
        @{
            @"action": @"create",
            @"collection": @"app.bsky.feed.post",
            @"rkey": @"atomic-2",
            @"value": @{
                @"$type": @"app.bsky.feed.post",
                @"text": @"Second atomic write",
                @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
            }
        }
    ];

    NSError *error = nil;
    NSDictionary *result = [self.service applyWrites:writes
                                              forDid:self.testDID
                                            validate:NO
                                          swapCommit:nil
                                               error:&error];
    XCTAssertNotNil(result);
    XCTAssertNil(error);

    // Both records should exist
    NSDictionary *r1 = [self.service getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/atomic-1", self.testDID]
                                        forDid:self.testDID error:nil];
    NSDictionary *r2 = [self.service getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/atomic-2", self.testDID]
                                        forDid:self.testDID error:nil];
    XCTAssertNotNil(r1);
    XCTAssertNotNil(r2);
}

- (void)testApplyWritesAtomicRollbackOnFailure {
    // Write #1 is valid, write #2 has an invalid collection NSID, so the whole batch fails
    // before the transaction even starts (pre-validation catches it)
    NSArray *writes = @[
        @{
            @"action": @"create",
            @"collection": @"app.bsky.feed.post",
            @"rkey": @"rollback-1",
            @"record": @{
                @"$type": @"app.bsky.feed.post",
                @"text": @"Should be rolled back",
                @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
            }
        },
        @{
            @"action": @"create",
            @"collection": @"invalid.collection.id",
            @"rkey": @"rollback-2",
            @"record": @{
                @"$type": @"invalid",
                @"text": @"This will fail validation"
            }
        },
        @{
            @"action": @"create",
            @"collection": @"app.bsky.feed.post",
            @"rkey": @"rollback-3",
            @"record": @{
                @"$type": @"app.bsky.feed.post",
                @"text": @"Should never be reached",
                @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
            }
        }
    ];

    NSError *error = nil;
    NSDictionary *result = [self.service applyWrites:writes
                                              forDid:self.testDID
                                            validate:NO
                                          swapCommit:nil
                                               error:&error];
    XCTAssertNil(result, @"Batch should fail due to invalid collection NSID");
    XCTAssertNotNil(error);

    // Record #1 should NOT exist because the whole batch was rolled back
    NSDictionary *r1 = [self.service getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/rollback-1", self.testDID]
                                        forDid:self.testDID error:nil];
    XCTAssertNil(r1, @"Record #1 should have been rolled back");
}

- (void)testApplyWritesWithMixedOps {
    // First create a record to delete
    [self.service putRecord:@"app.bsky.feed.post"
                       rkey:@"to-delete"
                      value:@{
                          @"$type": @"app.bsky.feed.post",
                          @"text": @"Will be deleted",
                          @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
                      }
                     forDid:self.testDID
                      error:nil];

    NSArray *writes = @[
        @{
            @"action": @"create",
            @"collection": @"app.bsky.feed.post",
            @"rkey": @"mixed-create",
            @"value": @{
                @"$type": @"app.bsky.feed.post",
                @"text": @"New record",
                @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
            }
        },
        @{
            @"action": @"delete",
            @"collection": @"app.bsky.feed.post",
            @"rkey": @"to-delete"
        }
    ];

    NSError *error = nil;
    NSDictionary *result = [self.service applyWrites:writes
                                              forDid:self.testDID
                                            validate:NO
                                          swapCommit:nil
                                               error:&error];
    XCTAssertNotNil(result);

    // New record exists
    NSDictionary *created = [self.service getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/mixed-create", self.testDID]
                                             forDid:self.testDID error:nil];
    XCTAssertNotNil(created);

    // Deleted record is gone
    NSDictionary *deleted = [self.service getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/to-delete", self.testDID]
                                             forDid:self.testDID error:nil];
    XCTAssertNil(deleted);
}

- (void)testApplyWritesEmptyBatch {
    NSError *error = nil;
    NSDictionary *result = [self.service applyWrites:@[]
                                              forDid:self.testDID
                                            validate:NO
                                          swapCommit:nil
                                               error:&error];
    XCTAssertNotNil(result);
    XCTAssertNil(error);
}

- (void)testApplyWritesSubjectDid {
    NSArray *writes = @[
        @{
            @"action": @"create",
            @"collection": @"app.bsky.graph.follow",
            @"rkey": @"follow-atomic",
            @"value": @{
                @"$type": @"app.bsky.graph.follow",
                @"subject": @"did:plc:target-user",
                @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
            }
        }
    ];

    NSError *error = nil;
    NSDictionary *result = [self.service applyWrites:writes
                                              forDid:self.testDID
                                            validate:NO
                                          swapCommit:nil
                                               error:&error];
    XCTAssertNotNil(result);

    // Verify the record was created
    NSDictionary *record = [self.service getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.graph.follow/follow-atomic", self.testDID]
                                            forDid:self.testDID error:nil];
    XCTAssertNotNil(record);
}

- (void)testApplyWritesCreateWithoutRkeyGeneratesKeyAndResult {
    NSArray *writes = @[
        @{
            @"action": @"create",
            @"collection": @"app.bsky.feed.post",
            @"value": @{
                @"$type": @"app.bsky.feed.post",
                @"text": @"No rkey",
                @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
            }
        }
    ];

    NSError *error = nil;
    NSDictionary *result = [self.service applyWrites:writes
                                              forDid:self.testDID
                                            validate:NO
                                          swapCommit:nil
                                               error:&error];
    XCTAssertNotNil(result);
    XCTAssertNil(error);

    NSArray *results = result[@"results"];
    XCTAssertEqual(results.count, 1);

    NSDictionary *opResult = results.firstObject;
    NSString *uri = opResult[@"uri"];
    NSString *cid = opResult[@"cid"];

    XCTAssertNotNil(uri);
    XCTAssertNotNil(cid);
    XCTAssertTrue([uri hasPrefix:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/", self.testDID]]);
    XCTAssertTrue(cid.length > 0);
}

- (void)testPutRecordWithEmptyRkey {
    NSDictionary *value = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"test"
    };
    
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
    NSDate *now = [NSDate date];
    NSDictionary *value = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Shared content",
        @"createdAt": [self.isoFormatter stringFromDate:now]
    };
    
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
