// Tests for PDSKeyManagerFactory: platform dispatch and interface compliance.

#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif

#import "Auth/PDSKeyManagerFactory.h"
#import "Auth/PDSKeyManagerProtocol.h"
#import "Database/PDSDatabase.h"

@interface PDSKeyManagerFactoryTests : XCTestCase
@property (nonatomic, strong) PDSDatabase *db;
@property (nonatomic, copy) NSString *dbPath;
@end

@implementation PDSKeyManagerFactoryTests

- (void)setUp {
    [super setUp];
    NSString *uuid = [[NSUUID UUID] UUIDString];
    self.dbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                   [NSString stringWithFormat:@"keymgr_factory_%@.db", uuid]];
    NSURL *url = [NSURL fileURLWithPath:self.dbPath];
    self.db = [PDSDatabase databaseAtURL:url];
    NSError *error = nil;
    BOOL opened = [self.db openWithError:&error];
    XCTAssertTrue(opened, @"Database must open: %@", error);
}

- (void)tearDown {
    [self.db close];
    [[NSFileManager defaultManager] removeItemAtPath:self.dbPath error:nil];
    [super tearDown];
}

#pragma mark - Factory

- (void)testFactoryReturnsNonNilKeyManager {
    id<PDSKeyManager> manager = [PDSKeyManagerFactory createKeyManagerWithDatabase:self.db];
    XCTAssertNotNil(manager, @"Factory must return a non-nil key manager");
}

- (void)testFactoryReturnsObjectConformingToProtocol {
    id<PDSKeyManager> manager = [PDSKeyManagerFactory createKeyManagerWithDatabase:self.db];
    XCTAssertTrue([manager conformsToProtocol:@protocol(PDSKeyManager)],
                  @"Returned object must conform to PDSKeyManager protocol");
}

- (void)testKeyManagerCanGenerateKeyPair {
    id<PDSKeyManager> manager = [PDSKeyManagerFactory createKeyManagerWithDatabase:self.db];
    NSError *error = nil;
    id<PDSKeyPair> keyPair = [manager generateKeyPairWithAlgorithm:@"ES256"
                                                           keySize:256
                                                             error:&error];
    XCTAssertNotNil(keyPair, @"generateKeyPairWithAlgorithm: must succeed: %@", error);
}

- (void)testKeyManagerCurrentKeyIDSetAfterGeneration {
    id<PDSKeyManager> manager = [PDSKeyManagerFactory createKeyManagerWithDatabase:self.db];
    NSError *error = nil;
    [manager generateKeyPairWithAlgorithm:@"ES256" keySize:256 error:&error];
    XCTAssertNotNil(manager.currentKeyID, @"currentKeyID must be set after key generation");
}

- (void)testFactoryCanBeCalledMultipleTimes {
    id<PDSKeyManager> m1 = [PDSKeyManagerFactory createKeyManagerWithDatabase:self.db];
    id<PDSKeyManager> m2 = [PDSKeyManagerFactory createKeyManagerWithDatabase:self.db];
    XCTAssertNotNil(m1);
    XCTAssertNotNil(m2);
}

@end
