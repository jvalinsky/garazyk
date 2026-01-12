#import <XCTest/XCTest.h>
#import "Database/PDSDatabase.h"
#import "Database/Integration/PDSDatabaseIntegrationTestUtilities.h"

@interface PDSDatabaseIntegrationTests : XCTestCase

@property (nonatomic, strong) PDSDatabase *database;

@end

@implementation PDSDatabaseIntegrationTests

- (void)setUp {
    [super setUp];
    
    __autoreleasing NSError *error = nil;
    self.database = [PDSDatabaseIntegrationTestUtilities createInMemoryDatabaseWithError:&error];
    XCTAssertNotNil(self.database, @"Failed to create in-memory database: %@", error);
    XCTAssertTrue(self.database.isOpen, @"Database should be open");
}

- (void)tearDown {
    [self.database close];
    self.database = nil;
    [super tearDown];
}

- (void)testSchemaVerification {
    __autoreleasing NSError *error = nil;
    BOOL schemaValid = [PDSDatabaseIntegrationTestUtilities verifySchemaInDatabase:self.database error:&error];
    XCTAssertTrue(schemaValid, @"Schema should be valid: %@", error);
}

- (void)testAccountFactoryAndOperations {
    PDSDatabaseAccount *account = [PDSDatabaseIntegrationTestUtilities createTestAccountWithDID:@"did:plc:test123" handle:@"test.example.com"];
    XCTAssertNotNil(account);
    XCTAssertEqualObjects(account.did, @"did:plc:test123");
    XCTAssertEqualObjects(account.handle, @"test.example.com");
    
    __autoreleasing NSError *error = nil;
    BOOL success = [self.database createAccount:account error:&error];
    XCTAssertTrue(success, @"Failed to create account: %@", error);
    
    __autoreleasing NSError *fetchError = nil;
    PDSDatabaseAccount *fetched = [self.database getAccountByDid:@"did:plc:test123" error:&fetchError];
    XCTAssertNotNil(fetched, @"Failed to fetch account: %@", fetchError);
    XCTAssertEqualObjects(fetched.did, account.did);
    XCTAssertEqualObjects(fetched.handle, account.handle);
}

- (void)testRepoFactoryAndOperations {
    PDSDatabaseRepo *repo = [PDSDatabaseIntegrationTestUtilities createTestRepoWithOwnerDID:@"did:plc:test123"];
    XCTAssertNotNil(repo);
    XCTAssertEqualObjects(repo.ownerDid, @"did:plc:test123");
    
    __autoreleasing NSError *error = nil;
    BOOL success = [self.database createRepo:repo error:&error];
    XCTAssertTrue(success, @"Failed to create repo: %@", error);
    
    __autoreleasing NSError *fetchError = nil;
    PDSDatabaseRepo *fetched = [self.database getRepoForDid:@"did:plc:test123" error:&fetchError];
    XCTAssertNotNil(fetched, @"Failed to fetch repo: %@", fetchError);
    XCTAssertEqualObjects(fetched.ownerDid, repo.ownerDid);
}

- (void)testRecordFactoryAndOperations {
    PDSDatabaseRecord *record = [PDSDatabaseIntegrationTestUtilities createTestRecordWithDID:@"did:plc:test123" collection:@"app.bsky.feed.post" rkey:@"test123"];
    XCTAssertNotNil(record);
    XCTAssertEqualObjects(record.did, @"did:plc:test123");
    XCTAssertEqualObjects(record.collection, @"app.bsky.feed.post");
    XCTAssertEqualObjects(record.rkey, @"test123");

    __autoreleasing NSError *error = nil;
    BOOL success = [self.database saveRecord:record error:&error];
    XCTAssertTrue(success, @"Failed to save record: %@", error);

    __autoreleasing NSError *fetchError = nil;
    PDSDatabaseRecord *fetched = [self.database getRecord:record.uri error:&fetchError];
    XCTAssertNotNil(fetched, @"Failed to fetch record: %@", fetchError);
    XCTAssertEqualObjects(fetched.uri, record.uri);
    XCTAssertEqualObjects(fetched.collection, record.collection);
}

- (void)testBlobFactoryAndOperations {
    PDSDatabaseBlob *blob = [PDSDatabaseIntegrationTestUtilities createTestBlobWithDID:@"did:plc:test123"];
    XCTAssertNotNil(blob);
    XCTAssertEqualObjects(blob.did, @"did:plc:test123");
    XCTAssertTrue(blob.size > 0);

    __autoreleasing NSError *error = nil;
    BOOL success = [self.database saveBlob:blob error:&error];
    XCTAssertTrue(success, @"Failed to save blob: %@", error);

    __autoreleasing NSError *fetchError = nil;
    PDSDatabaseBlob *fetched = [self.database getBlobWithCid:blob.cid error:&fetchError];
    XCTAssertNotNil(fetched, @"Failed to fetch blob: %@", fetchError);
    XCTAssertEqualObjects(fetched.did, blob.did);
}

- (void)testBlockFactoryAndOperations {
    PDSDatabaseBlock *block = [PDSDatabaseIntegrationTestUtilities createTestBlockWithRepoDID:@"did:plc:test123"];
    XCTAssertNotNil(block);
    XCTAssertEqualObjects(block.repoDid, @"did:plc:test123");
    XCTAssertNotNil(block.blockData);

    __autoreleasing NSError *error = nil;
    BOOL success = [self.database saveBlock:block error:&error];
    XCTAssertTrue(success, @"Failed to save block: %@", error);

    __autoreleasing NSError *fetchError = nil;
    PDSDatabaseBlock *fetched = [self.database getBlockWithCid:block.cid repoDid:block.repoDid error:&fetchError];
    XCTAssertNotNil(fetched, @"Failed to fetch block: %@", fetchError);
    XCTAssertEqualObjects(fetched.repoDid, block.repoDid);
}

@end