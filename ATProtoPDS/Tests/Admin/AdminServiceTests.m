#import <XCTest/XCTest.h>
#import "Admin/AdminService.h"
#import "Database/PDSDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@interface AdminServiceTests : XCTestCase
@property (nonatomic, strong, nullable) PDSDatabase *database;
@property (nonatomic, strong, nullable) AdminService *service;
@end

@implementation AdminServiceTests

- (void)setUp {
    [super setUp];
    NSError *error = nil;
    self.database = [self createInMemoryDatabase:&error];
    XCTAssertNotNil(self.database, @"Database setup failed: %@", error);
    self.service = [[AdminService alloc] initWithDatabase:self.database];
}

- (void)tearDown {
    [self.database close];
    self.database = nil;
    self.service = nil;
    [super tearDown];
}

- (PDSDatabase *)createInMemoryDatabase:(NSError **)error {
    PDSDatabase *database = [PDSDatabase databaseAtURL:[NSURL URLWithString:@":memory:"]];
    if (![database openWithError:error]) {
        return nil;
    }
    return database;
}

- (PDSDatabaseAccount *)createAccountWithDid:(NSString *)did handle:(NSString *)handle {
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = did;
    account.handle = handle;
    account.email = [NSString stringWithFormat:@"%@@example.com", handle];
    account.createdAt = [[NSDate date] timeIntervalSince1970];
    account.updatedAt = account.createdAt;
    NSError *error = nil;
    XCTAssertTrue([self.database createAccount:account error:&error], @"Account create failed: %@", error);
    return account;
}

- (NSNumber *)inviteEnabledForDid:(NSString *)did {
    NSError *error = nil;
    NSArray *rows = [self.database executeParameterizedQuery:@"SELECT invite_enabled FROM accounts WHERE did = ?"
                                                     params:@[did]
                                                      error:&error];
    XCTAssertNil(error);
    if (rows.count == 0) {
        return nil;
    }
    return rows.firstObject[@"invite_enabled"];
}

- (void)testGetAccountInfoMissing {
    NSError *error = nil;
    NSDictionary *info = [self.service getAccountInfoForDid:@"did:plc:missing" error:&error];
    XCTAssertNil(info);
}

- (void)testUpdateAccountHandleAndEmail {
    [self createAccountWithDid:@"did:plc:acct1" handle:@"user.example.com"];

    NSError *error = nil;
    NSDictionary *handleResult = [self.service updateAccountHandle:@"did:plc:acct1"
                                                         newHandle:@"new.example.com"
                                                             error:&error];
    XCTAssertNotNil(handleResult);
    XCTAssertNil(error);

    PDSDatabaseAccount *updated = [self.database getAccountByDid:@"did:plc:acct1" error:&error];
    XCTAssertNotNil(updated);
    XCTAssertEqualObjects(updated.handle, @"new.example.com");

    error = nil;
    NSDictionary *emailResult = [self.service updateAccountEmail:@"did:plc:acct1"
                                                           email:@"new@example.com"
                                                           error:&error];
    XCTAssertNotNil(emailResult);
    XCTAssertNil(error);

    updated = [self.database getAccountByDid:@"did:plc:acct1" error:&error];
    XCTAssertNotNil(updated);
    XCTAssertEqualObjects(updated.email, @"new@example.com");
}

- (void)testUpdateAccountPassword {
    [self createAccountWithDid:@"did:plc:acct2" handle:@"pass.example.com"];

    NSError *error = nil;
    NSDictionary *result = [self.service updateAccountPassword:@"did:plc:acct2"
                                                   newPassword:@"newpass123"
                                                         error:&error];
    XCTAssertNotNil(result);
    XCTAssertNil(error);

    PDSDatabaseAccount *updated = [self.database getAccountByDid:@"did:plc:acct2" error:&error];
    XCTAssertNotNil(updated);
    XCTAssertNotNil(updated.passwordHash);
    XCTAssertNotNil(updated.passwordSalt);
}

- (void)testEnableDisableInvites {
    [self createAccountWithDid:@"did:plc:acct3" handle:@"invites.example.com"];

    NSError *error = nil;
    NSDictionary *enableResult = [self.service enableAccountInvites:@"did:plc:acct3" error:&error];
    XCTAssertNotNil(enableResult);
    XCTAssertNil(error);
    XCTAssertEqualObjects([self inviteEnabledForDid:@"did:plc:acct3"], @1);

    error = nil;
    NSDictionary *disableResult = [self.service disableAccountInvites:@"did:plc:acct3" error:&error];
    XCTAssertNotNil(disableResult);
    XCTAssertNil(error);
    XCTAssertEqualObjects([self inviteEnabledForDid:@"did:plc:acct3"], @0);
}

@end

NS_ASSUME_NONNULL_END
