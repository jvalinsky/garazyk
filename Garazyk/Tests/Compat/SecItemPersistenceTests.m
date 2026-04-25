#import <XCTest/XCTest.h>
#import "Compat/PlatformShims/Security/SecItemLinuxStore.h"

@interface SecItemPersistenceTests : XCTestCase
@property (nonatomic, strong) SecItemLinuxStore *store;
@property (nonatomic, strong) NSString *testDBPath;
@end

@implementation SecItemPersistenceTests

- (void)setUp {
    [super setUp];
#ifdef __APPLE__
    // SecItemLinuxStore is a Linux compat shim; on macOS the real
    // Security.framework SecItem* APIs are used instead.  The Linux
    // store uses global dispatch_once state that cannot be reset
    // between test runs, causing hangs on macOS.  Skip on Apple
    // platforms.
    XCTSkip(@"SecItemLinuxStore is a Linux-only compat shim");
#endif
    NSString *tempDir = NSTemporaryDirectory();
    self.testDBPath = [tempDir stringByAppendingPathComponent:@"test_keychain.db"];
    [[NSFileManager defaultManager] removeItemAtPath:self.testDBPath error:nil];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.testDBPath error:nil];
    self.store = nil;
    [super tearDown];
}

- (void)testAddAndRetrieveItem {
    SecItemLinuxStore *store = [[SecItemLinuxStore alloc] init];
    NSData *testData = [@"secret" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *attributes = @{
        (id)kSecValueData: testData,
        @"custom": @"value"
    };

    NSError *error = nil;
    BOOL success = [store addItemWithService:@"com.test"
                                    account:@"user"
                                 attributes:attributes
                                      error:&error];
    XCTAssertTrue(success);
    XCTAssertNil(error);

    NSDictionary *retrieved = [store itemWithService:@"com.test"
                                             account:@"user"
                                               error:&error];
    XCTAssertNotNil(retrieved);
    XCTAssertNil(error);
    XCTAssertEqualObjects(retrieved[(id)kSecValueData], testData);
    XCTAssertEqualObjects(retrieved[@"custom"], @"value");
}

- (void)testDuplicateItemReturnsError {
    SecItemLinuxStore *store = [[SecItemLinuxStore alloc] init];
    NSData *testData = [@"secret" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *attributes = @{(id)kSecValueData: testData};

    NSError *error1 = nil;
    BOOL success1 = [store addItemWithService:@"com.test"
                                     account:@"user"
                                  attributes:attributes
                                       error:&error1];
    XCTAssertTrue(success1);

    NSError *error2 = nil;
    BOOL success2 = [store addItemWithService:@"com.test"
                                     account:@"user"
                                  attributes:attributes
                                       error:&error2];
    XCTAssertFalse(success2);
    XCTAssertNotNil(error2);
}

- (void)testUpdateMergesAttributes {
    SecItemLinuxStore *store = [[SecItemLinuxStore alloc] init];
    NSData *originalData = [@"secret1" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *updatedData = [@"secret2" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *attributes = @{(id)kSecValueData: originalData};

    NSError *error = nil;
    [store addItemWithService:@"com.test"
                     account:@"user"
                  attributes:attributes
                       error:&error];

    NSDictionary *toUpdate = @{(id)kSecValueData: updatedData};
    BOOL updated = [store updateItemWithService:@"com.test"
                                       account:@"user"
                             attributesToUpdate:toUpdate
                                         error:&error];
    XCTAssertTrue(updated);

    NSDictionary *retrieved = [store itemWithService:@"com.test"
                                             account:@"user"
                                               error:&error];
    XCTAssertEqualObjects(retrieved[(id)kSecValueData], updatedData);
}

- (void)testDeleteRemovesItem {
    SecItemLinuxStore *store = [[SecItemLinuxStore alloc] init];
    NSData *testData = [@"secret" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *attributes = @{(id)kSecValueData: testData};

    NSError *error = nil;
    [store addItemWithService:@"com.test"
                     account:@"user"
                  attributes:attributes
                       error:&error];

    BOOL deleted = [store deleteItemWithService:@"com.test"
                                       account:@"user"
                                         error:&error];
    XCTAssertTrue(deleted);

    NSDictionary *retrieved = [store itemWithService:@"com.test"
                                             account:@"user"
                                               error:&error];
    XCTAssertNil(retrieved);
}

- (void)testDeleteNonExistentItemReturnsNotFound {
    SecItemLinuxStore *store = [[SecItemLinuxStore alloc] init];

    NSError *error = nil;
    BOOL deleted = [store deleteItemWithService:@"com.nonexistent"
                                       account:@"missing"
                                         error:&error];
    XCTAssertFalse(deleted);
    XCTAssertNotNil(error);
}

- (void)testMissingServiceReturnsParamError {
    SecItemLinuxStore *store = [[SecItemLinuxStore alloc] init];
    NSData *testData = [@"secret" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *attributes = @{(id)kSecValueData: testData};

    NSError *error = nil;
    BOOL success = [store addItemWithService:nil
                                    account:@"user"
                                 attributes:attributes
                                      error:&error];
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
}

- (void)testPersistenceAcrossStoreInstances {
    SecItemLinuxStore *storeA = [[SecItemLinuxStore alloc] init];
    NSData *testData = [@"secret" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *attributes = @{(id)kSecValueData: testData};

    NSError *error = nil;
    [storeA addItemWithService:@"com.test"
                      account:@"user"
                   attributes:attributes
                        error:&error];

    SecItemLinuxStore *storeB = [[SecItemLinuxStore alloc] init];
    NSDictionary *retrieved = [storeB itemWithService:@"com.test"
                                              account:@"user"
                                                error:&error];
    XCTAssertNotNil(retrieved);
    XCTAssertEqualObjects(retrieved[(id)kSecValueData], testData);
}

@end
