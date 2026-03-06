#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif
#import "Network/SSLPinningManager.h"
#import <Security/Security.h>

@interface SSLPinningManager (TestHooks)
- (BOOL)validateServerTrust:(SecTrustRef)serverTrust forDomain:(NSString *)domain;
- (SecKeyRef)publicKeyFromCertificate:(SecCertificateRef)certificate;
- (NSData *)dataFromPublicKey:(SecKeyRef)publicKey;
@end

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

    [self.pinningManager addPinnedPublicKey:keyData forDomain:domain];
    NSDictionary *stored = [self.pinningManager valueForKey:@"pinnedKeys"];
    XCTAssertEqual([stored[domain] count], (NSUInteger)1);

    // Duplicate should be ignored.
    [self.pinningManager addPinnedPublicKey:keyData forDomain:domain];
    stored = [self.pinningManager valueForKey:@"pinnedKeys"];
    XCTAssertEqual([stored[domain] count], (NSUInteger)1);

    [self.pinningManager removePinnedKeysForDomain:domain];
    stored = [self.pinningManager valueForKey:@"pinnedKeys"];
    XCTAssertNil(stored[domain]);
}

- (void)testAddPinnedKeyIgnoresNilInputsMatchesCount {
    id nullObject = nil;
    [self.pinningManager addPinnedPublicKey:(NSData *)nullObject forDomain:@"example.com"];
    [self.pinningManager addPinnedPublicKey:[@"k" dataUsingEncoding:NSUTF8StringEncoding] forDomain:(NSString *)nullObject];
    NSDictionary *stored = [self.pinningManager valueForKey:@"pinnedKeys"];
    XCTAssertEqual(stored.count, (NSUInteger)0);
}

- (void)testCreateSession {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [self.pinningManager createSessionWithConfiguration:config];

    XCTAssertNotNil(session, @"Session should be created");
    XCTAssertNotNil(session.configuration, @"Session should have a configuration");
    XCTAssertEqual(session.delegate, self.pinningManager, @"Session delegate should be the pinning manager");
}

- (void)testValidateChallengeWithDisabledPinning {
    SSLPinningManager *disabledManager = [[SSLPinningManager alloc] initWithPinningEnabled:NO];
    id<NSURLAuthenticationChallengeSender> sender = (id<NSURLAuthenticationChallengeSender>)nil;
    NSURLProtectionSpace *space = [[NSURLProtectionSpace alloc] initWithHost:@"example.com"
                                                                         port:443
                                                                     protocol:NSURLProtectionSpaceHTTPS
                                                                        realm:nil
                                                         authenticationMethod:NSURLAuthenticationMethodServerTrust];
    NSURLAuthenticationChallenge *challenge = [[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:space
                                                                                           proposedCredential:nil
                                                                                         previousFailureCount:0
                                                                                              failureResponse:nil
                                                                                                        error:nil
                                                                                                       sender:sender];
    XCTAssertFalse([disabledManager validateChallenge:challenge forDomain:@"example.com"]);
}

- (void)testValidateChallengeRejectsUnsupportedMethodWhenEnabled {
    id<NSURLAuthenticationChallengeSender> sender = (id<NSURLAuthenticationChallengeSender>)nil;
    NSURLProtectionSpace *space = [[NSURLProtectionSpace alloc] initWithHost:@"example.com"
                                                                         port:443
                                                                     protocol:NSURLProtectionSpaceHTTPS
                                                                        realm:nil
                                                         authenticationMethod:NSURLAuthenticationMethodHTTPBasic];
    NSURLAuthenticationChallenge *challenge = [[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:space
                                                                                           proposedCredential:nil
                                                                                         previousFailureCount:0
                                                                                              failureResponse:nil
                                                                                                        error:nil
                                                                                                       sender:sender];
    XCTAssertFalse([self.pinningManager validateChallenge:challenge forDomain:@"example.com"]);
}

- (void)testValidateServerTrustWithDisabledPinningAlwaysAllows {
    SSLPinningManager *disabledManager = [[SSLPinningManager alloc] initWithPinningEnabled:NO];
    XCTAssertTrue([disabledManager validateServerTrust:NULL forDomain:@"example.com"]);
}

- (void)testValidateServerTrustAllowsWhenNoPinsConfigured {
    XCTAssertTrue([self.pinningManager validateServerTrust:NULL forDomain:@"example.com"]);
}

- (void)testPublicKeyExtractionAndSerializationRejectNilInputs {
    XCTAssertTrue([self.pinningManager publicKeyFromCertificate:NULL] == NULL);
    XCTAssertNil([self.pinningManager dataFromPublicKey:NULL]);
}

- (void)testSessionDelegateDefaultHandlingForNonTrustChallenge {
    id<NSURLAuthenticationChallengeSender> sender = (id<NSURLAuthenticationChallengeSender>)nil;
    NSURLProtectionSpace *space = [[NSURLProtectionSpace alloc] initWithHost:@"example.com"
                                                                         port:443
                                                                     protocol:NSURLProtectionSpaceHTTPS
                                                                        realm:nil
                                                         authenticationMethod:NSURLAuthenticationMethodHTTPBasic];
    NSURLAuthenticationChallenge *challenge = [[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:space
                                                                                           proposedCredential:nil
                                                                                         previousFailureCount:0
                                                                                              failureResponse:nil
                                                                                                        error:nil
                                                                                                       sender:sender];

    XCTestExpectation *expectation = [self expectationWithDescription:@"completion called"];
    [self.pinningManager URLSession:[NSURLSession sharedSession]
                 didReceiveChallenge:challenge
                   completionHandler:^(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential * _Nullable credential) {
        XCTAssertEqual(disposition, NSURLSessionAuthChallengePerformDefaultHandling);
        XCTAssertNil(credential);
        [expectation fulfill];
    }];
    [self waitForExpectations:@[expectation] timeout:1.0];
}

// Integration test that needs network access - disabled by default
- (void)testSSLPinningWithRealRequestHasNilError {
    // This test would make a real HTTPS request and verify pinning behavior
    // Disabled by default as it needs network access and specific certificates

    XCTSkip(@"Integration test disabled - needs network access and certificate setup");

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
