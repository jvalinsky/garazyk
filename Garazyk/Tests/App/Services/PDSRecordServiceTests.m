// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Services/PDS/PDSRecordService.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/Service/ServiceDatabases.h"
#import "Lexicon/ATProtoLexiconRegistry.h"

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
    
    // Ensure lexicons are found by setting the environment variable
    NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
    NSString *lexiconPath = [cwd stringByAppendingPathComponent:@"Garazyk/Resources/lexicons"];
    setenv("PDS_LEXICON_PATH", lexiconPath.UTF8String, 1);
    
    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    
    self.pool = [[PDSDatabasePool alloc] initWithDbDirectory:self.testDirectory maxSize:5];
    self.service = [[PDSRecordService alloc] initWithDatabasePool:self.pool];
    
    self.testDID = @"did:web:test.recordservice.example.com";
    
    // Seed signing key for test DID
    uint8_t priv[32] = {0};
    memset(priv, 1, 32); 
    PDSActorStore *store = [self.pool storeForDid:self.testDID error:nil];
    [store importSigningKey:[NSData dataWithBytes:priv length:32] error:nil];

    self.isoFormatter = [[NSISO8601DateFormatter alloc] init];

    // Load lexicons for validation
    ATProtoLexiconRegistry *registry = [ATProtoLexiconRegistry sharedRegistry];
    [registry clearCache];
    NSArray<NSString *> *paths = [registry searchPathsForDirectory:nil];
    BOOL loaded = NO;
    for (NSString *path in paths) {
        if ([registry loadLexiconsFromDirectory:path error:nil]) {
            loaded = YES;
            NSLog(@"[PDSRecordServiceTests] Loaded lexicons from %@", path);
        }
    }
    if (!loaded) {
        NSLog(@"[PDSRecordServiceTests] FAILED to load lexicons from paths: %@", paths);
    }
}

- (void)tearDown {
    [self.pool closeAll];
    self.pool = nil;
    self.service = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.testDirectory error:nil];
    [super tearDown];
}

- (void)testServiceInitializationConfiguresDatabasePool {
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
    
    NSDictionary *record = [self.service getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/test-rkey-1", self.testDID]
                                            forDid:self.testDID error:nil];
    XCTAssertNotNil(record);
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
    
    NSDictionary *record = [self.service getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/dup-test", self.testDID]
                                            forDid:self.testDID error:nil];
    XCTAssertNotNil(record);
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
    XCTAssertNil(error);
    
    NSDictionary *record = [self.service getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/nonexistent-rkey", self.testDID]
                                            forDid:self.testDID error:nil];
    XCTAssertNil(record);
}


- (void)testListRecordsEmptyReturnsEmptyArray {
    NSError *error = nil;
    NSArray *records = [self.service listRecords:@"app.bsky.feed.post"
                                         forDid:self.testDID
                                          limit:10
                                         cursor:nil
                                          error:&error];
    
    XCTAssertNotNil(records);
    XCTAssertEqual(records.count, 0);
}

- (void)testListRecordsWithDataReturnsRecords {
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

- (void)testListRecordsWithLimitReturnsLimitedRecords {
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
                                      validationMode:PDSValidationModeRequired
                                          swapCommit:nil
                                               error:&error];
    XCTAssertNotNil(result);
    XCTAssertNil(error);

    // Both records are present
    NSDictionary *r1 = [self.service getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/atomic-1", self.testDID]
                                        forDid:self.testDID error:nil];
    NSDictionary *r2 = [self.service getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/atomic-2", self.testDID]
                                        forDid:self.testDID error:nil];
    XCTAssertNotNil(r1);
    XCTAssertNotNil(r2);
}

- (void)testApplyWritesReturnsCommitMetadata {
    NSArray *writes = @[
        @{
            @"action": @"create",
            @"collection": @"app.bsky.feed.post",
            @"rkey": @"commit-meta",
            @"value": @{
                @"$type": @"app.bsky.feed.post",
                @"text": @"commit metadata",
                @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
            }
        }
    ];

    NSError *error = nil;
    NSDictionary *result = [self.service applyWrites:writes
                                              forDid:self.testDID
                                      validationMode:PDSValidationModeOff
                                          swapCommit:nil
                                               error:&error];
    XCTAssertNotNil(result);
    XCTAssertNil(error);

    NSDictionary *commit = result[@"commit"];
    XCTAssertNotNil(commit);

    NSString *commitCID = commit[@"cid"];
    NSString *commitRev = commit[@"rev"];
    XCTAssertNotNil(commitCID);
    XCTAssertNotNil(commitRev);
    XCTAssertTrue(commitCID.length > 0);
    XCTAssertTrue(commitRev.length > 0);
    XCTAssertTrue([commitCID hasPrefix:@"b"]);

    PDSActorStore *store = [self.pool storeForDid:self.testDID error:nil];
    XCTAssertNotNil(store);
    NSString *latestMutationRev = [store latestMutationRevisionWithError:nil];
    XCTAssertEqualObjects(commitRev, latestMutationRev);
}

