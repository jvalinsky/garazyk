// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>
#import "Database/PDSDatabase.h"

@interface PDSDatabaseRecordsTests : XCTestCase
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) NSURL *tempDirURL;
@end

@implementation PDSDatabaseRecordsTests

- (void)setUp {
    [super setUp];
    self.tempDirURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"records_test_%@", [[NSUUID UUID] UUIDString]]]];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempDirURL
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];
    NSURL *dbURL = [self.tempDirURL URLByAppendingPathComponent:@"test.db"];
    self.database = [PDSDatabase databaseAtURL:dbURL];
    NSError *error = nil;
    XCTAssertTrue([self.database openWithError:&error], @"Failed to open database: %@", error);
    XCTAssertNil(error);
}

- (void)tearDown {
    [self.database close];
    self.database = nil;
    [[NSFileManager defaultManager] removeItemAtURL:self.tempDirURL error:nil];
    [super tearDown];
}

#pragma mark - Helper

- (PDSDatabaseRecord *)testRecordWithUri:(NSString *)uri did:(NSString *)did {
    PDSDatabaseRecord *record = [[PDSDatabaseRecord alloc] init];
    record.uri = uri;
    record.did = did;
    record.collection = @"app.bsky.actor.profile";
    record.rkey = @"self";
    record.cid = @"bafyreitestrecordcid";
    record.createdAt = [NSDate date];
    record.value = @"{\"displayName\":\"Test User\"}";
    record.rev = @"3j4k5l6m7n";
    record.indexedAt = [NSDate date];
    return record;
}

#pragma mark - Create

- (void)testSaveRecord {
    PDSDatabaseRecord *record = [self testRecordWithUri:@"at://did:plc:rec1/app.bsky.actor.profile/self" did:@"did:plc:rec1"];
    NSError *error = nil;
    BOOL saved = [self.database saveRecord:record error:&error];
    XCTAssertTrue(saved, @"saveRecord should succeed");
    XCTAssertNil(error);
}

#pragma mark - Read

- (void)testGetRecord {
    NSString *uri = @"at://did:plc:getrec/app.bsky.actor.profile/self";
    PDSDatabaseRecord *record = [self testRecordWithUri:uri did:@"did:plc:getrec"];
    [self.database saveRecord:record error:nil];

    NSError *error = nil;
    PDSDatabaseRecord *found = [self.database getRecord:uri error:&error];
    XCTAssertNotNil(found, @"Should find record by URI");
    XCTAssertNil(error);
    XCTAssertEqualObjects(found.uri, uri);
    XCTAssertEqualObjects(found.did, @"did:plc:getrec");
    XCTAssertEqualObjects(found.collection, @"app.bsky.actor.profile");
}

- (void)testGetRecordNotFound {
    NSError *error = nil;
    PDSDatabaseRecord *found = [self.database getRecord:@"at://did:plc:nonexistent/app.bsky.actor.profile/self" error:&error];
    XCTAssertNil(found, @"Should return nil for nonexistent record");
    XCTAssertNil(error);
}

- (void)testGetRecordsForDidAndCollection {
    NSString *did = @"did:plc:listrecs";
    for (int i = 0; i < 3; i++) {
        NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/%d", did, i];
        PDSDatabaseRecord *record = [self testRecordWithUri:uri did:did];
        record.collection = @"app.bsky.feed.post";
        record.rkey = [NSString stringWithFormat:@"%d", i];
        [self.database saveRecord:record error:nil];
    }

    NSError *error = nil;
    NSArray<PDSDatabaseRecord *> *records = [self.database getRecordsForDid:did collection:@"app.bsky.feed.post" error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(records.count, 3);
}

- (void)testGetRecordsForDidWithoutCollection {
    NSString *did = @"did:plc:allrecs";
    PDSDatabaseRecord *profile = [self testRecordWithUri:[NSString stringWithFormat:@"at://%@/app.bsky.actor.profile/self", did] did:did];
    [self.database saveRecord:profile error:nil];

    PDSDatabaseRecord *post = [self testRecordWithUri:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/1", did] did:did];
    post.collection = @"app.bsky.feed.post";
    post.rkey = @"1";
    [self.database saveRecord:post error:nil];

    NSError *error = nil;
    NSArray<PDSDatabaseRecord *> *all = [self.database getRecordsForDid:did collection:nil error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(all.count, 2);
}

- (void)testGetRecordsForDidEmpty {
    NSError *error = nil;
    NSArray<PDSDatabaseRecord *> *records = [self.database getRecordsForDid:@"did:plc:norecs" collection:nil error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(records);
    XCTAssertEqual(records.count, 0);
}

@end
