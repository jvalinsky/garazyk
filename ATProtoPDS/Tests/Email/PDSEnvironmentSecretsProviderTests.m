#import <XCTest/XCTest.h>
#import "Email/PDSEnvironmentSecretsProvider.h"

@interface PDSEnvironmentSecretsProviderTests : XCTestCase

@end

@implementation PDSEnvironmentSecretsProviderTests

- (void)testInitWithPrefix {
    PDSEnvironmentSecretsProvider *provider = [[PDSEnvironmentSecretsProvider alloc] initWithPrefix:@"TEST_PREFIX_"];
    XCTAssertNotNil(provider);
    XCTAssertEqualObjects(provider.keyPrefix, @"TEST_PREFIX_");
}

- (void)testInitWithoutPrefix {
    PDSEnvironmentSecretsProvider *provider = [[PDSEnvironmentSecretsProvider alloc] init];
    XCTAssertNotNil(provider);
    XCTAssertEqualObjects(provider.keyPrefix, @"");
}

- (void)testSecretForKeyWithSetVariable {
    NSString *testKey = @"PDSEnvironmentSecretsProvider_TEST_KEY";
    NSString *testValue = @"test_secret_value_12345";
    
    setenv([testKey UTF8String], [testValue UTF8String], 1);
    [self addTeardownBlock:^{
        unsetenv([testKey UTF8String]);
    }];
    
    PDSEnvironmentSecretsProvider *provider = [[PDSEnvironmentSecretsProvider alloc] init];
    NSError *error = nil;
    NSString *value = [provider secretForKey:testKey error:&error];
    
    XCTAssertNotNil(value);
    XCTAssertNil(error);
    XCTAssertEqualObjects(value, testValue);
}

- (void)testSecretForKeyWithPrefix {
    NSString *testKey = @"API_KEY";
    NSString *testValue = @"prefixed_secret_value";
    NSString *fullKey = @"MYAPP_API_KEY";
    
    setenv([fullKey UTF8String], [testValue UTF8String], 1);
    [self addTeardownBlock:^{
        unsetenv([fullKey UTF8String]);
    }];
    
    PDSEnvironmentSecretsProvider *provider = [[PDSEnvironmentSecretsProvider alloc] initWithPrefix:@"MYAPP_"];
    NSError *error = nil;
    NSString *value = [provider secretForKey:testKey error:&error];
    
    XCTAssertNotNil(value);
    XCTAssertNil(error);
    XCTAssertEqualObjects(value, testValue);
}

- (void)testSecretForKeyWithMissingVariable {
    NSString *testKey = @"PDSEnvironmentSecretsProvider_NONEXISTENT_KEY_12345";
    
    unsetenv([testKey UTF8String]);
    
    PDSEnvironmentSecretsProvider *provider = [[PDSEnvironmentSecretsProvider alloc] init];
    NSError *error = nil;
    NSString *value = [provider secretForKey:testKey error:&error];
    
    XCTAssertNil(value);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, PDSEnvironmentSecretsProviderErrorKeyNotFound);
}

- (void)testSecretForKeyWithEmptyKey {
    PDSEnvironmentSecretsProvider *provider = [[PDSEnvironmentSecretsProvider alloc] init];
    NSError *error = nil;
    NSString *value = [provider secretForKey:@"" error:&error];
    
    XCTAssertNil(value);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, PDSEnvironmentSecretsProviderErrorInvalidKey);
}

@end
