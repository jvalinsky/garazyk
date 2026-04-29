#import <XCTest/XCTest.h>
#import "Record.h"
#import "RecordRepository.h"
#import "RecordService.h"
#import "TutorialCIDGenerator.h"

@interface RecordServiceTests : XCTestCase
@property (nonatomic, strong) NSString *dbPath;
@property (nonatomic, strong) RecordRepository *repo;
@property (nonatomic, strong) RecordService *service;
@end

@implementation RecordServiceTests

- (void)setUp {
    [super setUp];
    self.dbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                  [NSString stringWithFormat:@"rec_test_%@", [[NSUUID UUID] UUIDString]]];
    self.repo = [[RecordRepository alloc] initWithDatabasePath:self.dbPath];
    self.service = [[RecordService alloc] initWithRepository:self.repo];
}

- (void)tearDown {
    self.service = nil;
    self.repo = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.dbPath error:nil];
    [super tearDown];
}

- (void)testCreateRecord {
    NSError *error = nil;
    NSDictionary *result = [self.service createRecord:@"app.bsky.feed.post"
                                                 rkey:@"test123"
                                                value:@{@"text": @"Hello!"}
                                               forDid:@"did:web:localhost:~alice"
                                                error:&error];
    XCTAssertNotNil(result, @"Record should be created");
    XCTAssertNil(error);
    XCTAssertNotNil(result[@"uri"], @"Should return URI");
    XCTAssertNotNil(result[@"cid"], @"Should return CID");
    XCTAssertTrue([result[@"uri"] hasPrefix:@"at://did:web:localhost:~alice/app.bsky.feed.post/"]);
}

- (void)testGetRecord {
    NSError *error = nil;
    NSDictionary *created = [self.service createRecord:@"app.bsky.feed.post"
                                                   rkey:@"test456"
                                                  value:@{@"text": @"Test record"}
                                                 forDid:@"did:web:localhost:~alice"
                                                  error:&error];
    NSString *uri = created[@"uri"];

    NSDictionary *retrieved = [self.service getRecord:uri forDid:@"did:web:localhost:~alice" error:&error];
    XCTAssertNotNil(retrieved, @"Should retrieve created record");
    XCTAssertEqualObjects(retrieved[@"uri"], uri, @"URI should match");
    XCTAssertEqualObjects(retrieved[@"value"][@"text"], @"Test record", @"Content should match");
}

- (void)testGetNonexistentRecord {
    NSError *error = nil;
    NSDictionary *result = [self.service getRecord:@"at://did:web:localhost:~alice/app.bsky.feed.post/nonexistent"
                                           forDid:@"did:web:localhost:~alice"
                                            error:&error];
    XCTAssertNil(result, @"Should return nil for nonexistent record");
}

- (void)testListRecords {
    NSError *error = nil;
    [self.service createRecord:@"app.bsky.feed.post"
                          rkey:@"post1"
                         value:@{@"text": @"First"}
                        forDid:@"did:web:localhost:~alice"
                         error:nil];
    [self.service createRecord:@"app.bsky.feed.post"
                          rkey:@"post2"
                         value:@{@"text": @"Second"}
                        forDid:@"did:web:localhost:~alice"
                         error:nil];

    NSArray *records = [self.service listRecords:@"app.bsky.feed.post"
                                          forDid:@"did:web:localhost:~alice"
                                           limit:50
                                           error:&error];
    XCTAssertNotNil(records);
    XCTAssertEqual(records.count, 2, @"Should list 2 records");
}

- (void)testListRecordsWithLimit {
    for (int i = 0; i < 5; i++) {
        [self.service createRecord:@"app.bsky.feed.post"
                              rkey:[NSString stringWithFormat:@"post%d", i]
                             value:@{@"text": [NSString stringWithFormat:@"Post %d", i]}
                            forDid:@"did:web:localhost:~alice"
                             error:nil];
    }

    NSArray *records = [self.service listRecords:@"app.bsky.feed.post"
                                          forDid:@"did:web:localhost:~alice"
                                           limit:3
                                           error:nil];
    XCTAssertNotNil(records);
    XCTAssertEqual(records.count, 3, @"Should limit to 3 records");
}

- (void)testDeleteRecord {
    NSDictionary *created = [self.service createRecord:@"app.bsky.feed.post"
                                                   rkey:@"todelete"
                                                  value:@{@"text": @"Delete me"}
                                                 forDid:@"did:web:localhost:~alice"
                                                  error:nil];
    NSString *uri = created[@"uri"];

    NSError *error = nil;
    BOOL deleted = [self.service deleteRecord:uri forDid:@"did:web:localhost:~alice" error:&error];
    XCTAssertTrue(deleted, @"Delete should succeed");

    NSDictionary *shouldBeNil = [self.service getRecord:uri forDid:@"did:web:localhost:~alice" error:nil];
    XCTAssertNil(shouldBeNil, @"Record should be gone after deletion");
}

- (void)testRecordsIsolatedByDID {
    [self.service createRecord:@"app.bsky.feed.post"
                          rkey:@"alice-post"
                         value:@{@"text": @"Alice's post"}
                        forDid:@"did:web:localhost:~alice"
                         error:nil];
    [self.service createRecord:@"app.bsky.feed.post"
                          rkey:@"bob-post"
                         value:@{@"text": @"Bob's post"}
                        forDid:@"did:web:localhost:~bob"
                         error:nil];

    NSArray *aliceRecords = [self.service listRecords:@"app.bsky.feed.post"
                                               forDid:@"did:web:localhost:~alice"
                                                limit:50
                                                error:nil];
    NSArray *bobRecords = [self.service listRecords:@"app.bsky.feed.post"
                                             forDid:@"did:web:localhost:~bob"
                                              limit:50
                                              error:nil];
    XCTAssertEqual(aliceRecords.count, 1, @"Alice should see 1 record");
    XCTAssertEqual(bobRecords.count, 1, @"Bob should see 1 record");
}

@end
