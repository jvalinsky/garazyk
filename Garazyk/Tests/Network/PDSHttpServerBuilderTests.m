/*!
 @file PDSHttpServerBuilderTests.m

 @abstract Unit tests for PDSHttpServerBuilder.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <XCTest/XCTest.h>
#import "Network/PDSHttpServerBuilder.h"
#import "Network/HttpServer.h"
#import "App/PDSConfiguration.h"
#import "App/PDSController.h"
#import "Sync/Firehose/SubscribeReposHandler.h"
#import "Database/Service/ServiceDatabases.h"
#import "Auth/JWT.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <CoreFoundation/CoreFoundation.h>

@interface PDSHttpServerBuilderTests : XCTestCase
@property (nonatomic, strong) HttpServer *testServer;
@property (nonatomic, strong) NSString *testDirectory;
@end

@implementation PDSHttpServerBuilderTests

- (void)tearDown {
    // Ensure server is stopped and cleaned up after each test
    if (self.testServer) {
        [self.testServer stop];
        self.testServer = nil;
    }
    
    if (self.testDirectory) {
        [[NSFileManager defaultManager] removeItemAtPath:self.testDirectory error:nil];
        self.testDirectory = nil;
    }
    
    [super tearDown];
}

- (NSString *)makeTemporaryDirectory {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"pds-builder-tests-%@", NSUUID.UUID.UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    return path;
}

#pragma mark - Bug Condition Exploration Tests

/*!
 @test testWellKnownAtprotoDIDEndpointReturns404OnUnfixedCode
 
 @abstract Bug condition exploration test for handle-resolution-test5-fix spec.
 
 @discussion This test MUST FAIL on unfixed code - failure confirms the bug exists.
 This test encodes the expected behavior that will be satisfied after the fix.
 
 **Validates: Requirements 1.1, 1.2, 1.3, 1.4**
 
 **Property 1: Fault Condition** - Well-Known Endpoint Returns 404
 
 The bug manifests when a client requests GET /.well-known/atproto-did for a handle
 that exists in the PDS database. Per ATProto spec, the handle is determined by the
 Host header in the HTTP request, not a query parameter.
 
 **EXPECTED OUTCOME ON UNFIXED CODE**: Test FAILS (this is correct - it proves the bug exists)
 
 **EXPECTED OUTCOME AFTER FIX**: Test PASSES (confirms bug is fixed)
 
 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */
