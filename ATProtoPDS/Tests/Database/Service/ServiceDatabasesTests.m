#import <XCTest/XCTest.h>
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"

@interface ServiceDatabasesTests : XCTestCase

@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) PDSServiceDatabases *serviceDatabases;

@end

@implementation ServiceDatabasesTests

- (void)setUp {
    [super setUp];
    
    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ServiceDatabasesTests"];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:self.testDirectory error:nil];
    [fm createDirectoryAtPath:self.testDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    
    self.serviceDatabases = [[PDSServiceDatabases alloc] initWithDirectory:self.testDirectory
                                                            serviceMaxSize:10
                                                          didCacheMaxSize:10
                                                        sequencerMaxSize:10];
}

- (void)tearDown {
    [self.serviceDatabases closeAll];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:self.testDirectory error:nil];
    
    [super tearDown];
}

- (void)testServiceDatabasesInitialization {
    XCTAssertNotNil(self.serviceDatabases);
    XCTAssertNotNil(self.serviceDatabases.servicePool);
    XCTAssertNotNil(self.serviceDatabases.didCachePool);
    XCTAssertNotNil(self.serviceDatabases.sequencerPool);
}

- (void)testAccountCreation {
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = @"did:plc:service_test";
    account.handle = @"service.test";
    account.email = @"service@test.com";
    account.passwordHash = [@"hash" dataUsingEncoding:NSUTF8StringEncoding];
    account.passwordSalt = [@"salt" dataUsingEncoding:NSUTF8StringEncoding];
    account.createdAt = [[NSDate date] timeIntervalSince1970];
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    
    NSError *error = nil;
    BOOL success = [self.serviceDatabases createAccount:account error:&error];
    XCTAssertTrue(success, @"Create account failed: %@", error);
    
    PDSDatabaseAccount *fetched = [self.serviceDatabases getAccountByDid:account.did error:&error];
    XCTAssertNotNil(fetched, @"Get account failed: %@", error);
    XCTAssertEqualObjects(fetched.did, account.did);
    XCTAssertEqualObjects(fetched.handle, account.handle);
}

- (void)testAccountByHandle {
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = @"did:plc:handle_test";
    account.handle = @"handle.test";
    account.createdAt = [[NSDate date] timeIntervalSince1970];
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    
    NSError *error = nil;
    XCTAssertTrue([self.serviceDatabases createAccount:account error:&error], @"Create failed: %@", error);
    
    PDSDatabaseAccount *fetched = [self.serviceDatabases getAccountByHandle:@"handle.test" error:&error];
    XCTAssertNotNil(fetched, @"Get by handle failed: %@", error);
    XCTAssertEqualObjects(fetched.did, @"did:plc:handle_test");
}

- (void)testInviteCodeOperations {
    NSError *error = nil;
    NSString *did = @"did:plc:invite_test";
    NSString *code = @"TEST-INVITE-CODE-123";
    
    BOOL success = [self.serviceDatabases createInviteCode:code forAccount:did maxUses:5 error:&error];
    XCTAssertTrue(success, @"Create invite failed: %@", error);
    
    NSString *fetchedCode = [self.serviceDatabases getInviteCodeForAccount:did error:&error];
    XCTAssertEqualObjects(fetchedCode, code, @"Invite code should match");
    
    success = [self.serviceDatabases useInviteCode:code error:&error];
    XCTAssertTrue(success, @"Use invite failed: %@", error);
}

- (void)testDIDCaching {
    NSString *did = @"did:plc:cache_test";
    NSDictionary *document = @{@"@context": @"https://www.w3.org/ns/did/v1", @"id": did};
    NSDate *expiresAt = [NSDate dateWithTimeIntervalSinceNow:3600];
    
    [self.serviceDatabases cacheDID:did document:document expiresAt:expiresAt];
    
    NSDictionary *fetched = [self.serviceDatabases resolveDID:did];
    XCTAssertNotNil(fetched, @"Cached DID should be found");
    XCTAssertEqualObjects(fetched[@"id"], did);
}

- (void)testDIDCachingExpiry {
    NSString *did = @"did:plc:expired_test";
    NSDictionary *document = @{@"id": did};
    NSDate *expiresAt = [NSDate dateWithTimeIntervalSinceNow:-1];
    
    [self.serviceDatabases cacheDID:did document:document expiresAt:expiresAt];
    
    NSDictionary *fetched = [self.serviceDatabases resolveDID:did];
    XCTAssertNil(fetched, @"Expired cache should return nil");
}

- (void)testAccountUpdate {
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = @"did:plc:update_test";
    account.handle = @"update.test";
    account.createdAt = [[NSDate date] timeIntervalSince1970];
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    
    NSError *error = nil;
    XCTAssertTrue([self.serviceDatabases createAccount:account error:&error], @"Create failed: %@", error);
    
    account.email = @"updated@test.com";
    XCTAssertTrue([self.serviceDatabases updateAccount:account error:&error], @"Update failed: %@", error);
    
    PDSDatabaseAccount *fetched = [self.serviceDatabases getAccountByDid:account.did error:&error];
    XCTAssertEqualObjects(fetched.email, @"updated@test.com");
}

- (void)testAccountDeletion {
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = @"did:plc:delete_test";
    account.handle = @"delete.test";
    account.createdAt = [[NSDate date] timeIntervalSince1970];
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    
    NSError *error = nil;
    XCTAssertTrue([self.serviceDatabases createAccount:account error:&error], @"Create failed: %@", error);
    
    BOOL success = [self.serviceDatabases deleteAccount:account.did error:&error];
    XCTAssertTrue(success, @"Delete failed: %@", error);
    
    PDSDatabaseAccount *fetched = [self.serviceDatabases getAccountByDid:account.did error:&error];
    XCTAssertNil(fetched, @"Account should be deleted");
}

- (void)testCloseAll {
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = @"did:plc:close_test";
    account.handle = @"close.test";
    account.createdAt = [[NSDate date] timeIntervalSince1970];
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    
    NSError *error = nil;
    XCTAssertTrue([self.serviceDatabases createAccount:account error:&error], @"Create failed: %@", error);
    
    [self.serviceDatabases closeAll];
    
    XCTAssertNoThrow([self.serviceDatabases createAccount:account error:&error], @"Should be able to recreate after close");
}

@end
