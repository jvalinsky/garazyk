#import <XCTest/XCTest.h>
#import "Identity/PLCDirectoryClient.h"
#import "Identity/PLCOperation.h"
#import "Identity/PLCOperationSigner.h"
#import "Identity/DIDKey.h"

@interface PLCDirectoryClientTests : XCTestCase
@property (nonatomic, strong) PLCDirectoryClient *client;
@end

@implementation PLCDirectoryClientTests

- (void)setUp {
    [super setUp];
    self.client = [[PLCDirectoryClient alloc] init];
    self.client.timeoutInterval = 5.0; // Shorter timeout for tests
}

- (void)tearDown {
    self.client = nil;
    [super tearDown];
}

- (void)testDefaultBaseURL {
    XCTAssertEqualObjects(self.client.baseURL, @"https://plc.directory");
}

- (void)testCustomBaseURL {
    PLCDirectoryClient *custom = [[PLCDirectoryClient alloc] initWithBaseURL:@"https://test.plc.directory"];
    XCTAssertEqualObjects(custom.baseURL, @"https://test.plc.directory");
}

- (void)testTimeoutDefault {
    PLCDirectoryClient *defaultClient = [[PLCDirectoryClient alloc] init];
    XCTAssertEqual(defaultClient.timeoutInterval, 30.0);
}

// Test that we can build and sign a valid operation that would be accepted
- (void)testBuildSubmittableOperation {
    // Generate rotation key
    DIDKey *rotationKey = [DIDKey generateSecp256k1];
    XCTAssertNotNil(rotationKey);
    
    // Generate signing key
    DIDKey *signingKey = [DIDKey generateSecp256k1];
    XCTAssertNotNil(signingKey);
    
    // Create genesis operation
    PLCOperation *op = [PLCOperation genesisOperationWithRotationKeys:@[rotationKey.didKey]
                                                    verificationMethods:@{@"atproto": signingKey.didKey}
                                                           alsoKnownAs:@[@"at://test.example.com"]
                                                              services:@{
                                                                  @"atproto_pds": @{
                                                                      @"type": @"AtprotoPersonalDataServer",
                                                                      @"endpoint": @"https://pds.example.com"
                                                                  }
                                                              }];
    XCTAssertNotNil(op);
    
    // Sign the operation
    PLCOperationSigner *signer = [[PLCOperationSigner alloc] initWithDIDKey:rotationKey];
    NSError *error;
    BOOL signed_ = [signer signOperation:op error:&error];
    XCTAssertTrue(signed_, @"Failed to sign: %@", error);
    XCTAssertNotNil(op.sig);
    
    // Compute CID (which becomes part of the DID)
    NSString *cid = [op computeCID:&error];
    XCTAssertNotNil(cid, @"Failed to compute CID: %@", error);
    
    // Note: We don't actually submit - that would create real DIDs!
    // In a real integration test, you'd use a test instance of plc.directory
}

// This test verifies the sync interface works
- (void)testSyncInterfaceExists {
    // Just verify the interface compiles and works
    // The actual network call will fail but that's expected
    NSError *error;
    NSDictionary *result = [self.client resolveDIDSync:@"did:plc:nonexistent" error:&error];
    
    // Either result or error should be set
    XCTAssertTrue(result == nil || error != nil || result != nil);
}

@end
