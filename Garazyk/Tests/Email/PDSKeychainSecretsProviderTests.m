#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif
#import "Email/PDSKeychainSecretsProvider.h"

@interface PDSKeychainSecretsProviderTests : XCTestCase

@property (nonatomic, strong) PDSKeychainSecretsProvider *provider;
@property (nonatomic, copy) NSString *testService;
@property (nonatomic, assign) BOOL keychainWritable;

@end

@implementation PDSKeychainSecretsProviderTests

- (void)setUp {
    [super setUp];
    
    self.testService = [NSString stringWithFormat:@"com.atproto.pds.email.test.%@", [[NSUUID UUID] UUIDString]];
    self.provider = [[PDSKeychainSecretsProvider alloc] initWithService:self.testService];
    self.keychainWritable = [self probeKeychainWritable];
    
    [self cleanupAllTestData];
}

- (void)tearDown {
    [self cleanupAllTestData];
    
    [super tearDown];
}

- (BOOL)probeKeychainWritable {
    NSString *key = [NSString stringWithFormat:@"probe_%@", [[NSUUID UUID] UUIDString]];
    NSError *storeError = nil;
    BOOL stored = [self.provider storeSecret:@"probe" forKey:key error:&storeError];
    if (!stored) {
        return NO;
    }

    NSError *deleteError = nil;
    (void)[self.provider deleteSecretForKey:key error:&deleteError];
    return YES;
}

- (void)cleanupAllTestData {
    NSArray *testKeys = @[
        @"test_init_key",
        @"test_store_key",
        @"test_retrieve_key",
        @"test_nonexistent_key",
        @"test_delete_key",
        @"test_update_key"
    ];
    
    for (NSString *key in testKeys) {
        [self.provider deleteSecretForKey:key error:NULL];
    }
}

- (void)testInitWithServiceSetsService {
    NSString *customService = @"com.example.custom.service";
    PDSKeychainSecretsProvider *provider = [[PDSKeychainSecretsProvider alloc] initWithService:customService];
    
    XCTAssertNotNil(provider);
    XCTAssertEqualObjects(provider.service, customService);
}

- (void)testInitDefaultServiceSetsDefaultService {
    PDSKeychainSecretsProvider *provider = [[PDSKeychainSecretsProvider alloc] init];
    
    XCTAssertNotNil(provider);
    XCTAssertEqualObjects(provider.service, @"com.atproto.pds.email");
}

- (void)testStoreAndRetrieveSecret {
    NSString *testKey = @"test_store_key";
    NSString *testSecret = @"my_super_secret_api_key_12345";
    
    NSError *storeError = nil;
    BOOL stored = [self.provider storeSecret:testSecret forKey:testKey error:&storeError];
    
    if (!self.keychainWritable) {
        XCTAssertFalse(stored);
        XCTAssertNotNil(storeError);
        XCTAssertEqual(storeError.code, PDSKeychainSecretsProviderErrorStorageFailed);
        return;
    }

    XCTAssertTrue(stored, @"Secret should be stored successfully");
    XCTAssertNil(storeError, @"No error should occur during storage");
    
    NSError *retrieveError = nil;
    NSString *retrievedSecret = [self.provider secretForKey:testKey error:&retrieveError];
    
    XCTAssertNotNil(retrievedSecret, @"Retrieved secret should not be nil");
    XCTAssertNil(retrieveError, @"No error should occur during retrieval");
    XCTAssertEqualObjects(retrievedSecret, testSecret, @"Retrieved secret should match stored secret");
}

- (void)testRetrieveNonExistentSecret {
    NSString *nonExistentKey = [NSString stringWithFormat:@"test_nonexistent_key_%@", [[NSUUID UUID] UUIDString]];
    
    NSError *error = nil;
    NSString *secret = [self.provider secretForKey:nonExistentKey error:&error];
    
    XCTAssertNil(secret, @"Secret should be nil for non-existent key");
    XCTAssertNotNil(error, @"Error should be set for non-existent key");
    if (self.keychainWritable) {
        XCTAssertEqual(error.code, PDSKeychainSecretsProviderErrorItemNotFound, @"Error should be ItemNotFound");
    } else {
        XCTAssertEqual(error.code, PDSKeychainSecretsProviderErrorKeychainFailure, @"Unavailable keychain should report keychain failure");
    }
}

- (void)testSecretForKeyWithEmptyKey {
    NSError *error = nil;
    NSString *secret = [self.provider secretForKey:@"" error:&error];
    
    XCTAssertNil(secret, @"Secret should be nil for empty key");
    XCTAssertNotNil(error, @"Error should be set for empty key");
    XCTAssertEqual(error.code, PDSKeychainSecretsProviderErrorInvalidKey, @"Error should be InvalidKey");
}

