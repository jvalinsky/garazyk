#import <XCTest/XCTest.h>
#import "Account.h"
#import "AccountRepository.h"
#import "AccountService.h"
#import "TutorialJWTMinter.h"

@interface AccountServiceTests : XCTestCase
@property (nonatomic, strong) NSString *dbPath;
@property (nonatomic, strong) AccountRepository *repo;
@property (nonatomic, strong) TutorialJWTMinter *minter;
@property (nonatomic, strong) AccountService *service;
@end

@implementation AccountServiceTests

- (void)setUp {
    [super setUp];
    self.dbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                  [NSString stringWithFormat:@"acct_test_%@", [[NSUUID UUID] UUIDString]]];
    // Create the directory so AccountRepository can create the DB file inside it
    [[NSFileManager defaultManager] createDirectoryAtPath:self.dbPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    self.repo = [[AccountRepository alloc] initWithDatabasePath:self.dbPath];
    self.minter = [[TutorialJWTMinter alloc] initWithIssuer:@"did:web:localhost:2583"];
    self.service = [[AccountService alloc] initWithRepository:self.repo minter:self.minter];
}

- (void)tearDown {
    self.service = nil;
    self.minter = nil;
    self.repo = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.dbPath error:nil];
    [super tearDown];
}

- (void)testCreateAccount {
    NSError *error = nil;
    NSDictionary *result = [self.service createAccountForEmail:@"alice@example.com"
                                                       password:@"password123"
                                                         handle:@"alice.example"
                                                          error:&error];
    XCTAssertNotNil(result, @"Account should be created");
    XCTAssertNil(error, @"No error on creation");
    XCTAssertEqualObjects(result[@"handle"], @"alice.example");
    XCTAssertEqualObjects(result[@"email"], @"alice@example.com");
    XCTAssertTrue([result[@"did"] hasPrefix:@"did:web:localhost:~"], @"DID should use did:web format");
    XCTAssertNotNil(result[@"accessJwt"], @"Should have access JWT");
    XCTAssertNotNil(result[@"refreshJwt"], @"Should have refresh JWT");
}

- (void)testDuplicateHandleFails {
    NSError *error = nil;
    [self.service createAccountForEmail:@"alice@example.com"
                                password:@"pass1"
                                  handle:@"alice.example"
                                   error:nil];
    NSDictionary *duplicate = [self.service createAccountForEmail:@"alice2@example.com"
                                                          password:@"pass2"
                                                            handle:@"alice.example"
                                                             error:&error];
    XCTAssertNil(duplicate, @"Duplicate handle should fail");
    XCTAssertNotNil(error, @"Should return error for duplicate handle");
}

- (void)testDuplicateEmailFails {
    NSError *error = nil;
    [self.service createAccountForEmail:@"alice@example.com"
                                password:@"pass1"
                                  handle:@"alice.example"
                                   error:nil];
    NSDictionary *duplicate = [self.service createAccountForEmail:@"alice@example.com"
                                                          password:@"pass2"
                                                            handle:@"alice2.example"
                                                             error:&error];
    XCTAssertNil(duplicate, @"Duplicate email should fail");
    XCTAssertNotNil(error, @"Should return error for duplicate email");
}

- (void)testLoginWithCorrectPassword {
    NSError *error = nil;
    [self.service createAccountForEmail:@"alice@example.com"
                                password:@"password123"
                                  handle:@"alice.example"
                                   error:nil];

    NSDictionary *loggedIn = [self.service loginWithHandle:@"alice.example"
                                                  password:@"password123"
                                                     error:&error];
    XCTAssertNotNil(loggedIn, @"Login should succeed with correct password");
    XCTAssertNil(error);
    XCTAssertNotNil(loggedIn[@"accessJwt"], @"Should return access JWT");
}

- (void)testLoginWithWrongPasswordFails {
    NSError *error = nil;
    [self.service createAccountForEmail:@"alice@example.com"
                                password:@"password123"
                                  handle:@"alice.example"
                                   error:nil];

    NSDictionary *loggedIn = [self.service loginWithHandle:@"alice.example"
                                                  password:@"wrongpassword"
                                                     error:&error];
    XCTAssertNil(loggedIn, @"Login should fail with wrong password");
    XCTAssertNotNil(error, @"Should return error for wrong password");
}

- (void)testLoginNonexistentAccountFails {
    NSError *error = nil;
    NSDictionary *loggedIn = [self.service loginWithHandle:@"nobody.example"
                                                  password:@"password"
                                                     error:&error];
    XCTAssertNil(loggedIn, @"Login should fail for nonexistent account");
    XCTAssertNotNil(error, @"Should return error for nonexistent account");
}

@end
