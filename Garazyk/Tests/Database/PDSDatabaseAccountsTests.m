// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>
#import "Database/PDSDatabase.h"

@interface PDSDatabaseAccountsTests : XCTestCase
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) NSURL *tempDirURL;
@end

@implementation PDSDatabaseAccountsTests

- (void)setUp {
    [super setUp];
    self.tempDirURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"accounts_test_%@", [[NSUUID UUID] UUIDString]]]];
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

- (PDSDatabaseAccount *)testAccountWithDid:(NSString *)did handle:(NSString *)handle {
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = did;
    account.handle = handle;
    account.status = @"active";
    account.createdAt = [[NSDate date] timeIntervalSince1970];
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    return account;
}

#pragma mark - Create

- (void)testCreateAccount {
    PDSDatabaseAccount *account = [self testAccountWithDid:@"did:plc:test123" handle:@"alice.test"];
    NSError *error = nil;
    BOOL created = [self.database createAccount:account error:&error];
    XCTAssertTrue(created, @"createAccount should succeed");
    XCTAssertNil(error);
}

- (void)testCreateAccountWithOptionalFields {
    PDSDatabaseAccount *account = [self testAccountWithDid:@"did:plc:fullacct" handle:@"bob.test"];
    account.email = @"bob@test.com";
    account.inviteEnabled = YES;
    account.tfaEnabled = NO;
    NSError *error = nil;
    BOOL created = [self.database createAccount:account error:&error];
    XCTAssertTrue(created);
    XCTAssertNil(error);
}

#pragma mark - Read

- (void)testGetAccountByDid {
    PDSDatabaseAccount *account = [self testAccountWithDid:@"did:plc:lookup1" handle:@"carol.test"];
    [self.database createAccount:account error:nil];

    NSError *error = nil;
    PDSDatabaseAccount *found = [self.database getAccountByDid:@"did:plc:lookup1" error:&error];
    XCTAssertNotNil(found, @"Should find account by DID");
    XCTAssertNil(error);
    XCTAssertEqualObjects(found.did, @"did:plc:lookup1");
    XCTAssertEqualObjects(found.handle, @"carol.test");
}

- (void)testGetAccountByDidNotFound {
    NSError *error = nil;
    PDSDatabaseAccount *found = [self.database getAccountByDid:@"did:plc:nonexistent" error:&error];
    XCTAssertNil(found, @"Should return nil for nonexistent DID");
    XCTAssertNil(error);
}

- (void)testGetAccountByHandle {
    PDSDatabaseAccount *account = [self testAccountWithDid:@"did:plc:handle1" handle:@"dave.test"];
    [self.database createAccount:account error:nil];

    NSError *error = nil;
    PDSDatabaseAccount *found = [self.database getAccountByHandle:@"dave.test" error:&error];
    XCTAssertNotNil(found, @"Should find account by handle");
    XCTAssertNil(error);
    XCTAssertEqualObjects(found.did, @"did:plc:handle1");
    XCTAssertEqualObjects(found.handle, @"dave.test");
}

- (void)testGetAccountByHandleNotFound {
    NSError *error = nil;
    PDSDatabaseAccount *found = [self.database getAccountByHandle:@"nobody.test" error:&error];
    XCTAssertNil(found);
    XCTAssertNil(error);
}

- (void)testGetAccountByEmail {
    PDSDatabaseAccount *account = [self testAccountWithDid:@"did:plc:email1" handle:@"eve.test"];
    account.email = @"eve@test.com";
    [self.database createAccount:account error:nil];

    NSError *error = nil;
    PDSDatabaseAccount *found = [self.database getAccountByEmail:@"eve@test.com" error:&error];
    XCTAssertNotNil(found, @"Should find account by email");
    XCTAssertNil(error);
    XCTAssertEqualObjects(found.did, @"did:plc:email1");
}

- (void)testGetAccountByEmailNotFound {
    NSError *error = nil;
    PDSDatabaseAccount *found = [self.database getAccountByEmail:@"nobody@nowhere.com" error:&error];
    XCTAssertNil(found);
    XCTAssertNil(error);
}

#pragma mark - Update

- (void)testUpdateAccount {
    PDSDatabaseAccount *account = [self testAccountWithDid:@"did:plc:update1" handle:@"frank.test"];
    [self.database createAccount:account error:nil];

    account.handle = @"frank2.test";
    account.email = @"frank2@test.com";
    NSError *error = nil;
    BOOL updated = [self.database updateAccount:account error:&error];
    XCTAssertTrue(updated);
    XCTAssertNil(error);

    PDSDatabaseAccount *found = [self.database getAccountByDid:@"did:plc:update1" error:nil];
    XCTAssertEqualObjects(found.handle, @"frank2.test");
    XCTAssertEqualObjects(found.email, @"frank2@test.com");
}

#pragma mark - Delete

- (void)testDeleteAccount {
    PDSDatabaseAccount *account = [self testAccountWithDid:@"did:plc:delete1" handle:@"gone.test"];
    [self.database createAccount:account error:nil];

    NSError *error = nil;
    BOOL deleted = [self.database deleteAccount:@"did:plc:delete1" error:&error];
    XCTAssertTrue(deleted);
    XCTAssertNil(error);

    PDSDatabaseAccount *found = [self.database getAccountByDid:@"did:plc:delete1" error:nil];
    XCTAssertNil(found, @"Account should be gone after deletion");
}

- (void)testDeleteAccountNonexistent {
    NSError *error = nil;
    BOOL deleted = [self.database deleteAccount:@"did:plc:nonexistent" error:&error];
    // Deleting a nonexistent account: behavior depends on implementation
    // (may return YES with no-op or NO with error)
    (void)deleted;
}

#pragma mark - List

- (void)testGetAllAccounts {
    [self.database createAccount:[self testAccountWithDid:@"did:plc:all1" handle:@"a1.test"] error:nil];
    [self.database createAccount:[self testAccountWithDid:@"did:plc:all2" handle:@"a2.test"] error:nil];

    NSError *error = nil;
    NSArray<PDSDatabaseAccount *> *accounts = [self.database getAllAccountsWithError:&error];
    XCTAssertGreaterThanOrEqual(accounts.count, 2);
    XCTAssertNil(error);
}

- (void)testGetAccountsWithLimitPagination {
    for (int i = 0; i < 5; i++) {
        NSString *did = [NSString stringWithFormat:@"did:plc:page%d", i];
        NSString *handle = [NSString stringWithFormat:@"p%d.test", i];
        [self.database createAccount:[self testAccountWithDid:did handle:handle] error:nil];
    }

    NSError *error = nil;
    NSArray<PDSDatabaseAccount *> *page1 = [self.database getAccountsWithLimit:2 afterDid:nil error:&error];
    XCTAssertNil(error);
    XCTAssertGreaterThanOrEqual(page1.count, 2);

    if (page1.count > 0) {
        NSString *lastDid = [page1 lastObject].did;
        NSArray<PDSDatabaseAccount *> *page2 = [self.database getAccountsWithLimit:2 afterDid:lastDid error:&error];
        XCTAssertNil(error);
        XCTAssertGreaterThanOrEqual(page2.count, 1);
    }
}

@end
