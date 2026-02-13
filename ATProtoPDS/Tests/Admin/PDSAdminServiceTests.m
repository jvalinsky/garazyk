#import <XCTest/XCTest.h>
#import "Services/PDSAdminService.h"
#import "Database/PDSDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@interface PDSAdminServiceTests : XCTestCase
@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong, nullable) PDSDatabase *database;
@property (nonatomic, strong, nullable) PDSAdminService *service;
@end

@implementation PDSAdminServiceTests

- (void)setUp {
    [super setUp];
    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    
    NSString *dbPath = [self.testDirectory stringByAppendingPathComponent:@"admin.sqlite"];
    self.database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    
    NSError *error = nil;
    XCTAssertTrue([self.database openWithError:&error], @"Database setup failed: %@", error);
    
    self.service = [[PDSAdminService alloc] initWithDatabase:self.database databasePool:nil];
}

- (void)tearDown {
    [self.database close];
    self.database = nil;
    self.service = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.testDirectory error:nil];
    [super tearDown];
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

- (NSNumber *)disabledFlagForInviteCode:(NSString *)code {
    NSError *error = nil;
    NSArray *rows = [self.database executeParameterizedQuery:@"SELECT disabled FROM invite_codes WHERE code = ?"
                                                     params:@[code]
                                                      error:&error];
    XCTAssertNil(error);
    if (rows.count == 0) {
        return nil;
    }
    id value = rows.firstObject[@"disabled"];
    return [value respondsToSelector:@selector(integerValue)] ? @([value integerValue]) : nil;
}

- (void)testServiceInitialization {
    XCTAssertNotNil(self.service);
    XCTAssertEqual(self.service.database, self.database);
}

- (void)testUpdateAccountHandleAndEmail {
    [self createAccountWithDid:@"did:plc:acct1" handle:@"user.example.com"];

    NSError *error = nil;
    BOOL handleSuccess = [self.service updateHandle:@"new.example.com"
                                        forAccount:@"did:plc:acct1"
                                             error:&error];
    XCTAssertTrue(handleSuccess);
    XCTAssertNil(error);

    error = nil;
    BOOL success = [self.service updateEmail:@"new@example.com"
                                  forAccount:@"did:plc:acct1"
                                       error:&error];
    XCTAssertTrue(success);
    XCTAssertNil(error);

    PDSDatabaseAccount *updated = [self.database getAccountByDid:@"did:plc:acct1" error:&error];
    XCTAssertNotNil(updated);
    XCTAssertEqualObjects(updated.email, @"new@example.com");
}

- (void)testUpdateAccountPassword {
    [self createAccountWithDid:@"did:plc:acct2" handle:@"pass.example.com"];

    NSError *error = nil;
    BOOL passResult = [self.service updateAccountPassword:@"did:plc:acct2"
                                                 newPassword:@"newpass123"
                                                       error:&error];
    XCTAssertTrue(passResult);
    XCTAssertNil(error);
}

- (void)testEnableDisableInvites {
    [self createAccountWithDid:@"did:plc:acct3" handle:@"invites.example.com"];

    NSError *error = nil;
    NSDictionary *createInviteResult = [self.service createInviteCode:@{@"forAccount": @"did:plc:acct3"} error:&error];
    XCTAssertNotNil(createInviteResult);
    XCTAssertNil(error);

    error = nil;
    BOOL enableResult = [self.service enableAccountInvitesForDid:@"did:plc:acct3" error:&error];
    XCTAssertTrue(enableResult);
    XCTAssertNil(error);
    
    BOOL disableResult = [self.service disableAccountInvitesForDid:@"did:plc:acct3" error:&error];
    XCTAssertTrue(disableResult);
    XCTAssertNil(error);
    XCTAssertEqualObjects([self inviteEnabledForDid:@"did:plc:acct3"], @0);
}

- (void)testCreateInviteCode {
    [self createAccountWithDid:@"did:plc:invite1" handle:@"invite.example.com"];

    NSError *error = nil;
    NSDictionary *result = [self.service createInviteCode:@{@"forAccount": @"did:plc:invite1"} error:&error];
    
    XCTAssertNotNil(result);
    XCTAssertNil(error);
    XCTAssertNotNil(result[@"code"]);
}

- (void)testCreateInviteCodeWithUses {
    [self createAccountWithDid:@"did:plc:invite2" handle:@"invite2.example.com"];

    NSError *error = nil;
    NSDictionary *result = [self.service createInviteCode:@{
        @"forAccount": @"did:plc:invite2",
        @"usesAvailable": @(5)
    } error:&error];
    
    XCTAssertNotNil(result);
    XCTAssertNil(error);
    XCTAssertNotNil(result[@"code"]);
}