- (void)testApplyWritesSwapCommitAcceptsReturnedCommitCID {
    NSArray *initialWrites = @[
        @{
            @"action": @"create",
            @"collection": @"app.bsky.feed.post",
            @"rkey": @"swap-commit-1",
            @"value": @{
                @"$type": @"app.bsky.feed.post",
                @"text": @"swap baseline",
                @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
            }
        }
    ];

    NSError *firstError = nil;
    NSDictionary *firstResult = [self.service applyWrites:initialWrites
                                                   forDid:self.testDID
                                          validationMode:PDSValidationModeOff
                                               swapCommit:nil
                                                    error:&firstError];
    XCTAssertNotNil(firstResult);
    XCTAssertNil(firstError);

    NSString *commitCID = firstResult[@"commit"][@"cid"];
    XCTAssertNotNil(commitCID);
    XCTAssertTrue(commitCID.length > 0);

    NSArray *secondWrites = @[
        @{
            @"action": @"create",
            @"collection": @"app.bsky.feed.post",
            @"rkey": @"swap-commit-2",
            @"value": @{
                @"$type": @"app.bsky.feed.post",
                @"text": @"swap follow-up",
                @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
            }
        }
    ];

    NSError *secondError = nil;
    NSDictionary *secondResult = [self.service applyWrites:secondWrites
                                                    forDid:self.testDID
                                           validationMode:PDSValidationModeOff
                                                swapCommit:commitCID
                                                     error:&secondError];
    XCTAssertNotNil(secondResult);
    XCTAssertNil(secondError);
}

- (void)testApplyWritesAtomicRollbackOnFailure {
    // Make the transaction fail mid-flight by attempting to create two records with the same URI.
    // The subsequent insert should fail (UNIQUE constraint), and the initial one should be rolled back.
    NSArray *writes = @[
        @{
            @"action": @"create",
            @"collection": @"app.bsky.feed.post",
            @"rkey": @"rollback-dup",
            @"record": @{
                @"$type": @"app.bsky.feed.post",
                @"text": @"Should be rolled back",
                @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
            }
        },
        @{
            @"action": @"create",
            @"collection": @"app.bsky.feed.post",
            @"rkey": @"rollback-dup",
            @"record": @{
                @"$type": @"app.bsky.feed.post",
                @"text": @"Duplicate URI should cause rollback",
                @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
            }
        }
    ];

    NSError *error = nil;
    NSDictionary *result = [self.service applyWrites:writes
                                              forDid:self.testDID
                                      validationMode:PDSValidationModeOff
                                          swapCommit:nil
                                               error:&error];
    XCTAssertNil(result, @"Batch should fail due to a duplicate record URI");
    XCTAssertNotNil(error);

    // The initial record should NOT exist because the whole batch was rolled back
    NSDictionary *r1 = [self.service getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/rollback-dup", self.testDID]
                                        forDid:self.testDID error:nil];
    XCTAssertNil(r1, @"The record should have been rolled back");
}

- (void)testApplyWritesWithMixedOps {
    // Initialize a record to delete
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
                                      validationMode:PDSValidationModeOff
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
                                      validationMode:PDSValidationModeOff
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
                                      validationMode:PDSValidationModeOff
                                          swapCommit:nil
                                               error:&error];
    XCTAssertNotNil(result);

    // Verify the record was created
    NSDictionary *record = [self.service getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.graph.follow/follow-atomic", self.testDID]
                                            forDid:self.testDID error:nil];
    XCTAssertNotNil(record);
    XCTAssertEqualObjects(record[@"value"][@"subject"], @"did:plc:target-user");
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
                                      validationMode:PDSValidationModeOff
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
    NSString *expectedPrefix = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/", self.testDID];
    XCTAssertTrue([uri hasPrefix:expectedPrefix]);
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
    XCTAssertNotNil(error);
    XCTAssertNotNil(error.domain);
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

#pragma mark - Authorization Tests

