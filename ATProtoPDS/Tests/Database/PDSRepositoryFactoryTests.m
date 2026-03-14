// Tests for PDSRepositoryFactory: returns protocol-conforming repository instances.

#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif

#import "Database/PDSRepositoryFactory.h"
#import "Core/Repositories/PDSAccountRepository.h"
#import "Core/Repositories/PDSSessionRepository.h"
#import "Database/Service/ServiceDatabases.h"

@interface PDSRepositoryFactoryTests : XCTestCase
@property (nonatomic, strong) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, copy) NSString *testDirectory;
@end

@implementation PDSRepositoryFactoryTests

- (void)setUp {
    [super setUp];
    NSString *uuid = [[NSUUID UUID] UUIDString];
    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"repo_factory_%@", uuid]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    self.serviceDatabases = [[PDSServiceDatabases alloc] initWithDirectory:self.testDirectory
                                                               maxPoolSize:2];
}

- (void)tearDown {
    [self.serviceDatabases closeAll];
    [[NSFileManager defaultManager] removeItemAtPath:self.testDirectory error:nil];
    [super tearDown];
}

#pragma mark - Account repository

- (void)testAccountRepositoryIsNonNil {
    id<PDSAccountRepository> repo = [PDSRepositoryFactory
                                     accountRepositoryWithServiceDatabases:self.serviceDatabases];
    XCTAssertNotNil(repo, @"accountRepository must not be nil");
}

- (void)testAccountRepositoryConformsToProtocol {
    id<PDSAccountRepository> repo = [PDSRepositoryFactory
                                     accountRepositoryWithServiceDatabases:self.serviceDatabases];
    XCTAssertTrue([repo conformsToProtocol:@protocol(PDSAccountRepository)],
                  @"Returned object must conform to PDSAccountRepository");
}

#pragma mark - Session repository

- (void)testSessionRepositoryIsNonNil {
    id<PDSSessionRepository> repo = [PDSRepositoryFactory
                                     sessionRepositoryWithServiceDatabases:self.serviceDatabases];
    XCTAssertNotNil(repo, @"sessionRepository must not be nil");
}

- (void)testSessionRepositoryConformsToProtocol {
    id<PDSSessionRepository> repo = [PDSRepositoryFactory
                                     sessionRepositoryWithServiceDatabases:self.serviceDatabases];
    XCTAssertTrue([repo conformsToProtocol:@protocol(PDSSessionRepository)],
                  @"Returned object must conform to PDSSessionRepository");
}

#pragma mark - Multiple calls

- (void)testFactoryCanBeCalledMultipleTimes {
    id<PDSAccountRepository> r1 = [PDSRepositoryFactory
                                   accountRepositoryWithServiceDatabases:self.serviceDatabases];
    id<PDSAccountRepository> r2 = [PDSRepositoryFactory
                                   accountRepositoryWithServiceDatabases:self.serviceDatabases];
    XCTAssertNotNil(r1);
    XCTAssertNotNil(r2);
}

@end