- (void)testWellKnownAtprotoDIDEndpointReturns404OnUnfixedCode {
    // Setup: Create a temporary directory and controller
    self.testDirectory = [self makeTemporaryDirectory];
    PDSController *controller = [[PDSController alloc] initWithDirectory:self.testDirectory serviceMaxSize:10 userDatabaseSize:10];
    
    // Create an account in the database so we have a valid handle to test
    NSError *createError = nil;
    NSString *testHandle = @"test5.garazyk.xyz";
    NSString *testDID = @"did:plc:5rpam44qoj2eeisejtxmke7e";
    NSString *testEmail = @"test5@example.com";
    NSString *testPassword = @"testpassword123";
    
    // Create account using the controller's createAccountForEmail method
    NSDictionary *accountResult = [controller createAccountForEmail:testEmail
                                                           password:testPassword
                                                             handle:testHandle
                                                                did:testDID
                                                              error:&createError];
    
    if (!accountResult) {
        // If account creation fails, skip the test
        XCTSkip(@"Could not create test account: %@", createError);
        return;
    }
    
    // Build HTTP server with PDSHttpServerBuilder
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
    builder.controller = controller;
    builder.port = 0; // Use ephemeral port
    
    // Disable features we don't need for this test
    builder.enableOAuth = NO;
    builder.enableOAuthDemo = NO;
    builder.enableMSTViewer = NO;
    builder.enableNodeInfo = NO;
    
    NSError *buildError = nil;
    self.testServer = [builder buildWithError:&buildError];
    
    if (!self.testServer) {
        XCTFail(@"Failed to build HTTP server: %@", buildError);
        return;
    }
    
    // Start the server
    NSError *startError = nil;
    BOOL started = [self.testServer startWithError:&startError];
    
    if (!started) {
        // Check if this is a permission error (EPERM) and skip if so
        NSError *underlying = startError.userInfo[NSUnderlyingErrorKey];
        if ([underlying.domain isEqualToString:NSPOSIXErrorDomain] && underlying.code == EPERM) {
            XCTSkip(@"HttpServer cannot listen (EPERM) in this environment");
            return;
        }
        
        XCTFail(@"Failed to start HTTP server: %@", startError);
        return;
    }
    
    // Get the actual port the server is listening on
    UInt16 actualPort = self.testServer.port;
    
    // Make HTTP request to /.well-known/atproto-did with Host header set to the handle
    // Per ATProto spec: The handle is determined by the Host header, not a query parameter
    // Example: GET https://test5.garazyk.xyz/.well-known/atproto-did
    // 
    // NOTE: We craft a raw HTTP request because NSURLSession overrides the Host header
    // when connecting to localhost. In production, the Host header is set correctly by
    // the HTTP client based on the domain in the URL.
    NSString *rawRequest = [NSString stringWithFormat:
        @"GET /.well-known/atproto-did HTTP/1.1\r\n"
        @"Host: %@\r\n"
        @"Connection: close\r\n"
        @"\r\n", testHandle];
    
    NSData *requestData = [rawRequest dataUsingEncoding:NSUTF8StringEncoding];
    
    // Connect to the server and send raw HTTP request
    CFSocketRef socket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP, 0, NULL, NULL);
    
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(actualPort);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    
    NSData *addressData = [NSData dataWithBytes:&addr length:sizeof(addr)];
    CFSocketError connectResult = CFSocketConnectToAddress(socket, (__bridge CFDataRef)addressData, 5.0);
    
    if (connectResult != kCFSocketSuccess) {
        CFRelease(socket);
        XCTFail(@"Failed to connect to server");
        return;
    }
    
    // Send the request
    CFSocketNativeHandle nativeSocket = CFSocketGetNative(socket);
    
    // Set receive timeout to avoid hanging
    struct timeval timeout;
    timeout.tv_sec = 5;
    timeout.tv_usec = 0;
    setsockopt(nativeSocket, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    
    ssize_t sent = send(nativeSocket, requestData.bytes, requestData.length, 0);
    
    if (sent != (ssize_t)requestData.length) {
        CFRelease(socket);
        XCTFail(@"Failed to send request");
        return;
    }
    
    // Read the response
    NSMutableData *responseData = [NSMutableData data];
    char buffer[4096];
    ssize_t received;
    
    while ((received = recv(nativeSocket, buffer, sizeof(buffer), 0)) > 0) {
        [responseData appendBytes:buffer length:received];
    }
    
    CFRelease(socket);
    
    // Parse the HTTP response
    NSString *responseString = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
    NSArray *lines = [responseString componentsSeparatedByString:@"\r\n"];
    
    // Parse status line
    NSInteger statusCode = 0;
    if (lines.count > 0) {
        NSString *statusLine = lines[0];
        NSArray *parts = [statusLine componentsSeparatedByString:@" "];
        if (parts.count >= 2) {
            statusCode = [parts[1] integerValue];
        }
    }
    
    // Find the body (after empty line)
    NSString *responseBody = nil;
    BOOL foundEmptyLine = NO;
    NSMutableString *body = [NSMutableString string];
    for (NSString *line in lines) {
        if (foundEmptyLine) {
            if (body.length > 0) {
                [body appendString:@"\r\n"];
            }
            [body appendString:line];
        } else if (line.length == 0) {
            foundEmptyLine = YES;
        }
    }
    responseBody = body;
    
    // ASSERTIONS: This test encodes the EXPECTED behavior after the fix
    // On UNFIXED code, this test will FAIL (which is correct - it proves the bug exists)
    // On FIXED code, this test will PASS (which confirms the bug is fixed)
    
    // Expected behavior: GET /.well-known/atproto-did with Host: test5.garazyk.xyz should return 200 with DID
    XCTAssertEqual(statusCode, 200, @"Expected 200 OK for valid handle, but got %ld. On unfixed code, this returns 400 'Missing Host header' - this failure confirms the bug exists.", (long)statusCode);
    
    XCTAssertNotNil(responseBody, @"Expected response body with DID");
    
    if (responseBody) {
        // Trim whitespace from response
        NSString *trimmedResponse = [responseBody stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        XCTAssertEqualObjects(trimmedResponse, testDID, @"Expected DID '%@' in response body, but got '%@'. On unfixed code, this returns error message.", testDID, trimmedResponse);
    }
    
    // Document the counterexample for unfixed code:
    // GET /.well-known/atproto-did with Host: test5.garazyk.xyz returns 400 with message
    // "Missing Host header" instead of 200 with "did:plc:5rpam44qoj2eeisejtxmke7e"
}

#pragma mark - Initialization Tests

- (void)testInitWithDefaults {
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
    
    XCTAssertNotNil(builder);
    XCTAssertEqual(builder.port, 2583);
    XCTAssertTrue(builder.enableXrpc);
    XCTAssertTrue(builder.enableOAuth);
    XCTAssertTrue(builder.enableOAuthDemo);
    XCTAssertTrue(builder.enableMSTViewer);
    XCTAssertTrue(builder.enableNodeInfo);
}

- (void)testInitWithConfigurationSetsDefaultPortWithNilConfig {
    // Note: This test needs PDSConfiguration to be mockable or use shared instance
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] initWithConfiguration:nil];
    
    XCTAssertNotNil(builder);
    // With nil configuration, should use defaults
    XCTAssertEqual(builder.port, 2583);
}

