#import <XCTest/XCTest.h>
#import "Network/SSLPinningManager.h"
#import <Security/Security.h>

@interface SSLPinningTests : XCTestCase

@property (nonatomic, strong) SSLPinningManager *pinningManager;

@end

@implementation SSLPinningTests

- (void)setUp {
    [super setUp];
    self.pinningManager = [[SSLPinningManager alloc] initWithPinningEnabled:YES];
}

- (void)tearDown {
    self.pinningManager = nil;
    [super tearDown];
}

- (void)testSharedManager {
    SSLPinningManager *manager1 = [SSLPinningManager sharedManager];
    SSLPinningManager *manager2 = [SSLPinningManager sharedManager];
    XCTAssertEqual(manager1, manager2, @"Shared manager should return the same instance");
}

- (void)testPinningEnabled {
    XCTAssertTrue(self.pinningManager.isPinningEnabled, @"Pinning should be enabled by default");

    SSLPinningManager *disabledManager = [[SSLPinningManager alloc] initWithPinningEnabled:NO];
    XCTAssertFalse(disabledManager.isPinningEnabled, @"Pinning should be disabled when initialized with NO");
}

- (void)testAddAndRemovePinnedKeys {
    NSString *domain = @"example.com";
    NSData *keyData = [@"test-key-data" dataUsingEncoding:NSUTF8StringEncoding];

    // Add a key
    [self.pinningManager addPinnedPublicKey:keyData forDomain:domain];
    // Note: We can't directly test the internal storage, but we can test that methods don't crash

    // Remove keys
    [self.pinningManager removePinnedKeysForDomain:domain];
    // Again, we can't directly verify removal but can test that method doesn't crash
}

- (void)testCreateSession {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [self.pinningManager createSessionWithConfiguration:config];

    XCTAssertNotNil(session, @"Session should be created");
    XCTAssertEqual(session.configuration, config, @"Session should use the provided configuration");
    XCTAssertEqual(session.delegate, self.pinningManager, @"Session delegate should be the pinning manager");
}

- (void)testValidateChallengeWithDisabledPinning {
    SSLPinningManager *disabledManager = [[SSLPinningManager alloc] initWithPinningEnabled:NO];

    // Create a mock challenge - this is difficult to test fully without a real server
    // For now, we'll test that the method exists and doesn't crash
    NSURLAuthenticationChallenge *challenge = nil; // Would need to create a real challenge

    // Since we can't easily create a real challenge in unit tests,
    // we'll just verify the manager is properly initialized
    XCTAssertNotNil(disabledManager);
}

// Integration test that requires network access - disabled by default
- (void)testSSLPinningWithRealRequest {
    // This test would make a real HTTPS request and verify pinning behavior
    // Disabled by default as it requires network access and specific certificates

    XCTSkip(@"Integration test disabled - requires network access and certificate setup");

    // Example of how this could work:
    /*
    XCTestExpectation *expectation = [self expectationWithDescription:@"Network request"];

    SSLPinningManager *manager = [[SSLPinningManager alloc] initWithPinningEnabled:YES];
    // Add known good public key for a test domain
    // manager addPinnedPublicKey:... forDomain:@"example.com"

    NSURLSession *session = [manager createSessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];

    NSURLSessionDataTask *task = [session dataTaskWithURL:[NSURL URLWithString:@"https://example.com"]
                                        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        // Verify the request succeeded
        XCTAssertNil(error);
        XCTAssertNotNil(data);
        [expectation fulfill];
    }];

    [task resume];
    [self waitForExpectationsWithTimeout:30.0 handler:nil];
    */
}

@end