- (void)testDisableInviteCode {
    [self createAccountWithDid:@"did:plc:invite3" handle:@"invite3.example.com"];

    NSError *error = nil;
    NSDictionary *createResult = [self.service createInviteCode:@{@"forAccount": @"did:plc:invite3"} error:&error];
    NSString *code = createResult[@"code"];
    
    error = nil;
    BOOL disabled = [self.service disableInviteCode:code error:&error];
    XCTAssertTrue(disabled);
    XCTAssertNil(error);

    NSArray *rows = [self.database executeParameterizedQuery:@"SELECT disabled FROM invite_codes WHERE code = ?"
                                                     params:@[code]
                                                      error:&error];
    XCTAssertNil(error);
    XCTAssertEqual([rows.firstObject[@"disabled"] integerValue], 1);
}

- (void)testDisableInviteCodesByCodesAndAccounts {
    [self createAccountWithDid:@"did:plc:invite4" handle:@"invite4.example.com"];
    [self createAccountWithDid:@"did:plc:invite5" handle:@"invite5.example.com"];

    NSError *error = nil;
    NSDictionary *first = [self.service createInviteCode:@{@"forAccount": @"did:plc:invite4"} error:&error];
    XCTAssertNotNil(first);
    XCTAssertNil(error);
    NSDictionary *second = [self.service createInviteCode:@{@"forAccount": @"did:plc:invite4"} error:&error];
    XCTAssertNotNil(second);
    XCTAssertNil(error);
    NSDictionary *third = [self.service createInviteCode:@{@"forAccount": @"did:plc:invite5"} error:&error];
    XCTAssertNotNil(third);
    XCTAssertNil(error);

    NSString *targetedCode = first[@"code"];
    NSString *untouchedCode = second[@"code"];
    NSString *accountDisabledCode = third[@"code"];

    BOOL result = [self.service disableInviteCodesWithCodes:@[targetedCode]
                                                   accounts:@[@"invite5.example.com"]
                                                      error:&error];
    XCTAssertTrue(result);
    XCTAssertNil(error);

    XCTAssertEqualObjects([self disabledFlagForInviteCode:targetedCode], @1);
    XCTAssertEqualObjects([self disabledFlagForInviteCode:untouchedCode], @0);
    XCTAssertEqualObjects([self disabledFlagForInviteCode:accountDisabledCode], @1);
}

- (void)testDisableInviteCodesRequiresCriteria {
    NSError *error = nil;
    BOOL result = [self.service disableInviteCodesWithCodes:@[] accounts:@[] error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 400);
}

- (void)testDisableInviteCodesUnknownAccountFails {
    NSError *error = nil;
    BOOL result = [self.service disableInviteCodesWithCodes:nil
                                                   accounts:@[@"missing.example.com"]
                                                      error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 404);
}

- (void)testUpdateHandleNonexistentAccount {
    NSError *error = nil;
    BOOL result = [self.service updateHandle:@"nonexistent.example.com"
                                  forAccount:@"did:plc:nonexistent"
                                       error:&error];
    XCTAssertFalse(result);
}

- (void)testUpdateEmailNonexistentAccount {
    NSError *error = nil;
    BOOL result = [self.service updateEmail:@"nonexistent@example.com"
                                 forAccount:@"did:plc:nonexistent"
                                      error:&error];
    XCTAssertFalse(result);
}

- (void)testUpdatePasswordNonexistentAccount {
    NSError *error = nil;
    BOOL result = [self.service updateAccountPassword:@"did:plc:nonexistent"
                                             newPassword:@"password123"
                                                   error:&error];
    XCTAssertFalse(result);
}

- (void)testEnableInvitesNonexistentAccount {
    NSError *error = nil;
    BOOL result = [self.service enableAccountInvitesForDid:@"did:plc:nonexistent" error:&error];
    XCTAssertFalse(result);
}

- (void)testDisableInvitesNonexistentAccount {
    NSError *error = nil;
    BOOL result = [self.service disableAccountInvitesForDid:@"did:plc:nonexistent" error:&error];
    XCTAssertFalse(result);
}

- (void)testDisableNonexistentInviteCode {
    NSError *error = nil;
    BOOL result = [self.service disableInviteCode:@"nonexistent-code" error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, 404);
}

- (void)testInviteCodeForNonexistentAccount {
    NSError *error = nil;
    NSDictionary *result = [self.service createInviteCode:@{@"forAccount": @"did:plc:nonexistent"} error:&error];
    XCTAssertNil(result);
}

- (void)testAccountDeletion {
    [self createAccountWithDid:@"did:plc:delete" handle:@"delete.example.com"];
    
    NSError *error = nil;
    PDSDatabaseAccount *account = [self.database getAccountByDid:@"did:plc:delete" error:&error];
    XCTAssertNotNil(account);
    
    BOOL deleted = [self.database deleteAccount:@"did:plc:delete" error:&error];
    XCTAssertTrue(deleted);
    
    account = [self.database getAccountByDid:@"did:plc:delete" error:&error];
    XCTAssertNil(account);
}

@end

NS_ASSUME_NONNULL_END
