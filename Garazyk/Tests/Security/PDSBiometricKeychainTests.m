// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>

// PDSBiometricKeychain requires the macOS Security framework.
// Tests that go through the keychain are guarded to handle
// entitlement restrictions in the test runner (errSecMissingEntitlement).
#if TARGET_OS_OSX
#import "Security/PDSBiometricKeychain.h"

@interface PDSBiometricKeychainTests : XCTestCase
@property (nonatomic, strong) PDSBiometricKeychain *keychain;
@property (nonatomic, copy) NSString *testServiceName;
@property (nonatomic, assign) BOOL keychainAvailable;
@end

@implementation PDSBiometricKeychainTests

- (void)setUp {
    [super setUp];
    self.testServiceName = @"com.garazyk.tests.biometrickit";
    self.keychain = [[PDSBiometricKeychain alloc] initWithServiceName:self.testServiceName
                                                          accessGroup:nil
                                                        useBiometrics:NO];

    // Probe whether keychain is accessible (test runner may lack entitlements)
    NSData *probe = [@"probe" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *storeError = nil;
    BOOL stored = [self.keychain storeKey:probe forAccount:@"__probe__" error:&storeError];
    if (stored) {
        [self.keychain deleteKeyForAccount:@"__probe__" error:nil];
        self.keychainAvailable = YES;
    } else if (storeError.code == PDSBiometricKeychainErrorAuthFailed) {
        // errSecMissingEntitlement (-67694) maps to AuthFailed — keychain not available
        self.keychainAvailable = NO;
    } else {
        self.keychainAvailable = NO;
    }
}

#pragma mark - Init

- (void)testInit_ValidParameters_ReturnsInstance {
    PDSBiometricKeychain *kc = [[PDSBiometricKeychain alloc] initWithServiceName:@"com.test"
                                                                     accessGroup:nil
                                                                   useBiometrics:NO];
    XCTAssertNotNil(kc);
    XCTAssertEqualObjects(kc.serviceName, @"com.test");
    XCTAssertNil(kc.accessGroup);
    XCTAssertFalse(kc.useBiometrics);
}

- (void)testInit_WithAccessGroup_SetsGroup {
    PDSBiometricKeychain *kc = [[PDSBiometricKeychain alloc] initWithServiceName:@"com.test"
                                                                     accessGroup:@"com.test.group"
                                                                   useBiometrics:YES];
    XCTAssertNotNil(kc);
    XCTAssertEqualObjects(kc.accessGroup, @"com.test.group");
    XCTAssertTrue(kc.useBiometrics);
}

- (void)testSharedInstance_ReturnsSingleton {
    PDSBiometricKeychain *instance1 = [PDSBiometricKeychain sharedInstance];
    PDSBiometricKeychain *instance2 = [PDSBiometricKeychain sharedInstance];
    XCTAssertEqual(instance1, instance2);
    XCTAssertNotNil(instance1);
}

#pragma mark - Store / Retrieve / Delete

- (void)testStoreAndRetrieve_Succeeds {
    if (!self.keychainAvailable) {
        XCTSkip(@"Keychain not available in test environment (missing entitlement)");
    }

    NSData *keyData = [@"test-key-data" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *account = @"test-account-1";

    NSError *storeError = nil;
    BOOL stored = [self.keychain storeKey:keyData forAccount:account error:&storeError];
    XCTAssertTrue(stored);
    XCTAssertNil(storeError);

    NSError *retrieveError = nil;
    NSData *retrieved = [self.keychain retrieveKeyForAccount:account error:&retrieveError];
    XCTAssertNotNil(retrieved);
    XCTAssertEqualObjects(retrieved, keyData);
    XCTAssertNil(retrieveError);
}

- (void)testStore_NilKeyData_ReturnsError {
    NSError *error = nil;
    BOOL stored = [self.keychain storeKey:nil forAccount:@"test-account" error:&error];
    XCTAssertFalse(stored);
    XCTAssertNotNil(error);
}

- (void)testStore_EmptyKeyData_ReturnsError {
    NSError *error = nil;
    BOOL stored = [self.keychain storeKey:[NSData data] forAccount:@"test-account" error:&error];
    XCTAssertFalse(stored);
    XCTAssertNotNil(error);
}

- (void)testRetrieve_NonExistentAccount_ReturnsNilError {
    NSError *error = nil;
    NSData *retrieved = [self.keychain retrieveKeyForAccount:@"non-existent-account"
                                                       error:&error];
    XCTAssertNil(retrieved);
    // On a platform without keychain entitlement, this also fails
    if (!self.keychainAvailable && error.code == PDSBiometricKeychainErrorAuthFailed) {
        return; // Acceptable — entitlement missing
    }
    XCTAssertNotNil(error);
}

- (void)testDelete_ExistingKey_Succeeds {
    if (!self.keychainAvailable) {
        XCTSkip(@"Keychain not available in test environment");
    }

    NSData *keyData = [@"delete-test" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *account = @"delete-account";

    [self.keychain storeKey:keyData forAccount:account error:nil];

    NSError *deleteError = nil;
    BOOL deleted = [self.keychain deleteKeyForAccount:account error:&deleteError];
    XCTAssertTrue(deleted);
    XCTAssertNil(deleteError);
}

- (void)testDelete_NonExistentKey_HandlesGracefully {
    NSError *error = nil;
    BOOL deleted = [self.keychain deleteKeyForAccount:@"never-stored" error:&error];
    // errSecItemNotFound or errSecSuccess are both acceptable
    if (error) {
        // If keychain is not available, error is expected
        if (!self.keychainAvailable && error.code == PDSBiometricKeychainErrorAuthFailed) {
            return;
        }
        XCTAssertEqual(error.code, PDSBiometricKeychainErrorKeyNotFound);
    } else {
        XCTAssertTrue(deleted);
    }
}

- (void)testKeyExists_AfterStore_ReturnsYES {
    if (!self.keychainAvailable) {
        XCTSkip(@"Keychain not available in test environment");
    }

    NSData *keyData = [@"exists-test" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *account = @"exists-account";

    [self.keychain storeKey:keyData forAccount:account error:nil];

    BOOL exists = [self.keychain keyExistsForAccount:account];
    XCTAssertTrue(exists);
}

- (void)testKeyExists_NonExistent_ReturnsNO {
    BOOL exists = [self.keychain keyExistsForAccount:@"non-existent"];
    XCTAssertFalse(exists);
}

- (void)testKeyExists_AfterDelete_ReturnsNO {
    if (!self.keychainAvailable) {
        XCTSkip(@"Keychain not available in test environment");
    }

    NSData *keyData = [@"gone-test" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *account = @"gone-account";

    [self.keychain storeKey:keyData forAccount:account error:nil];
    [self.keychain deleteKeyForAccount:account error:nil];

    BOOL exists = [self.keychain keyExistsForAccount:account];
    XCTAssertFalse(exists);
}

- (void)testStoreOverwrite_ExistingKey_UpdatesValue {
    if (!self.keychainAvailable) {
        XCTSkip(@"Keychain not available in test environment");
    }

    NSString *account = @"overwrite-account";

    [self.keychain storeKey:[@"original" dataUsingEncoding:NSUTF8StringEncoding]
                 forAccount:account error:nil];

    [self.keychain storeKey:[@"updated" dataUsingEncoding:NSUTF8StringEncoding]
                 forAccount:account error:nil];

    NSError *error = nil;
    NSData *retrieved = [self.keychain retrieveKeyForAccount:account error:&error];
    XCTAssertNotNil(retrieved);
    NSString *retrievedStr = [[NSString alloc] initWithData:retrieved encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(retrievedStr, @"updated");
}

#pragma mark - Upgrade

- (void)testUpgradeExistingKeys_EmptyAccounts_ReturnsYES {
    BOOL upgraded = [self.keychain upgradeExistingKeysWithAccounts:@[] error:nil];
    XCTAssertTrue(upgraded);
}

#pragma mark - Biometry (no-crash checks)

- (void)testIsBiometryAvailable_DoesNotCrash {
    BOOL available = [self.keychain isBiometryAvailable];
    // Just verify the method returns a value without crashing.
    // The actual value depends on the test machine's hardware.
    XCTAssertNoThrow([self.keychain isBiometryAvailable]);
}

- (void)testBiometryTypeString_DoesNotCrash {
    NSString *type = [self.keychain biometryTypeString];
    XCTAssertNotNil(type);
    XCTAssertTrue([type isKindOfClass:[NSString class]]);
}

- (void)testCreateAuthenticationContext_ReturnsContextOrNil {
    NSError *error = nil;
    LAContext *context = [self.keychain createAuthenticationContextWithError:&error];
    if (!context) {
        XCTAssertNotNil(error);
    } else {
        XCTAssertNil(error);
        XCTAssertTrue([context isKindOfClass:[LAContext class]]);
    }
}

- (void)testCreateAuthenticationContext_NilError_DoesNotCrash {
    LAContext *context = [self.keychain createAuthenticationContextWithError:nil];
    if (context) {
        XCTAssertTrue([context isKindOfClass:[LAContext class]]);
    }
}

@end

#else
// Non-macOS platform: provide empty test class that passes
@interface PDSBiometricKeychainTests : XCTestCase
@end

@implementation PDSBiometricKeychainTests

- (void)testBiometricKeychainUnavailableOnThisPlatform {
    XCTSkip(@"PDSBiometricKeychain requires macOS Security framework");
}

@end
#endif
