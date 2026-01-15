#import <XCTest/XCTest.h>
#import "App/PDSConfiguration.h"

#import "App/PDSConfiguration.h"

// Expose private methods for testing
@interface PDSConfiguration (Private)
- (void)applyConfig:(NSDictionary *)config;
- (NSString *)resolveEnvOverrideForKey:(NSString *)envKey default:(NSString *)defaultValue;
- (BOOL)boolFromEnv:(NSString *)envKey default:(BOOL)defaultValue;
@end

// Subclass to mock environment variables
@interface TestablePDSConfiguration : PDSConfiguration
@property (nonatomic, strong) NSDictionary *mockEnvironment;
@end

@implementation TestablePDSConfiguration

- (instancetype)initWithEnvironment:(NSDictionary *)environment {
    // We must set mockEnvironment BEFORE init calls applyConfig
    // But self is not valid until [super init].
    // And [super init] calls applyConfig.
    // So we need to override init to effectively hook into it, or set environment via global/static if we can't.
    // Actually, [super init] calls applyConfig. applyConfig calls resolveEnvOverrideForKey.
    // resolveEnvOverrideForKey uses self.mockEnvironment.
    // But self.mockEnvironment is not set yet!
    // Workaround: Use a static variable or a different init pattern?
    // Or, simpler: Just let [super init] run (defaults), then we set mockEnvironment and call applyConfig again manually!
    self = [super init];
    if (self) {
        _mockEnvironment = environment;
        [self applyConfig:@{}]; // Re-apply with mock environment
    }
    return self;
}

- (NSString *)resolveEnvOverrideForKey:(NSString *)envKey default:(NSString *)defaultValue {
    NSString *mockValue = self.mockEnvironment[envKey];
    if (mockValue) return mockValue;
    return [super resolveEnvOverrideForKey:envKey default:defaultValue];
}

- (BOOL)boolFromEnv:(NSString *)envKey default:(BOOL)defaultValue {
    NSString *mockValue = self.mockEnvironment[envKey];
    if (mockValue) {
        return [@"true" isEqualToString:mockValue.lowercaseString] || [@"1" isEqualToString:mockValue];
    }
    return [super boolFromEnv:envKey default:defaultValue];
}

@end

@interface PDSConfigurationTests : XCTestCase
@end

@implementation PDSConfigurationTests

- (void)testDefaultRateLimitValues {
    TestablePDSConfiguration *config = [[TestablePDSConfiguration alloc] initWithEnvironment:@{}];
    
    // Check defaults
    XCTAssertTrue(config.rateLimitEnabled, @"Rate limit should be enabled by default");
    XCTAssertEqual(config.rateLimitDidLimit, 5000, @"Default DID limit should be 5000");
    XCTAssertEqual(config.rateLimitDidWindowSeconds, 3600, @"Default DID window should be 3600");
    XCTAssertEqual(config.rateLimitIpLimit, 1000, @"Default IP limit should be 1000");
}

- (void)testEnvironmentVariableOverrides {
    NSDictionary *env = @{
        @"PDS_RATELIMIT_ENABLED": @"false",
        @"PDS_RATELIMIT_DID_LIMIT": @"999",
        @"PDS_RATELIMIT_DID_WINDOW": @"120",
        @"PDS_RATELIMIT_IP_LIMIT": @"50",
        @"PDS_RATELIMIT_IP_WINDOW": @"10",
        @"PDS_RATELIMIT_BLOB_LIMIT": @"5",
        @"PDS_RATELIMIT_BLOB_WINDOW": @"600"
    };
    
    TestablePDSConfiguration *config = [[TestablePDSConfiguration alloc] initWithEnvironment:env];
    
    XCTAssertFalse(config.rateLimitEnabled, @"Rate limit should be disabled by env var");
    XCTAssertEqual(config.rateLimitDidLimit, 999, @"DID limit should override");
    XCTAssertEqual(config.rateLimitDidWindowSeconds, 120, @"DID window should override");
    XCTAssertEqual(config.rateLimitIpLimit, 50, @"IP limit should override");
    XCTAssertEqual(config.rateLimitIpWindowSeconds, 10, @"IP window should override");
    XCTAssertEqual(config.rateLimitBlobLimit, 5, @"Blob limit should override");
    XCTAssertEqual(config.rateLimitBlobWindowSeconds, 600, @"Blob window should override");
}

- (void)testLoadFromConfigFile {
    // Create temporary config file
    NSString *tempDir = NSTemporaryDirectory();
    NSString *configPath = [tempDir stringByAppendingPathComponent:@"test_config.json"];
    
    NSDictionary *jsonConfig = @{
        @"rate_limit": @{
            @"enabled": @YES,
            @"did_limit": @8000,
            @"did_window": @1800,
            @"ip_limit": @200,
            @"ip_window": @30,
            @"blob_limit": @10,
            @"blob_window": @100
        }
    };
    
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonConfig options:0 error:nil];
    [jsonData writeToFile:configPath atomically:YES];
    
    TestablePDSConfiguration *config = [[TestablePDSConfiguration alloc] initWithEnvironment:@{}];
    NSError *error = nil;
    BOOL success = [config loadFromPath:configPath error:&error];
    
    XCTAssertTrue(success, @"Should load config file successfully");
    XCTAssertNil(error, @"Should not have error");
    
    XCTAssertEqual(config.rateLimitDidLimit, 8000, @"Config DID limit should match JSON");
    XCTAssertEqual(config.rateLimitDidWindowSeconds, 1800, @"Config DID window should match JSON");
    XCTAssertEqual(config.rateLimitIpLimit, 200, @"Config IP limit should match JSON");
    XCTAssertEqual(config.rateLimitBlobLimit, 10, @"Config Blob limit should match JSON");
    
    // Clean up
    [[NSFileManager defaultManager] removeItemAtPath:configPath error:nil];
}

- (void)testEnvironmentOverridesConfigFile {
    // Config file sets limits
    NSString *tempDir = NSTemporaryDirectory();
    NSString *configPath = [tempDir stringByAppendingPathComponent:@"test_config_override.json"];
    NSDictionary *jsonConfig = @{@"rate_limit": @{@"did_limit": @100}};
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonConfig options:0 error:nil];
    [jsonData writeToFile:configPath atomically:YES];
    
    // Env var sets DIFFERENT limits
    NSDictionary *env = @{@"PDS_RATELIMIT_DID_LIMIT": @200}; // 200 > 100
    
    TestablePDSConfiguration *config = [[TestablePDSConfiguration alloc] initWithEnvironment:env];
    [config loadFromPath:configPath error:nil];
    
    // Should be 200 (Env wins)
    // Wait, applyConfig logic:
    // _rateLimitDidLimit = [rateLimit[@"did_limit"] unsignedIntegerValue];
    // THEN at the end:
    // if (envDidLimit) _rateLimitDidLimit = [envDidLimit integerValue];
    // So YES, ENV overrides config map logic.
    
    XCTAssertEqual(config.rateLimitDidLimit, 200, @"Environment should override config file");
    
    [[NSFileManager defaultManager] removeItemAtPath:configPath error:nil];
}

@end
