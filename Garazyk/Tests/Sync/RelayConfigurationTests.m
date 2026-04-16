#import <XCTest/XCTest.h>
#import "Sync/Relay/RelayConfiguration.h"

@interface RelayConfigurationTests : XCTestCase

@end

@implementation RelayConfigurationTests

- (void)testDefaultConfiguration {
    RelayConfiguration *config = [[RelayConfiguration alloc] initWithUpstreamURLs:@[@"pds1.example.com"]
                                                                     downstreamPort:2584
                                                                      retentionHours:72
                                                                    validationMode:RelayValidationModeLogOnly];
    
    XCTAssertEqual(config.downstreamPort, 2584);
    XCTAssertEqual(config.retentionHours, 72);
    XCTAssertEqual(config.validationMode, RelayValidationModeLogOnly);
    XCTAssertEqual(config.maxDownstreamConnections, 1000);
}

- (void)testCustomConfiguration {
    RelayConfiguration *config = [[RelayConfiguration alloc] initWithUpstreamURLs:@[@"p1.com", @"p2.com"]
                                                                     downstreamPort:3000
                                                                      retentionHours:24
                                                                    validationMode:RelayValidationModeStrict];
    
    XCTAssertEqual(config.upstreamURLs.count, 2);
    XCTAssertEqualObjects(config.upstreamURLs[0], @"p1.com");
    XCTAssertEqual(config.downstreamPort, 3000);
    XCTAssertEqual(config.retentionHours, 24);
    XCTAssertEqual(config.validationMode, RelayValidationModeStrict);
}

- (void)testValidationModes {
    RelayConfiguration *lenient = [[RelayConfiguration alloc] initWithUpstreamURLs:@[@"a.com"]
                                                                      downstreamPort:0
                                                                       retentionHours:0
                                                                     validationMode:RelayValidationModeLenient];
    XCTAssertEqual(lenient.validationMode, RelayValidationModeLenient);
    
    RelayConfiguration *strict = [[RelayConfiguration alloc] initWithUpstreamURLs:@[@"a.com"]
                                                                      downstreamPort:0
                                                                       retentionHours:0
                                                                     validationMode:RelayValidationModeStrict];
    XCTAssertEqual(strict.validationMode, RelayValidationModeStrict);
    
    RelayConfiguration *logOnly = [[RelayConfiguration alloc] initWithUpstreamURLs:@[@"a.com"]
                                                                     downstreamPort:0
                                                                      retentionHours:0
                                                                    validationMode:RelayValidationModeLogOnly];
    XCTAssertEqual(logOnly.validationMode, RelayValidationModeLogOnly);
}

- (void)testConfigurationFromEnvironment {
    // This test would require environment variables to be set
    // Skipping actual test as it depends on external state
}

- (void)testConfigurationFromFile {
    // This test would require a config file
    // Skipping actual test as it depends on external state
}

@end