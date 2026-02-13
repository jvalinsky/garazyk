#import <XCTest/XCTest.h>
#import "App/Services/PDSRecordService.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"

@interface PDSRecordTombstoneTests : XCTestCase
@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) PDSDatabasePool *pool;
@property (nonatomic, strong) PDSRecordService *service;
@property (nonatomic, copy) NSString *testDID;
@property (nonatomic, strong) NSISO8601DateFormatter *isoFormatter;
@end

@implementation PDSRecordTombstoneTests

- (void)setUp {
    [super setUp];

    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    self.pool = [[PDSDatabasePool alloc] initWithDbDirectory:self.testDirectory maxSize:5];
    self.service = [[PDSRecordService alloc] initWithDatabasePool:self.pool];
    self.testDID = @"did:web:test.recordtombstones.example.com";
    self.isoFormatter = [[NSISO8601DateFormatter alloc] init];
}

- (void)tearDown {
    [self.pool closeAll];
    self.pool = nil;
    self.service = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.testDirectory error:nil];
    [super tearDown];
}

- (void)testDeleteRecordWritesTombstone {
    NSDictionary *value = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Record to tombstone",
        @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
    };

    NSError *error = nil;
    BOOL putOK = [self.service putRecord:@"app.bsky.feed.post"
                                    rkey:@"tombstone-test"
                                   value:value
                                  forDid:self.testDID
                          validationMode:PDSValidationModeOff
                                   error:&error];
    XCTAssertTrue(putOK);
    XCTAssertNil(error);

    BOOL deleteOK = [self.service deleteRecord:@"app.bsky.feed.post"
                                          rkey:@"tombstone-test"
                                        forDid:self.testDID
                                         error:&error];
    XCTAssertTrue(deleteOK);
    XCTAssertNil(error);

    PDSActorStore *store = [self.pool storeForDid:self.testDID error:&error];
    XCTAssertNotNil(store);
    XCTAssertNil(error);

    NSArray<NSDictionary<NSString *, id> *> *tombstones = [store listRecordTombstonesSinceRev:nil
                                                                                         limit:10
                                                                                         error:&error];
    XCTAssertNotNil(tombstones);
    XCTAssertNil(error);
    XCTAssertEqual(tombstones.count, 1U);
    XCTAssertEqualObjects(tombstones.firstObject[@"collection"], @"app.bsky.feed.post");
    XCTAssertEqualObjects(tombstones.firstObject[@"rkey"], @"tombstone-test");
    XCTAssertTrue([tombstones.firstObject[@"rev"] length] > 0);
}

- (void)testDeleteNonexistentRecordDoesNotWriteTombstone {
    NSError *error = nil;
    BOOL deleteOK = [self.service deleteRecord:@"app.bsky.feed.post"
                                          rkey:@"missing-tombstone-test"
                                        forDid:self.testDID
                                         error:&error];
    XCTAssertTrue(deleteOK);
    XCTAssertNil(error);

    PDSActorStore *store = [self.pool storeForDid:self.testDID error:&error];
    XCTAssertNotNil(store);
    XCTAssertNil(error);

    NSArray<NSDictionary<NSString *, id> *> *tombstones = [store listRecordTombstonesSinceRev:nil
                                                                                         limit:10
                                                                                         error:&error];
    XCTAssertNotNil(tombstones);
    XCTAssertNil(error);
    XCTAssertEqual(tombstones.count, 0U);
}

- (void)testApplyWritesDeleteWritesSingleBatchRevTombstones {
    NSDictionary *firstValue = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Delete me first",
        @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
    };
    NSDictionary *secondValue = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Delete me second",
        @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]
    };

    [self.service putRecord:@"app.bsky.feed.post"
                       rkey:@"apply-delete-a"
                      value:firstValue
                     forDid:self.testDID
             validationMode:PDSValidationModeOff
                      error:nil];
    [self.service putRecord:@"app.bsky.feed.post"
                       rkey:@"apply-delete-b"
                      value:secondValue
                     forDid:self.testDID
             validationMode:PDSValidationModeOff
                      error:nil];

    NSArray *writes = @[
        @{@"action": @"delete", @"collection": @"app.bsky.feed.post", @"rkey": @"apply-delete-a"},
        @{@"action": @"delete", @"collection": @"app.bsky.feed.post", @"rkey": @"apply-delete-b"}
    ];

    NSError *error = nil;
    NSDictionary *result = [self.service applyWrites:writes
                                              forDid:self.testDID
                                            validate:NO
                                          swapCommit:nil
                                               error:&error];
    XCTAssertNotNil(result);
    XCTAssertNil(error);

    PDSActorStore *store = [self.pool storeForDid:self.testDID error:&error];
    XCTAssertNotNil(store);
    XCTAssertNil(error);

    NSArray<NSDictionary<NSString *, id> *> *tombstones = [store listRecordTombstonesSinceRev:nil
                                                                                         limit:10
                                                                                         error:&error];
    XCTAssertNotNil(tombstones);
    XCTAssertNil(error);
    XCTAssertEqual(tombstones.count, 2U);

    NSString *firstRev = tombstones.firstObject[@"rev"];
    NSString *secondRev = tombstones.lastObject[@"rev"];
    XCTAssertEqualObjects(firstRev, secondRev);
}

@end