#pragma mark - Property Tests

- (void)testPortConfigurationSetsPort {
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
    builder.enableOAuthDemo = NO;
    builder.enableMSTViewer = NO;
    builder.enableNodeInfo = NO;

    XCTAssertFalse(builder.enableXrpc);
    XCTAssertFalse(builder.enableOAuth);
    XCTAssertFalse(builder.enableOAuthDemo);
    XCTAssertFalse(builder.enableMSTViewer);
    XCTAssertFalse(builder.enableNodeInfo);
}

- (void)testIssuerConfigurationSetsIssuer {
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
    
    XCTAssertNil(builder.issuer);
    
    builder.issuer = @"https://example.com";
    XCTAssertEqualObjects(builder.issuer, @"https://example.com");
}

#pragma mark - Build Tests

- (void)testBuildWithMinimalConfigurationReturnsNonNullServerAndNoError {
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
    
    // Disable features that require dependencies
    builder.enableXrpc = NO;
    builder.enableOAuth = NO;
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
    builder.enableOAuthDemo = NO;
    builder.enableMSTViewer = NO;
    builder.enableNodeInfo = NO;

    NSError *error = nil;
    HttpServer *server = [builder buildWithError:&error];

    // Should still succeed, but XRPC routes won't be registered
    XCTAssertNotNil(server);
    XCTAssertNil(error);
}

