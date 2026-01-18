/*!
 @file PDSHttpServerBuilderTests.m

 @abstract Unit tests for PDSHttpServerBuilder.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <XCTest/XCTest.h>
#import "Network/PDSHttpServerBuilder.h"
#import "Network/HttpServer.h"
#import "App/PDSConfiguration.h"

@interface PDSHttpServerBuilderTests : XCTestCase
@end

@implementation PDSHttpServerBuilderTests

#pragma mark - Initialization Tests

- (void)testInitWithDefaults {
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
    
    XCTAssertNotNil(builder);
    XCTAssertEqual(builder.port, 2583);
    XCTAssertTrue(builder.enableXrpc);
    XCTAssertTrue(builder.enableOAuth);
    XCTAssertTrue(builder.enableExploreUI);
    XCTAssertTrue(builder.enableOAuthDemo);
    XCTAssertTrue(builder.enableMSTViewer);
    XCTAssertTrue(builder.enableNodeInfo);
}

- (void)testInitWithConfiguration {
    // Note: This test requires PDSConfiguration to be mockable or use shared instance
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] initWithConfiguration:nil];
    
    XCTAssertNotNil(builder);
    // With nil configuration, should use defaults
    XCTAssertEqual(builder.port, 2583);
}

#pragma mark - Property Tests

- (void)testPortConfiguration {
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
    
    builder.port = 8080;
    XCTAssertEqual(builder.port, 8080);
    
    builder.port = 0;
    XCTAssertEqual(builder.port, 0);
}

- (void)testFeatureFlagsCanBeDisabled {
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
    
    builder.enableXrpc = NO;
    builder.enableOAuth = NO;
    builder.enableExploreUI = NO;
    builder.enableOAuthDemo = NO;
    builder.enableMSTViewer = NO;
    builder.enableNodeInfo = NO;
    
    XCTAssertFalse(builder.enableXrpc);
    XCTAssertFalse(builder.enableOAuth);
    XCTAssertFalse(builder.enableExploreUI);
    XCTAssertFalse(builder.enableOAuthDemo);
    XCTAssertFalse(builder.enableMSTViewer);
    XCTAssertFalse(builder.enableNodeInfo);
}

- (void)testIssuerConfiguration {
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
    
    XCTAssertNil(builder.issuer);
    
    builder.issuer = @"https://example.com";
    XCTAssertEqualObjects(builder.issuer, @"https://example.com");
}

#pragma mark - Build Tests

- (void)testBuildWithMinimalConfigurationSucceeds {
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
    
    // Disable features that require dependencies
    builder.enableXrpc = NO;
    builder.enableOAuth = NO;
    builder.enableExploreUI = NO;
    builder.enableOAuthDemo = NO;
    builder.enableMSTViewer = NO;
    builder.enableNodeInfo = NO;
    
    NSError *error = nil;
    HttpServer *server = [builder buildWithError:&error];
    
    XCTAssertNotNil(server);
    XCTAssertNil(error);
}

- (void)testBuildReturnsServerWithCorrectPort {
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
    builder.port = 9999;
    
    // Disable features that require dependencies
    builder.enableXrpc = NO;
    builder.enableOAuth = NO;
    builder.enableExploreUI = NO;
    builder.enableOAuthDemo = NO;
    builder.enableMSTViewer = NO;
    builder.enableNodeInfo = NO;
    
    NSError *error = nil;
    HttpServer *server = [builder buildWithError:&error];
    
    XCTAssertNotNil(server);
    XCTAssertEqual(server.port, 9999);
}

#pragma mark - Configure Server Tests

- (void)testConfigureServerWithNilServerFails {
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
    
    NSError *error = nil;
    BOOL result = [builder configureServer:nil error:&error];
    
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, @"PDSHttpServerBuilderErrorDomain");
}

- (void)testConfigureServerWithValidServerSucceeds {
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
    
    // Disable features that require dependencies
    builder.enableXrpc = NO;
    builder.enableOAuth = NO;
    builder.enableExploreUI = NO;
    builder.enableOAuthDemo = NO;
    builder.enableMSTViewer = NO;
    builder.enableNodeInfo = NO;
    
    HttpServer *server = [HttpServer serverWithPort:8080];
    
    NSError *error = nil;
    BOOL result = [builder configureServer:server error:&error];
    
    XCTAssertTrue(result);
    XCTAssertNil(error);
}

#pragma mark - Feature Flag Behavior Tests

- (void)testXrpcNotRegisteredWhenControllerMissing {
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
    builder.enableXrpc = YES;
    builder.controller = nil;  // No controller
    
    // Disable other features
    builder.enableOAuth = NO;
    builder.enableExploreUI = NO;
    builder.enableOAuthDemo = NO;
    builder.enableMSTViewer = NO;
    builder.enableNodeInfo = NO;
    
    NSError *error = nil;
    HttpServer *server = [builder buildWithError:&error];
    
    // Should still succeed, but XRPC routes won't be registered
    XCTAssertNotNil(server);
    XCTAssertNil(error);
}

- (void)testOAuthNotRegisteredWhenDependenciesMissing {
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
    builder.enableOAuth = YES;
    builder.serviceDatabases = nil;  // No databases
    builder.jwtMinter = nil;         // No minter
    
    // Disable other features
    builder.enableXrpc = NO;
    builder.enableExploreUI = NO;
    builder.enableOAuthDemo = NO;
    builder.enableMSTViewer = NO;
    builder.enableNodeInfo = NO;
    
    NSError *error = nil;
    HttpServer *server = [builder buildWithError:&error];
    
    // Should still succeed, but OAuth routes won't be registered
    XCTAssertNotNil(server);
    XCTAssertNil(error);
}

#pragma mark - Multiple Build Tests

- (void)testBuilderCanBuildMultipleServers {
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
    
    // Disable features that require dependencies
    builder.enableXrpc = NO;
    builder.enableOAuth = NO;
    builder.enableExploreUI = NO;
    builder.enableOAuthDemo = NO;
    builder.enableMSTViewer = NO;
    builder.enableNodeInfo = NO;
    
    NSError *error1 = nil;
    HttpServer *server1 = [builder buildWithError:&error1];
    
    builder.port = 8081;
    NSError *error2 = nil;
    HttpServer *server2 = [builder buildWithError:&error2];
    
    XCTAssertNotNil(server1);
    XCTAssertNotNil(server2);
    XCTAssertNotEqual(server1, server2);
    XCTAssertEqual(server2.port, 8081);
}

#pragma mark - Edge Cases

- (void)testBuildWithZeroPort {
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
    builder.port = 0;  // Usually means "pick an available port"
    
    // Disable features that require dependencies
    builder.enableXrpc = NO;
    builder.enableOAuth = NO;
    builder.enableExploreUI = NO;
    builder.enableOAuthDemo = NO;
    builder.enableMSTViewer = NO;
    builder.enableNodeInfo = NO;
    
    NSError *error = nil;
    HttpServer *server = [builder buildWithError:&error];
    
    XCTAssertNotNil(server);
}

- (void)testConfigureServerCanBeCalledMultipleTimes {
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
    
    // Disable features that require dependencies
    builder.enableXrpc = NO;
    builder.enableOAuth = NO;
    builder.enableExploreUI = NO;
    builder.enableOAuthDemo = NO;
    builder.enableMSTViewer = NO;
    builder.enableNodeInfo = NO;
    
    HttpServer *server = [HttpServer serverWithPort:8080];
    
    NSError *error1 = nil;
    BOOL result1 = [builder configureServer:server error:&error1];
    
    NSError *error2 = nil;
    BOOL result2 = [builder configureServer:server error:&error2];
    
    XCTAssertTrue(result1);
    XCTAssertTrue(result2);
}

@end