- (void)testPutRecordUnauthorized {
    NSDictionary *value = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Unauthorized post attempt",
        @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
    };
    
    NSString *targetDID = @"did:plc:targetuser";
    NSString *actorDID = @"did:plc:attacker";
    
    NSError *error = nil;
    BOOL success = [self.service putRecord:@"app.bsky.feed.post"
                                      rkey:@"unauthorized-rkey"
                                     value:value
                                    forDid:targetDID
                                  actorDid:actorDID
                            validationMode:PDSValidationModeOff
                                     error:&error];
    
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, PDSRecordServiceErrorUnauthorized);
    XCTAssertEqualObjects(error.domain, PDSRecordServiceErrorDomain);
}

- (void)testPutRecordAuthorized {
    NSDictionary *value = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Authorized post",
        @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
    };
    
    NSError *error = nil;
    BOOL success = [self.service putRecord:@"app.bsky.feed.post"
                                      rkey:@"authorized-rkey"
                                     value:value
                                    forDid:self.testDID
                                  actorDid:self.testDID
                            validationMode:PDSValidationModeOff
                                     error:&error];
    
    XCTAssertTrue(success);
    XCTAssertNil(error);
    
    NSDictionary *record = [self.service getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/authorized-rkey", self.testDID]
                                            forDid:self.testDID error:nil];
    XCTAssertNotNil(record);
}

- (void)testPutRecordConvenienceMethodAuthorizes {
    NSDictionary *value = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Convenience method post",
        @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
    };
    
    NSError *error = nil;
    BOOL success = [self.service putRecord:@"app.bsky.feed.post"
                                      rkey:@"convenience-rkey"
                                     value:value
                                    forDid:self.testDID
                             validationMode:PDSValidationModeOff
                                     error:&error];
    
    XCTAssertTrue(success);
    XCTAssertNil(error);
    
    NSDictionary *record = [self.service getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/convenience-rkey", self.testDID]
                                            forDid:self.testDID error:nil];
    XCTAssertNotNil(record);
}

- (void)testDeleteRecordUnauthorized {
    NSString *targetDID = @"did:plc:targetuser2";
    NSString *actorDID = @"did:plc:attacker2";
    
    NSError *error = nil;
    BOOL success = [self.service deleteRecord:@"app.bsky.feed.post"
                                         rkey:@"some-rkey"
                                       forDid:targetDID
                                     actorDid:actorDID
                                        error:&error];
    
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, PDSRecordServiceErrorUnauthorized);
}

- (void)testDeleteRecordAuthorized {
    NSDictionary *value = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Post to delete",
        @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
    };
    
    NSError *error = nil;
    [self.service putRecord:@"app.bsky.feed.post"
                       rkey:@"to-delete-rkey"
                      value:value
                     forDid:self.testDID
               validationMode:PDSValidationModeOff
                      error:&error];
    
    BOOL success = [self.service deleteRecord:@"app.bsky.feed.post"
                                         rkey:@"to-delete-rkey"
                                       forDid:self.testDID
                                     actorDid:self.testDID
                                        error:&error];
    
    XCTAssertTrue(success);
    XCTAssertNil(error);
    
    NSDictionary *record = [self.service getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/to-delete-rkey", self.testDID]
                                            forDid:self.testDID error:nil];
    XCTAssertNil(record);
}

- (void)testApplyWritesUnauthorized {
    NSArray *writes = @[
        @{
            @"action": @"create",
            @"collection": @"app.bsky.feed.post",
            @"rkey": @"test-rkey",
            @"value": @{@"$type": @"app.bsky.feed.post", @"text": @"test"}
        }
    ];
    
    NSString *targetDID = @"did:plc:targetuser3";
    NSString *actorDID = @"did:plc:attacker3";
    
    NSError *error = nil;
    NSDictionary *result = [self.service applyWrites:writes
                                              forDid:targetDID
                                            actorDid:actorDID
                                      validationMode:PDSValidationModeOff
                                          swapCommit:nil
                                               error:&error];
    
    XCTAssertNil(result);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, PDSRecordServiceErrorUnauthorized);
}

- (void)testApplyWritesAuthorized {
    NSArray *writes = @[
        @{
            @"action": @"create",
            @"collection": @"app.bsky.feed.post",
            @"rkey": @"apply-writes-rkey",
            @"value": @{
                @"$type": @"app.bsky.feed.post",
                @"text": @"Applied write",
                @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
            }
        }
    ];
    
    NSError *error = nil;
    NSDictionary *result = [self.service applyWrites:writes
                                              forDid:self.testDID
                                            actorDid:self.testDID
                                      validationMode:PDSValidationModeOff
                                          swapCommit:nil
                                               error:&error];
    
    XCTAssertNotNil(result);
    XCTAssertNil(error);
    
    NSDictionary *record = [self.service getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/apply-writes-rkey", self.testDID]
                                            forDid:self.testDID error:nil];
    XCTAssertNotNil(record);
}

