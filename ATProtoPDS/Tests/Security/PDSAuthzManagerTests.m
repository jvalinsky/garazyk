#import <XCTest/XCTest.h>
#import "Security/PDSAuthzManager.h"
#import "Database/PDSDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@interface PDSAuthzManagerTests : XCTestCase
@property (nonatomic, strong, nullable) PDSDatabase *database;
@property (nonatomic, strong, nullable) PDSAuthzManager *manager;
@property (nonatomic, copy, nullable) NSString *databasePath;
@end

@implementation PDSAuthzManagerTests

- (void)setUp {
    [super setUp];
    NSError *error = nil;
    self.database = [self createInMemoryDatabase:&error];
    XCTAssertNotNil(self.database, @"Database setup failed: %@", error);

    self.manager = [PDSAuthzManager sharedManager];
    [self.manager setValue:self.database forKey:@"database"];
}

- (void)tearDown {
    [self.database close];
    self.database = nil;
    self.manager = nil;
    if (self.databasePath.length > 0) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        [fileManager removeItemAtPath:self.databasePath error:nil];
        [fileManager removeItemAtPath:[self.databasePath stringByAppendingString:@"-wal"] error:nil];
        [fileManager removeItemAtPath:[self.databasePath stringByAppendingString:@"-shm"] error:nil];
        self.databasePath = nil;
    }
    [super tearDown];
}

- (PDSDatabase *)createInMemoryDatabase:(NSError **)error {
    NSString *filename = [NSString stringWithFormat:@"pds-authz-tests-%@.sqlite", [[NSUUID UUID] UUIDString]];
    self.databasePath = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
    NSURL *databaseURL = [NSURL fileURLWithPath:self.databasePath];
    PDSDatabase *database = [PDSDatabase databaseAtURL:databaseURL];
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

- (PDSDatabaseRepo *)createRepoWithOwnerDid:(NSString *)did {
    PDSDatabaseRepo *repo = [[PDSDatabaseRepo alloc] init];
    repo.ownerDid = did;
    repo.rootCid = [@"root" dataUsingEncoding:NSUTF8StringEncoding];
    repo.createdAt = [NSDate date];
    repo.updatedAt = [NSDate date];
    NSError *error = nil;
    XCTAssertTrue([self.database createRepo:repo error:&error], @"Repo create failed: %@", error);
    return repo;
}

- (void)testAccessRepoSelfAuthorizedWithoutRepo {
    NSError *error = nil;
    BOOL allowed = [self.manager isAuthorizedToAccessRepo:@"did:plc:self123"
                                           requestingDID:@"did:plc:self123"
                                                   error:&error];
    XCTAssertTrue(allowed);
    XCTAssertNil(error);
}

- (void)testAccessRepoInvalidDidRejected {
    NSError *error = nil;
    BOOL allowed = [self.manager isAuthorizedToAccessRepo:@"invalid"
                                           requestingDID:@"did:plc:requester"
                                                   error:&error];
    XCTAssertFalse(allowed);
    XCTAssertEqual(error.code, PDSAuthzErrorUnauthorized);
}

- (void)testAccessRepoMissingRepoRejected {
    NSError *error = nil;
    BOOL allowed = [self.manager isAuthorizedToAccessRepo:@"did:plc:missing"
                                           requestingDID:@"did:plc:other"
                                                   error:&error];
    XCTAssertFalse(allowed);
    XCTAssertEqual(error.code, PDSAuthzErrorRepoNotFound);
}

- (void)testAccessRepoOwnershipMismatch {
    NSError *error = nil;
    [self createRepoWithOwnerDid:@"did:plc:owner"];

    error = nil;
    BOOL allowed = [self.manager isAuthorizedToAccessRepo:@"did:plc:owner"
                                           requestingDID:@"did:plc:other"
                                                   error:&error];
    XCTAssertFalse(allowed);
    XCTAssertEqual(error.code, PDSAuthzErrorRepoOwnershipMismatch);
}

- (void)testAdminAuthorizationAndEndpoints {
    NSError *error = nil;
    [self createAccountWithDid:@"did:plc:admin123" handle:@"admin.user"];

    error = nil;
    BOOL adminAllowed = [self.manager isAuthorizedForAdminOperation:@"did:plc:admin123" error:&error];
    XCTAssertTrue(adminAllowed);
    XCTAssertNil(error);

    error = nil;
    [self createAccountWithDid:@"did:plc:user123" handle:@"user.example.com"];

    error = nil;
    BOOL userAllowed = [self.manager isAuthorizedForAdminOperation:@"did:plc:user123" error:&error];
    XCTAssertFalse(userAllowed);
    XCTAssertEqual(error.code, PDSAuthzErrorAdminRequired);

    NSArray<NSString *> *adminMethods = @[
        @"com.atproto.admin.getAccountInfo",
        @"com.atproto.admin.moderateAccount",
        @"com.atproto.admin.moderateRecord",
        @"com.atproto.admin.takeDownAccount",
        @"com.atproto.admin.getAccountTakedown",
        @"com.atproto.admin.disableInviteCodes",
        @"com.atproto.admin.getSubjectStatus",
        @"com.atproto.admin.updateSubjectStatus",
    ];
    for (NSString *method in adminMethods) {
        XCTAssertTrue([self.manager isAdminEndpoint:method], @"Expected %@ to require admin", method);
    }

    XCTAssertTrue([self.manager isAdminEndpoint:@"com.atproto.temp.addReservedHandle"]);
    XCTAssertFalse([self.manager isAdminEndpoint:@"com.atproto.server.createInviteCode"]);
    XCTAssertFalse([self.manager isAdminEndpoint:@"com.atproto.server.createInviteCodes"]);
    XCTAssertFalse([self.manager isAdminEndpoint:@"com.atproto.repo.getRecord"]);
}

- (void)testValidateWriteAccessRejectsInvalidRkey {
    NSError *error = nil;
    BOOL allowed = [self.manager validateWriteAccess:@"did:plc:writer"
                                       forCollection:@"app.bsky.feed.post"
                                                rkey:@"../bad"
                                            actorDID:@"did:plc:writer"
                                               error:&error];
    XCTAssertFalse(allowed);
    XCTAssertEqual(error.code, PDSAuthzErrorUnauthorized);
}

- (void)testValidateReadAccessMutedCollection {
    NSError *error = nil;
    [self createAccountWithDid:@"did:plc:mute123" handle:@"mute.example.com"];

    error = nil;
    BOOL allowed = [self.manager validateReadAccess:@"did:plc:mute123"
                                      forCollection:@"app.bsky.feed.post"
                                           actorDID:@"did:plc:mute123"
                                              error:&error];
    XCTAssertFalse(allowed);
}

@end

NS_ASSUME_NONNULL_END
