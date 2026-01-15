#import <XCTest/XCTest.h>
#import "App/Services/PDSAccountService.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/Service/ServiceDatabases.h"

@interface PDSAccountServiceTests : XCTestCase
@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) PDSDatabasePool *pool;
@property (nonatomic, strong) PDSAccountService *service;
@end

@implementation PDSAccountServiceTests

- (void)setUp {
    [super setUp];
    
    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    
    self.pool = [[PDSDatabasePool alloc] initWithDbDirectory:self.testDirectory maxSize:5];
    self.service = [[PDSAccountService alloc] initWithDatabasePool:self.pool];
    
    self.service.serviceDatabases = [[PDSServiceDatabases alloc] initWithDirectory:self.testDirectory
                                                                   serviceMaxSize:1024*1024
                                                                 didCacheMaxSize:1000
                                                               sequencerMaxSize:100];
}

- (void)tearDown {
    [self.pool closeAll];
    self.pool = nil;
    self.service = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.testDirectory error:nil];
    [super tearDown];
}

- (void)testCreateAccount {
    NSError *error = nil;
    NSDictionary *result = [self.service createAccountForEmail:@"test@example.com"
                                                      password:@"password123"
                                                        handle:@"test.example.com"
                                                           did:nil // Let it generate
                                                         error:&error];
    
    XCTAssertNotNil(result);
    XCTAssertNil(error);
    XCTAssertNotNil(result[@"did"]);
    XCTAssertEqualObjects(result[@"handle"], @"test.example.com");
    XCTAssertEqualObjects(result[@"email"], @"test@example.com");
}

- (void)testCreateAccountDuplicate {
    NSError *error = nil;
    [self.service createAccountForEmail:@"dup@example.com"
                               password:@"password123"
                                 handle:@"dup.example.com"
                                    did:nil
                                  error:&error];
    
    error = nil;
    NSDictionary *dupResult = [self.service createAccountForEmail:@"dup@example.com"
                                                         password:@"password456"
                                                           handle:@"dup.example.com"
                                                              did:nil
                                                            error:&error];
    XCTAssertNil(dupResult);
    XCTAssertNotNil(error);
}

- (void)testLogin {
    [self.service createAccountForEmail:@"login@example.com"
                               password:@"correctHash"
                                 handle:@"login.example.com"
                                    did:nil
                                  error:nil];

    NSError *error = nil;
    NSDictionary *session = [self.service loginWithHandle:@"login.example.com"
                                                 password:@"correctHash"
                                                    error:&error];
    XCTAssertNotNil(session);
    XCTAssertNil(error);
    XCTAssertNotNil(session[@"accessJwt"]);
    XCTAssertNotNil(session[@"refreshJwt"]);
}

- (void)testLoginInvalidPassword {
    [self.service createAccountForEmail:@"fail@example.com"
                               password:@"correctHash"
                                 handle:@"fail.example.com"
                                    did:nil
                                  error:nil];

    NSError *error = nil;
    NSDictionary *session = [self.service loginWithHandle:@"fail.example.com"
                                                 password:@"wrongPassword"
                                                    error:&error];
    XCTAssertNil(session);
    XCTAssertNotNil(error);
}

@end