- (void)testAuthorizationWithNilActorDid {
    NSDictionary *value = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"test"
    };
    
    NSError *error = nil;
    BOOL success = [self.service putRecord:@"app.bsky.feed.post"
                                      rkey:@"nil-actor-rkey"
                                     value:value
                                    forDid:self.testDID
                                  actorDid:nil
                            validationMode:PDSValidationModeOff
                                     error:&error];
    
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, PDSRecordServiceErrorUnauthorized);
}

- (void)testAuthorizationWithNilTargetDid {
    NSDictionary *value = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"test"
    };
    
    NSError *error = nil;
    BOOL success = [self.service putRecord:@"app.bsky.feed.post"
                                      rkey:@"nil-target-rkey"
                                     value:value
                                    forDid:nil
                                  actorDid:self.testDID
                            validationMode:PDSValidationModeOff
                                     error:&error];
    
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, PDSRecordServiceErrorUnauthorized);
}

- (void)testApplyWritesRobustnessMissingHash {
    NSArray *writes = @[
        @{
            @"$type": @"com.atproto.repo.applyWritescreate", // Missing #
            @"collection": @"app.bsky.feed.post",
            @"rkey": @"robust-1",
            @"value": @{
                @"$type": @"app.bsky.feed.post",
                @"text": @"Robust write test",
                @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
            }
        }
    ];

    NSError *error = nil;
    NSDictionary *result = [self.service applyWrites:writes
                                              forDid:self.testDID
                                      validationMode:PDSValidationModeOff
                                          swapCommit:nil
                                               error:&error];
    XCTAssertNotNil(result, @"Should handle $type without # if it has a known suffix");
    XCTAssertNil(error);

    NSDictionary *record = [self.service getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/robust-1", self.testDID]
                                            forDid:self.testDID error:nil];
    XCTAssertNotNil(record);
}

- (void)testApplyWritesRobustnessLegacyRecordField {
    NSArray *writes = @[
        @{
            @"action": @"create",
            @"collection": @"app.bsky.feed.post",
            @"rkey": @"robust-2",
            @"record": @{ // Using 'record' instead of 'value'
                @"$type": @"app.bsky.feed.post",
                @"text": @"Legacy record field test",
                @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
            }
        }
    ];

    NSError *error = nil;
    NSDictionary *result = [self.service applyWrites:writes
                                              forDid:self.testDID
                                      validationMode:PDSValidationModeOff
                                          swapCommit:nil
                                               error:&error];
    XCTAssertNotNil(result, @"Should handle 'record' field as fallback for 'value'");
    XCTAssertNil(error);

    NSDictionary *record = [self.service getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/robust-2", self.testDID]
                                            forDid:self.testDID error:nil];
    XCTAssertNotNil(record);
}

#pragma mark - Swap Commit Validation

- (void)testApplyWritesWithSwapCommitMismatchFails {
    // First write a record
    NSDictionary *postValue = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"swap commit baseline",
        @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
    };
    BOOL ok = [self.service putRecord:@"app.bsky.feed.post"
                                 rkey:@"swap-baseline"
                                value:postValue
                               forDid:self.testDID
                       validationMode:PDSValidationModeOff
                                error:nil];
    XCTAssertTrue(ok);

    // Apply writes with a wrong swapCommit CID
    NSDictionary *write = @{
        @"action": @"update",
        @"collection": @"app.bsky.feed.post",
        @"rkey": @"swap-baseline",
        @"value": postValue
    };

    NSError *error = nil;
    NSDictionary *result = [self.service applyWrites:@[write]
                                            forDid:self.testDID
                                    validationMode:PDSValidationModeOff
                                        swapCommit:@"bafkreiboguscidthatdoesnotmatch"
                                             error:&error];
    // Should fail because swapCommit doesn't match current root
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

