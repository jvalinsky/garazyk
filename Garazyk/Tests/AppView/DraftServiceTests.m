// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "AppView/Services/DraftService.h"
#import "Database/PDSDatabase.h"

@interface DraftServiceTests : XCTestCase
@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) PDSDraftService *service;
@end

@implementation DraftServiceTests

- (void)setUp {
    [super setUp];
    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *dbPath = [self.testDirectory stringByAppendingPathComponent:@"draft_test.db"];
    [[NSFileManager defaultManager] removeItemAtPath:dbPath error:nil];

    self.database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    NSError *error = nil;
    XCTAssertTrue([self.database openWithError:&error], @"Database setup failed: %@", error);
    [self setupSchema];
    self.service = [[PDSDraftService alloc] initWithDatabase:self.database];
}

- (void)setupSchema {
    NSError *error = nil;
    NSString *sql = @"CREATE TABLE IF NOT EXISTS drafts ("
        @"id TEXT PRIMARY KEY, did TEXT NOT NULL, content TEXT, "
        @"created_at REAL, updated_at REAL)";
    XCTAssertTrue([self.database executeParameterizedUpdate:sql params:@[] error:&error], @"Table create: %@", error);
}

- (void)tearDown {
    [self.database close];
    self.database = nil;
    self.service = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.testDirectory error:nil];
    [super tearDown];
}

#pragma mark - Init

- (void)testService_Init {
    XCTAssertNotNil(self.service);
}

#pragma mark - createDraftForDID

- (void)testCreateDraft_Valid_ReturnsDraft {
    NSError *error = nil;
    NSDictionary *result = [self.service createDraftForDID:@"did:plc:test"
                                                  content:@{@"subject": @"Test draft"}
                                                    error:&error];
    XCTAssertNotNil(result);
    XCTAssertNil(error);
    XCTAssertNotNil(result[@"id"]);
    XCTAssertEqualObjects(result[@"did"], @"did:plc:test");
    XCTAssertNotNil(result[@"content"]);
}

- (void)testCreateDraft_NilDid_ReturnsNilError {
    NSError *error = nil;
    NSDictionary *result = [self.service createDraftForDID:(NSString *)nil
                                                  content:@{@"text": @"hello"}
                                                    error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

- (void)testCreateDraft_EmptyDid_ReturnsNilError {
    NSError *error = nil;
    NSDictionary *result = [self.service createDraftForDID:@""
                                                  content:@{@"text": @"hello"}
                                                    error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

- (void)testCreateDraft_EmptyContent_ReturnsDraft {
    NSError *error = nil;
    NSDictionary *result = [self.service createDraftForDID:@"did:plc:test"
                                                  content:@{}
                                                    error:&error];
    XCTAssertNotNil(result);
    XCTAssertNil(error);
    XCTAssertNotNil(result[@"id"]);
}

- (void)testCreateDraft_NullErrorPointer_Safe {
    NSDictionary *result = [self.service createDraftForDID:(NSString *)nil
                                                  content:@{}
                                                    error:NULL];
    XCTAssertNil(result);
}

#pragma mark - getDraftsForDID

- (void)testGetDrafts_AfterCreate_ReturnsDrafts {
    [self.service createDraftForDID:@"did:plc:reader"
                           content:@{@"note": @"first"}
                             error:nil];
    [self.service createDraftForDID:@"did:plc:reader"
                           content:@{@"note": @"second"}
                             error:nil];

    NSError *error = nil;
    NSArray *drafts = [self.service getDraftsForDID:@"did:plc:reader" error:&error];
    XCTAssertNotNil(drafts);
    XCTAssertEqual(drafts.count, 2U);
    XCTAssertNil(error);
}

- (void)testGetDrafts_NonexistentDid_ReturnsEmpty {
    NSError *error = nil;
    NSArray *drafts = [self.service getDraftsForDID:@"did:plc:nobody" error:&error];
    XCTAssertNotNil(drafts);
    XCTAssertEqual(drafts.count, 0U);
    XCTAssertNil(error);
}

- (void)testGetDrafts_NilDid_ReturnsNilError {
    NSError *error = nil;
    NSArray *drafts = [self.service getDraftsForDID:(NSString *)nil error:&error];
    XCTAssertNil(drafts);
    XCTAssertNotNil(error);
}

- (void)testGetDrafts_EmptyDid_ReturnsNilError {
    NSError *error = nil;
    NSArray *drafts = [self.service getDraftsForDID:@"" error:&error];
    XCTAssertNil(drafts);
    XCTAssertNotNil(error);
}

#pragma mark - updateDraftForDID

- (void)testUpdateDraft_Valid_ReturnsSuccess {
    NSDictionary *created = [self.service createDraftForDID:@"did:plc:updater"
                                                    content:@{@"original": @"data"}
                                                      error:nil];
    NSString *draftID = created[@"id"];

    NSError *error = nil;
    BOOL result = [self.service updateDraftForDID:@"did:plc:updater"
                                         draftID:draftID
                                         content:@{@"updated": @"data"}
                                           error:&error];
    XCTAssertTrue(result);
    XCTAssertNil(error);
}

- (void)testUpdateDraft_NilDid_ReturnsNOError {
    NSDictionary *created = [self.service createDraftForDID:@"did:plc:test"
                                                    content:@{@"a": @"b"}
                                                      error:nil];
    NSError *error = nil;
    BOOL result = [self.service updateDraftForDID:(NSString *)nil
                                         draftID:created[@"id"]
                                         content:@{}
                                           error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testUpdateDraft_EmptyDid_ReturnsNOError {
    NSDictionary *created = [self.service createDraftForDID:@"did:plc:test"
                                                    content:@{@"a": @"b"}
                                                      error:nil];
    NSError *error = nil;
    BOOL result = [self.service updateDraftForDID:@""
                                         draftID:created[@"id"]
                                         content:@{}
                                           error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testUpdateDraft_NilDraftID_ReturnsNOError {
    NSError *error = nil;
    BOOL result = [self.service updateDraftForDID:@"did:plc:test"
                                         draftID:(NSString *)nil
                                         content:@{}
                                           error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

#pragma mark - deleteDraftForDID

- (void)testDeleteDraft_Valid_ReturnsSuccess {
    NSDictionary *created = [self.service createDraftForDID:@"did:plc:deleter"
                                                    content:@{@"delete": @"me"}
                                                      error:nil];

    NSError *error = nil;
    BOOL result = [self.service deleteDraftForDID:@"did:plc:deleter"
                                         draftID:created[@"id"]
                                           error:&error];
    XCTAssertTrue(result);
    XCTAssertNil(error);

    // Verify the draft is gone
    NSArray *drafts = [self.service getDraftsForDID:@"did:plc:deleter" error:nil];
    XCTAssertEqual(drafts.count, 0U);
}

- (void)testDeleteDraft_NilDid_ReturnsNOError {
    NSError *error = nil;
    BOOL result = [self.service deleteDraftForDID:(NSString *)nil draftID:@"some-id" error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testDeleteDraft_NilDraftID_ReturnsNOError {
    NSError *error = nil;
    BOOL result = [self.service deleteDraftForDID:@"did:plc:test" draftID:(NSString *)nil error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

@end
