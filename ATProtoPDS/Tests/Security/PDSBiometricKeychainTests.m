// Tests for PDSBiometricKeychain: Keychain-backed key storage with optional biometrics.
// These tests run only on Apple platforms and do not require actual biometrics hardware;
// they exercise the no-biometrics code path using a unique test service name to avoid
// polluting the real keychain.

#ifdef __APPLE__
#import <XCTest/XCTest.h>
#import "Security/PDSBiometricKeychain.h"

@interface PDSBiometricKeychainTests : XCTestCase
@property (nonatomic, strong) PDSBiometricKeychain *keychain;
@property (nonatomic, copy) NSString *servicePrefix;
@end

@implementation PDSBiometricKeychainTests

- (void)setUp {
    [super setUp];
    // Use a unique service name per test run to avoid cross-test interference.
    self.servicePrefix = [NSString stringWithFormat:@"com.test.biometric.%@", [[NSUUID UUID] UUIDString]];
    self.keychain = [[PDSBiometricKeychain alloc] initWithServiceName:self.servicePrefix
                                                          accessGroup:nil
                                                        useBiometrics:NO];
}

- (void)tearDown {
    // Clean up any keychain items written during the test.
    NSArray<NSString *> *testAccounts = @[@"account-A", @"account-B", @"account-C",
                                          @"account-dup", @"account-del"];
    for (NSString *account in testAccounts) {
        [self.keychain deleteKeyForAccount:account error:nil];
    }
    [super tearDown];
}

- (NSData *)testKeyData {
    NSMutableData *key = [NSMutableData dataWithLength:32];
    uint8_t *bytes = key.mutableBytes;
    for (NSUInteger i = 0; i < 32; i++) bytes[i] = (uint8_t)(i + 1);
    return key;
}

#pragma mark - Basic Store / Retrieve

- (void)testStoreAndRetrieveKeyNoBiometrics {
    NSData *key = [self testKeyData];
    NSError *error = nil;
    BOOL stored = [self.keychain storeKey:key forAccount:@"account-A" error:&error];
    XCTAssertTrue(stored, @"storeKey:forAccount:error: must succeed: %@", error);
    XCTAssertNil(error);

    NSData *retrieved = [self.keychain retrieveKeyForAccount:@"account-A" error:&error];
    XCTAssertNotNil(retrieved, @"Retrieved key must not be nil: %@", error);
    XCTAssertEqualObjects(retrieved, key, @"Retrieved key must equal stored key");
}

- (void)testStoreKeyUpdateAtomic {
    NSData *first  = [@"first-key-data-32bytes-xxxxxxxxxx" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *second = [@"second-key-data-32bytes-xxxxxxxxx" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;

    XCTAssertTrue([self.keychain storeKey:first  forAccount:@"account-dup" error:&error]);
    XCTAssertTrue([self.keychain storeKey:second forAccount:@"account-dup" error:&error],
                  @"Updating an existing key via SecItemUpdate must succeed: %@", error);

    NSData *retrieved = [self.keychain retrieveKeyForAccount:@"account-dup" error:&error];
    XCTAssertEqualObjects(retrieved, second, @"Retrieved value must be the updated key");
}

#pragma mark - Delete

- (void)testDeleteKeySucceeds {
    NSError *error = nil;
    XCTAssertTrue([self.keychain storeKey:[self testKeyData] forAccount:@"account-del" error:&error]);

    BOOL deleted = [self.keychain deleteKeyForAccount:@"account-del" error:&error];
    XCTAssertTrue(deleted, @"deleteKeyForAccount:error: must succeed: %@", error);

    NSData *afterDelete = [self.keychain retrieveKeyForAccount:@"account-del" error:nil];
    XCTAssertNil(afterDelete, @"Key must be gone after deletion");
}

#pragma mark - Existence Check

- (void)testKeyExistsReturnsFalseForMissingKey {
    BOOL exists = [self.keychain keyExistsForAccount:@"no-such-account-xyz"];
    XCTAssertFalse(exists);
}

- (void)testKeyExistsReturnsTrueAfterStore {
    NSError *error = nil;
    XCTAssertTrue([self.keychain storeKey:[self testKeyData] forAccount:@"account-B" error:&error]);
    BOOL exists = [self.keychain keyExistsForAccount:@"account-B"];
    XCTAssertTrue(exists);
}

- (void)testKeyExistsReturnsFalseAfterDelete {
    NSError *error = nil;
    XCTAssertTrue([self.keychain storeKey:[self testKeyData] forAccount:@"account-C" error:&error]);
    XCTAssertTrue([self.keychain deleteKeyForAccount:@"account-C" error:&error]);
    BOOL exists = [self.keychain keyExistsForAccount:@"account-C"];
    XCTAssertFalse(exists);
}

#pragma mark - Upgrade

- (void)testUpgradeExistingKeysEmptyAccountsNoOp {
    NSError *error = nil;
    BOOL ok = [self.keychain upgradeExistingKeysWithAccounts:@[] error:&error];
    XCTAssertTrue(ok, @"Upgrade with empty account list must succeed: %@", error);
}

#pragma mark - Biometry Info

- (void)testBiometryAvailabilityDoesNotCrash {
    // Just ensure no crash; result depends on device capabilities.
    (void)[self.keychain isBiometryAvailable];
    (void)[self.keychain biometryTypeString];
}

@end
#endif // __APPLE__