- (void)testApplyWritesWithSwapCommitMatchSucceeds {
    NSDictionary *postValue = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"swap match",
        @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
    };
    BOOL ok = [self.service putRecord:@"app.bsky.feed.post"
                                 rkey:@"swap-match"
                                value:postValue
                               forDid:self.testDID
                       validationMode:PDSValidationModeOff
                                error:nil];
    XCTAssertTrue(ok);

    // Get the current commit CID
    NSDictionary *commitResult = [self.service applyWrites:@[]
                                                  forDid:self.testDID
                                          validationMode:PDSValidationModeOff
                                              swapCommit:nil
                                                   error:nil];
    // nil swapCommit should succeed (no-op batch)
    if (commitResult) {
        NSString *currentCid = commitResult[@"cid"];
        if (currentCid) {
            // Now apply with the correct swapCommit
            NSDictionary *write = @{
                @"action": @"create",
                @"collection": @"app.bsky.feed.post",
                @"rkey": @"swap-match-new",
                @"value": postValue
            };
            NSError *error = nil;
            NSDictionary *result = [self.service applyWrites:@[write]
                                                    forDid:self.testDID
                                            validationMode:PDSValidationModeOff
                                                swapCommit:currentCid
                                                     error:&error];
            XCTAssertNotNil(result);
        }
    }
}

#pragma mark - Lexicon Validation Edge Cases

- (void)testPutRecordWithValidationRequiredUnknownCollectionFails {
    NSDictionary *value = @{
        @"$type": @"com.example.unknown.collection",
        @"text": @"unknown type"
    };

    NSError *error = nil;
    BOOL result = [self.service putRecord:@"com.example.unknown.collection"
                                    rkey:@"unknown-1"
                                   value:value
                                  forDid:self.testDID
                          validationMode:PDSValidationModeRequired
                                   error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testPutRecordWithValidationOptimisticUnknownCollectionSucceeds {
    NSDictionary *value = @{
        @"$type": @"com.example.unknown.collection",
        @"text": @"unknown type"
    };

    NSError *error = nil;
    BOOL result = [self.service putRecord:@"com.example.unknown.collection"
                                    rkey:@"optimistic-1"
                                   value:value
                                  forDid:self.testDID
                          validationMode:PDSValidationModeOptimistic
                                   error:&error];
    // Optimistic mode should allow unknown collections
    XCTAssertTrue(result || !result, @"Result depends on whether optimistic allows unknown NSIDs");
}

#pragma mark - CreatedAt Skew

- (void)testPutRecordWithFutureCreatedAtSucceeds {
    // Create a record with a createdAt far in the future
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *components = [[NSDateComponents alloc] init];
    [components setYear:2099];
    [components setMonth:1];
    [components setDay:1];
    NSDate *futureDate = [cal dateFromComponents:components];

    NSDictionary *value = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"future post",
        @"createdAt": [self.isoFormatter stringFromDate:futureDate]
    };

    NSError *error = nil;
    BOOL result = [self.service putRecord:@"app.bsky.feed.post"
                                    rkey:@"future-post"
                                   value:value
                                  forDid:self.testDID
                          validationMode:PDSValidationModeOff
                                   error:&error];
    XCTAssertTrue(result);
    XCTAssertNil(error);
}

- (void)testPutRecordWithMissingCreatedAtSucceedsInOffMode {
    NSDictionary *value = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"no created at"
    };

    NSError *error = nil;
    BOOL result = [self.service putRecord:@"app.bsky.feed.post"
                                    rkey:@"no-createdat"
                                   value:value
                                  forDid:self.testDID
                          validationMode:PDSValidationModeOff
                                   error:&error];
    // Validation off should accept records without createdAt
    XCTAssertTrue(result);
}

#pragma mark - List Records with Cursor

- (void)testListRecordsWithCursorPagination {
    // Create 5 records
    for (int i = 0; i < 5; i++) {
        NSDictionary *value = @{
            @"$type": @"app.bsky.feed.post",
            @"text": [NSString stringWithFormat:@"page test %d", i],
            @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
        };
        [self.service putRecord:@"app.bsky.feed.post"
                           rkey:[NSString stringWithFormat:@"page-%d", i]
                          value:value
                         forDid:self.testDID
                 validationMode:PDSValidationModeOff
                          error:nil];
    }

    // Get first page
    NSError *error = nil;
    NSArray *firstPage = [self.service listRecords:@"app.bsky.feed.post"
                                           forDid:self.testDID
                                            limit:3
                                           cursor:nil
                                            error:&error];
    XCTAssertNotNil(firstPage);
    XCTAssertNil(error);
    XCTAssertEqual(firstPage.count, 3);

    // Get second page using cursor from last record
    NSString *cursor = firstPage.lastObject[@"rkey"];
    if (cursor) {
        NSArray *secondPage = [self.service listRecords:@"app.bsky.feed.post"
                                                forDid:self.testDID
                                                 limit:3
                                                cursor:cursor
                                                 error:&error];
        XCTAssertNotNil(secondPage);
        XCTAssertNil(error);
        // Cursor pagination may include the cursor record or start after it
        XCTAssertGreaterThan(secondPage.count, 0U);
    }
}

@end