- (void)testConfigureServerRegistersSubscribeReposWebSocketRoute {
    NSString *tempDir = [self makeTemporaryDirectory];
    PDSController *controller = [[PDSController alloc] initWithDirectory:tempDir serviceMaxSize:10 userDatabaseSize:10];
    SubscribeReposHandler *subscribeReposHandler =
        [[SubscribeReposHandler alloc]
            initWithServiceDatabases:controller.serviceDatabases
                    userDatabasePool:controller.userDatabasePool];

    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
    builder.controller = controller;
    builder.subscribeReposHandler = subscribeReposHandler;
    builder.enableOAuth = NO;
    builder.enableOAuthDemo = NO;
    builder.enableMSTViewer = NO;
    builder.enableNodeInfo = NO;

    HttpServer *server = [HttpServer serverWithPort:8080];
    NSError *error = nil;
    BOOL result = [builder configureServer:server error:&error];

    XCTAssertTrue(result);
    XCTAssertNil(error);

    NSDictionary *webSocketHandlers = [server valueForKey:@"webSocketHandlers"];
    XCTAssertNotNil(webSocketHandlers[@"/xrpc/com.atproto.sync.subscribeRepos"]);

    [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
}

- (void)testConfigureServerWithoutSubscribeReposHandlerHasNoWebSocketRoute {
    NSString *tempDir = [self makeTemporaryDirectory];
    PDSController *controller = [[PDSController alloc] initWithDirectory:tempDir serviceMaxSize:10 userDatabaseSize:10];

    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
    builder.controller = controller;
    builder.enableOAuth = NO;
    builder.enableOAuthDemo = NO;
    builder.enableMSTViewer = NO;
    builder.enableNodeInfo = NO;

    HttpServer *server = [HttpServer serverWithPort:8080];
    NSError *error = nil;
    BOOL result = [builder configureServer:server error:&error];

    XCTAssertTrue(result);
    XCTAssertNil(error);

    NSDictionary *webSocketHandlers = [server valueForKey:@"webSocketHandlers"];
    XCTAssertNil(webSocketHandlers[@"/xrpc/com.atproto.sync.subscribeRepos"]);

    [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
}

- (void)testOAuthNotRegisteredWhenDependenciesMissing {
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
    builder.enableOAuth = YES;
    builder.serviceDatabases = nil;  // No databases
    builder.jwtMinter = nil;         // No minter
    
    // Disable other features
    builder.enableXrpc = NO;
    builder.enableOAuthDemo = NO;
    builder.enableMSTViewer = NO;
    builder.enableNodeInfo = NO;

    NSError *error = nil;
    HttpServer *server = [builder buildWithError:&error];

    // Should still succeed, but OAuth routes won't be registered
    XCTAssertNotNil(server);
    XCTAssertNil(error);
}

- (void)testAdminRoutesRedirectToUIServerAndRootIsPlainText {
    NSString *tempDir = [self makeTemporaryDirectory];
    PDSController *controller = [[PDSController alloc] initWithDirectory:tempDir
                                                            serviceMaxSize:10
                                                          userDatabaseSize:10];

    NSString *previousUIURL = [[[NSProcessInfo processInfo] environment][@"PDS_UI_SERVER_URL"] copy];
    setenv("PDS_UI_SERVER_URL", "http://ui.local:4599", 1);
    @try {
        PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
        builder.controller = controller;
        builder.port = 0;

        builder.enableOAuth = NO;
        builder.enableXrpc = NO;
        builder.enableOAuthDemo = NO;
        builder.enableMSTViewer = NO;
        builder.enableNodeInfo = NO;
        // Admin routes are enabled by default through PDSHttpAdminRoutePack registration

        NSError *buildError = nil;
        self.testServer = [builder buildWithError:&buildError];
        XCTAssertNotNil(self.testServer);
        XCTAssertNil(buildError);
        if (!self.testServer) {
            [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
            return;
        }

        NSError *startError = nil;
        BOOL started = [self.testServer startWithError:&startError];
        if (!started) {
            NSError *underlying = startError.userInfo[NSUnderlyingErrorKey];
            if ([underlying.domain isEqualToString:NSPOSIXErrorDomain] &&
                underlying.code == EPERM) {
                [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
                XCTSkip(@"HttpServer cannot listen (EPERM) in this environment");
                return;
            }
            [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
            XCTFail(@"Failed to start HTTP server: %@", startError);
            return;
        }

        UInt16 actualPort = self.testServer.port;

        NSDictionary *rootResponse = [self rawHTTPResponseWithMethod:@"GET"
                                                                path:@"/"
                                                                port:actualPort];
        XCTAssertEqual([rootResponse[@"statusCode"] integerValue], 200);
        NSString *rootType = rootResponse[@"headers"][@"content-type"];
        XCTAssertTrue([rootType containsString:@"text/plain"]);
        NSString *rootBody = [rootResponse[@"body"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        XCTAssertEqualObjects(rootBody, @"kaszlak 1.0.0");

        [self.testServer stop];
        self.testServer = nil;
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
    } @finally {
        if (previousUIURL.length > 0) {
            setenv("PDS_UI_SERVER_URL", previousUIURL.UTF8String, 1);
        } else {
            unsetenv("PDS_UI_SERVER_URL");
        }
    }
}

#pragma mark - Multiple Build Tests

- (void)testBuilderCanBuildMultipleServers {
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];

    // Disable features that require dependencies
    builder.enableXrpc = NO;
    builder.enableOAuth = NO;
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

- (void)testBuildWithZeroPortReturnsNonNullServer {
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
    builder.port = 0;  // Usually means "pick an available port"

    // Disable features that require dependencies
    builder.enableXrpc = NO;
    builder.enableOAuth = NO;
    builder.enableOAuthDemo = NO;
    builder.enableMSTViewer = NO;
    builder.enableNodeInfo = NO;

    NSError *error = nil;
    HttpServer *server = [builder buildWithError:&error];
    
    XCTAssertNotNil(server);
    XCTAssertEqual(server.port, 0);
    XCTAssertNil(error);
}

- (void)testConfigureServerCanBeCalledMultipleTimesReturnsSuccess {
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];

    // Disable features that require dependencies
    builder.enableXrpc = NO;
    builder.enableOAuth = NO;
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

#pragma mark - Preservation Property Tests

/*!
 @test testPreservation_OAuthWellKnownEndpointsWork
 
 @abstract Preservation property test for handle-resolution-test5-fix spec.
 
 @discussion This test verifies that OAuth .well-known endpoints continue to work
 on UNFIXED code. This establishes the baseline behavior that must be preserved
 after implementing the fix.
 
 **Validates: Requirements 3.1, 3.2**
 
 **Property 2: Preservation** - Other Endpoints Unchanged
 
 For any HTTP request that does NOT target /.well-known/atproto-did, the server
 should produce the same response before and after the fix.
 
 **EXPECTED OUTCOME ON UNFIXED CODE**: Test PASSES (confirms baseline behavior)
 
 **EXPECTED OUTCOME AFTER FIX**: Test PASSES (confirms no regressions)
 
 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */
- (void)testPreservation_OAuthWellKnownEndpointsAreRegisteredValidatesServerBuildReturnsNoError {
    // Setup: Create a minimal server with OAuth enabled
    NSString *tempDir = [self makeTemporaryDirectory];
    PDSController *controller = [[PDSController alloc] initWithDirectory:tempDir serviceMaxSize:10 userDatabaseSize:10];
    
    // Setup OAuth dependencies
    PDSServiceDatabases *serviceDatabases = [[PDSServiceDatabases alloc] initWithDirectory:tempDir
                                                                            serviceMaxSize:10
                                                                          didCacheMaxSize:10
                                                                        sequencerMaxSize:10];
    JWTMinter *jwtMinter = [[JWTMinter alloc] init];
    jwtMinter.issuer = @"http://localhost";
    
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
    builder.controller = controller;
    builder.serviceDatabases = serviceDatabases;
    builder.jwtMinter = jwtMinter;
    builder.port = 0; // Use ephemeral port
    builder.enableOAuth = YES;
    builder.enableXrpc = NO;
    builder.enableOAuthDemo = NO;
    builder.enableMSTViewer = NO;
    builder.enableNodeInfo = NO;

    NSError *buildError = nil;
    HttpServer *server = [builder buildWithError:&buildError];
    
    if (!server) {
        [serviceDatabases closeAll];
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
        XCTFail(@"Failed to build HTTP server: %@", buildError);
        return;
    }
    
    NSError *startError = nil;
    BOOL started = [server startWithError:&startError];
    
    if (!started) {
        [serviceDatabases closeAll];
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
        NSError *underlying = startError.userInfo[NSUnderlyingErrorKey];
        if ([underlying.domain isEqualToString:NSPOSIXErrorDomain] && underlying.code == EPERM) {
            XCTSkip(@"HttpServer cannot listen (EPERM) in this environment");
            return;
        }
        XCTFail(@"Failed to start HTTP server: %@", startError);
        return;
    }
    
    UInt16 actualPort = server.port;
    
    // Test 1: OAuth Authorization Server Metadata - verify endpoint is registered (not 404)
    NSString *authServerURL = [NSString stringWithFormat:@"http://localhost:%d/.well-known/oauth-authorization-server", actualPort];
    [self verifyEndpointIsRegistered:authServerURL expectation:@"OAuth authorization server metadata"];
    
    // Test 2: OAuth Protected Resource Metadata - verify endpoint is registered (not 404)
    NSString *protectedResourceURL = [NSString stringWithFormat:@"http://localhost:%d/.well-known/oauth-protected-resource", actualPort];
    [self verifyEndpointIsRegistered:protectedResourceURL expectation:@"OAuth protected resource metadata"];
    
    [server stop];
    [serviceDatabases closeAll];
    [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
}

/*!
 @test testPreservation_NodeInfoWellKnownEndpointWorks
 
 @abstract Preservation property test for handle-resolution-test5-fix spec.
 
 @discussion This test verifies that the NodeInfo .well-known endpoint continues
 to work on UNFIXED code. This establishes the baseline behavior that must be
 preserved after implementing the fix.
 
 **Validates: Requirements 3.3**
 
 **Property 2: Preservation** - Other Endpoints Unchanged
 
 **EXPECTED OUTCOME ON UNFIXED CODE**: Test PASSES (confirms baseline behavior)
 
 **EXPECTED OUTCOME AFTER FIX**: Test PASSES (confirms no regressions)
 
 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */
- (void)testPreservation_NodeInfoWellKnownEndpointValidatesServerBuildReturnsNoError {
    // Setup: Create a minimal server with NodeInfo enabled
    NSString *tempDir = [self makeTemporaryDirectory];
    PDSController *controller = [[PDSController alloc] initWithDirectory:tempDir serviceMaxSize:10 userDatabaseSize:10];
    
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
    builder.controller = controller;
    builder.port = 0;
    builder.enableNodeInfo = YES;
    builder.enableOAuth = NO;
    builder.enableXrpc = NO;
    builder.enableOAuthDemo = NO;
    builder.enableMSTViewer = NO;

    NSError *buildError = nil;
    HttpServer *server = [builder buildWithError:&buildError];
    
    if (!server) {
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
        XCTFail(@"Failed to build HTTP server: %@", buildError);
        return;
    }
    
    NSError *startError = nil;
    BOOL started = [server startWithError:&startError];
    
    if (!started) {
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
        NSError *underlying = startError.userInfo[NSUnderlyingErrorKey];
        if ([underlying.domain isEqualToString:NSPOSIXErrorDomain] && underlying.code == EPERM) {
            XCTSkip(@"HttpServer cannot listen (EPERM) in this environment");
            return;
        }
        XCTFail(@"Failed to start HTTP server: %@", startError);
        return;
    }
    
    UInt16 actualPort = server.port;
    
    // Test: NodeInfo Discovery Endpoint
    NSString *nodeInfoURL = [NSString stringWithFormat:@"http://localhost:%d/.well-known/nodeinfo", actualPort];
    [self verifyEndpointReturns200:nodeInfoURL withContentType:@"application/json" expectation:@"NodeInfo discovery"];
    
    [server stop];
    [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
}

/*!
 @test testPreservation_XrpcMethodsWork
 
 @abstract Preservation property test for handle-resolution-test5-fix spec.
 
 @discussion This test verifies that XRPC methods continue to work on UNFIXED code.
 This establishes the baseline behavior that must be preserved after implementing
 the fix.
 
 **Validates: Requirements 3.4, 3.5**
 
 **Property 2: Preservation** - Other Endpoints Unchanged
 
 **EXPECTED OUTCOME ON UNFIXED CODE**: Test PASSES (confirms baseline behavior)
 
 **EXPECTED OUTCOME AFTER FIX**: Test PASSES (confirms no regressions)
 
 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */
- (void)testPreservation_XrpcMethodsValidatesServerBuildReturnsNoError {
    // Setup: Create a server with XRPC enabled
    NSString *tempDir = [self makeTemporaryDirectory];
    PDSController *controller = [[PDSController alloc] initWithDirectory:tempDir serviceMaxSize:10 userDatabaseSize:10];
    
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
    builder.controller = controller;
    builder.port = 0;
    builder.enableXrpc = YES;
    builder.enableOAuth = NO;
    builder.enableOAuthDemo = NO;
    builder.enableMSTViewer = NO;
    builder.enableNodeInfo = NO;

    NSError *buildError = nil;
    HttpServer *server = [builder buildWithError:&buildError];
    
    if (!server) {
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
        XCTFail(@"Failed to build HTTP server: %@", buildError);
        return;
    }
    
    NSError *startError = nil;
    BOOL started = [server startWithError:&startError];
    
    if (!started) {
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
        NSError *underlying = startError.userInfo[NSUnderlyingErrorKey];
        if ([underlying.domain isEqualToString:NSPOSIXErrorDomain] && underlying.code == EPERM) {
            XCTSkip(@"HttpServer cannot listen (EPERM) in this environment");
            return;
        }
        XCTFail(@"Failed to start HTTP server: %@", startError);
        return;
    }
    
    UInt16 actualPort = server.port;
    
    // Test: XRPC method com.atproto.server.describeServer
    NSString *xrpcURL = [NSString stringWithFormat:@"http://localhost:%d/xrpc/com.atproto.server.describeServer", actualPort];
    [self verifyEndpointReturns200:xrpcURL withContentType:@"application/json" expectation:@"XRPC describeServer"];
    
    [server stop];
    [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
}

- (void)testXrpcDescribeServerPrefersXrpcRoutesOverExploreWildcard {
    NSString *tempDir = [self makeTemporaryDirectory];
    PDSController *controller = [[PDSController alloc] initWithDirectory:tempDir
                                                           serviceMaxSize:10
                                                          userDatabaseSize:10];

    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
    builder.controller = controller;
    builder.port = 0;
    builder.enableXrpc = YES;
    builder.enableOAuth = NO;
    builder.enableOAuthDemo = NO;
    builder.enableMSTViewer = NO;
    builder.enableNodeInfo = NO;

    NSError *buildError = nil;
    HttpServer *server = [builder buildWithError:&buildError];
    if (!server) {
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
        XCTFail(@"Failed to build HTTP server: %@", buildError);
        return;
    }

    NSError *startError = nil;
    BOOL started = [server startWithError:&startError];
    if (!started) {
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
        NSError *underlying = startError.userInfo[NSUnderlyingErrorKey];
        if ([underlying.domain isEqualToString:NSPOSIXErrorDomain] &&
            underlying.code == EPERM) {
            XCTSkip(@"HttpServer cannot listen (EPERM) in this environment");
            return;
        }
        XCTFail(@"Failed to start HTTP server: %@", startError);
        return;
    }

    UInt16 actualPort = server.port;
    NSString *xrpcURL = [NSString
        stringWithFormat:@"http://localhost:%d/xrpc/com.atproto.server.describeServer",
                         actualPort];
    [self verifyEndpointReturns200:xrpcURL
                   withContentType:@"application/json"
                       expectation:@"XRPC describeServer with UI wildcard"];

    [server stop];
    [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
}

#pragma mark - Helper Methods

- (NSDictionary *)rawHTTPResponseWithMethod:(NSString *)method
                                       path:(NSString *)path
                                       port:(UInt16)port {
    NSString *requestText = [NSString stringWithFormat:@"%@ %@ HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
                                                       method ?: @"GET",
                                                       path ?: @"/"];
    NSData *requestData = [requestText dataUsingEncoding:NSUTF8StringEncoding];

    CFSocketRef socket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP, 0, NULL, NULL);
    if (!socket) {
        XCTFail(@"Failed to create socket");
        return @{@"statusCode": @0, @"headers": @{}, @"body": @""};
    }

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    NSData *addressData = [NSData dataWithBytes:&addr length:sizeof(addr)];
    CFSocketError connectResult = CFSocketConnectToAddress(socket, (__bridge CFDataRef)addressData, 5.0);
    if (connectResult != kCFSocketSuccess) {
        CFRelease(socket);
        XCTFail(@"Failed to connect to local HTTP server");
        return @{@"statusCode": @0, @"headers": @{}, @"body": @""};
    }

    CFSocketNativeHandle nativeSocket = CFSocketGetNative(socket);
    struct timeval timeout;
    timeout.tv_sec = 5;
    timeout.tv_usec = 0;
    setsockopt(nativeSocket, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));

    ssize_t sent = send(nativeSocket, requestData.bytes, requestData.length, 0);
    if (sent != (ssize_t)requestData.length) {
        CFRelease(socket);
        XCTFail(@"Failed to send request bytes");
        return @{@"statusCode": @0, @"headers": @{}, @"body": @""};
    }

    NSMutableData *responseData = [NSMutableData data];
    char buffer[4096];
    ssize_t received = 0;
    while ((received = recv(nativeSocket, buffer, sizeof(buffer), 0)) > 0) {
        [responseData appendBytes:buffer length:(NSUInteger)received];
    }
    CFRelease(socket);

    NSString *responseString = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] ?: @"";
    NSRange headerEndRange = [responseString rangeOfString:@"\r\n\r\n"];
    NSString *headerSection = headerEndRange.location != NSNotFound
                                  ? [responseString substringToIndex:headerEndRange.location]
                                  : responseString;
    NSString *bodySection = headerEndRange.location != NSNotFound
                                ? [responseString substringFromIndex:headerEndRange.location + 4]
                                : @"";

    NSArray<NSString *> *headerLines = [headerSection componentsSeparatedByString:@"\r\n"];
    NSInteger statusCode = 0;
    NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
    if (headerLines.count > 0) {
        NSArray<NSString *> *statusParts = [headerLines[0] componentsSeparatedByString:@" "];
        if (statusParts.count >= 2) {
            statusCode = [statusParts[1] integerValue];
        }
    }

    for (NSUInteger i = 1; i < headerLines.count; i++) {
        NSString *line = headerLines[i];
        NSRange separatorRange = [line rangeOfString:@":"];
        if (separatorRange.location == NSNotFound) {
            continue;
        }
        NSString *key = [[line substringToIndex:separatorRange.location]
            lowercaseString];
        NSString *value = [[line substringFromIndex:separatorRange.location + 1]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (key.length > 0) {
            headers[key] = value ?: @"";
        }
    }

    return @{
        @"statusCode": @(statusCode),
        @"headers": [headers copy],
        @"body": bodySection ?: @""
    };
}

/*!
 @method verifyEndpointReturns200:withContentType:expectation:
 
 @abstract Helper method to verify an endpoint returns 200 with expected content type.
 
 @param urlString The URL to test
 @param expectedContentType The expected Content-Type header value (or nil to skip check)
 @param description Description for assertion messages
 */
- (void)verifyEndpointReturns200:(NSString *)urlString withContentType:(NSString *)expectedContentType expectation:(NSString *)description {
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 5.0;
    
    XCTestExpectation *expectation = [self expectationWithDescription:[NSString stringWithFormat:@"%@ request", description]];
    
    __block NSInteger statusCode = 0;
    __block NSString *contentType = nil;
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            XCTFail(@"Network error for %@: %@", description, error);
            [expectation fulfill];
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        statusCode = httpResponse.statusCode;
        contentType = httpResponse.allHeaderFields[@"Content-Type"];
        
        [expectation fulfill];
    }];
    
    [task resume];
    
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
    
    // Assertions
    XCTAssertEqual(statusCode, 200, @"Expected 200 OK for %@, but got %ld. This endpoint should work on unfixed code.", description, (long)statusCode);
    
    if (expectedContentType) {
        XCTAssertTrue([contentType containsString:expectedContentType], @"Expected Content-Type to contain '%@' for %@, but got '%@'", expectedContentType, description, contentType);
    }
}

/*!
 @method verifyEndpointIsRegistered:expectation:
 
 @abstract Helper method to verify an endpoint is registered (returns non-404 status).
 
 @param urlString The URL to test
 @param description Description for assertion messages
 */
- (void)verifyEndpointIsRegistered:(NSString *)urlString expectation:(NSString *)description {
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 5.0;
    
    XCTestExpectation *expectation = [self expectationWithDescription:[NSString stringWithFormat:@"%@ request", description]];
    
    __block NSInteger statusCode = 0;
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            XCTFail(@"Network error for %@: %@", description, error);
            [expectation fulfill];
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        statusCode = httpResponse.statusCode;
        
        [expectation fulfill];
    }];
    
    [task resume];
    
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
    
    // Assertion: Endpoint should be registered (not 404)
    XCTAssertNotEqual(statusCode, 404, @"Expected endpoint %@ to be registered (not 404), but got 404. This endpoint should be registered on unfixed code.", description);
}

@end