- (void)testDeleteSecret {
    NSString *testKey = @"test_delete_key";
    NSString *testSecret = @"secret_to_delete_12345";
    
    NSError *storeError = nil;
    BOOL stored = [self.provider storeSecret:testSecret forKey:testKey error:&storeError];
    if (!self.keychainWritable) {
        XCTAssertFalse(stored);
        XCTAssertNotNil(storeError);
        XCTAssertEqual(storeError.code, PDSKeychainSecretsProviderErrorStorageFailed);

        // Delete of a non-existent item is idempotent per provider semantics:
        // errSecItemNotFound is treated as success (RESTful DELETE behavior).
        // This aligns with AT Protocol's idempotent design philosophy.
        NSError *deleteError = nil;
        BOOL deleted = [self.provider deleteSecretForKey:testKey error:&deleteError];
        XCTAssertTrue(deleted, @"Delete of non-existent item should succeed (idempotent)");
        XCTAssertNil(deleteError);
        return;
    }
    XCTAssertTrue(stored);
    XCTAssertNil(storeError, @"Setup: Secret should be stored");
    
    NSError *deleteError = nil;
    BOOL deleted = [self.provider deleteSecretForKey:testKey error:&deleteError];
    
    XCTAssertTrue(deleted, @"Delete should succeed");
    XCTAssertNil(deleteError, @"No error should occur during deletion");
    
    NSError *retrieveError = nil;
    NSString *retrievedSecret = [self.provider secretForKey:testKey error:&retrieveError];
    
    XCTAssertNil(retrievedSecret, @"Secret should be nil after deletion");
    XCTAssertNotNil(retrieveError, @"Error should be set after deletion");
    XCTAssertEqual(retrieveError.code, PDSKeychainSecretsProviderErrorItemNotFound, @"Error should be ItemNotFound after deletion");
}

- (void)testUpdateExistingSecret {
    NSString *testKey = @"test_update_key";
    NSString *originalSecret = @"original_secret_12345";
    NSString *updatedSecret = @"updated_secret_67890";
    
    NSError *storeError1 = nil;
    BOOL stored1 = [self.provider storeSecret:originalSecret forKey:testKey error:&storeError1];
    if (!self.keychainWritable) {
        XCTAssertFalse(stored1);
        XCTAssertNotNil(storeError1);
        XCTAssertEqual(storeError1.code, PDSKeychainSecretsProviderErrorStorageFailed);
        return;
    }

    XCTAssertTrue(stored1, @"Original secret should be stored");
    XCTAssertNil(storeError1);
    
    NSError *retrieveError1 = nil;
    NSString *retrieved1 = [self.provider secretForKey:testKey error:&retrieveError1];
    XCTAssertEqualObjects(retrieved1, originalSecret, @"Should retrieve original secret");
    
    NSError *storeError2 = nil;
    BOOL stored2 = [self.provider storeSecret:updatedSecret forKey:testKey error:&storeError2];
    XCTAssertTrue(stored2, @"Updated secret should be stored");
    XCTAssertNil(storeError2);
    
    NSError *retrieveError2 = nil;
    NSString *retrieved2 = [self.provider secretForKey:testKey error:&retrieveError2];
    XCTAssertEqualObjects(retrieved2, updatedSecret, @"Should retrieve updated secret, not original");
    XCTAssertNotEqualObjects(retrieved2, originalSecret, @"Retrieved secret should not be original");
}

- (void)testStoreSecretRejectsNilInputs {
    id nullObject = nil;
    NSError *error = nil;
    XCTAssertFalse([self.provider storeSecret:(NSString *)nullObject forKey:@"k" error:&error]);
    XCTAssertEqual(error.code, PDSKeychainSecretsProviderErrorInvalidInput);

    error = nil;
    XCTAssertFalse([self.provider storeSecret:@"v" forKey:(NSString *)nullObject error:&error]);
    XCTAssertEqual(error.code, PDSKeychainSecretsProviderErrorInvalidInput);
}

- (void)testStoreSecretRejectsEmptyKey {
    NSError *error = nil;
    XCTAssertFalse([self.provider storeSecret:@"v" forKey:@"" error:&error]);
    XCTAssertEqual(error.code, PDSKeychainSecretsProviderErrorInvalidInput);
}

- (void)testDeleteSecretRejectsEmptyKey {
    NSError *error = nil;
    XCTAssertFalse([self.provider deleteSecretForKey:@"" error:&error]);
    XCTAssertEqual(error.code, PDSKeychainSecretsProviderErrorInvalidKey);
}

@end
