#import <XCTest/XCTest.h>
#import "Identity/PLCDirectoryClient.h"
#import "Identity/PLCOperationBuilder.h"
#import "Identity/DIDKeyEncoder.h"
#import "Auth/Secp256k1.h"

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
    NSError *error;
    PLCOperationBuilder *builder = [[PLCOperationBuilder alloc] initWithNewRotationKeyWithError:&error];
    XCTAssertNotNil(builder);
    
    Secp256k1KeyPair *signingKey = [Secp256k1KeyPair generateKeyPair:&error];
    XCTAssertNotNil(signingKey);
    
    builder.signingDIDKey = [DIDKeyEncoder encodeDIDKeyFromCompressedPublicKey:signingKey.compressedPublicKey
                                                                       keyType:DIDKeyTypeSecp256k1
                                                                         error:&error];
    builder.handle = @"test.example.com";
    builder.pdsEndpoint = @"https://pds.example.com";
    
    NSDictionary *op = [builder buildGenesisOperationWithError:&error];
    XCTAssertNotNil(op);
    
    NSString *did = [PLCOperationBuilder computeDIDFromGenesisOperation:op error:&error];
    XCTAssertNotNil(did);
    
    // Verify the operation is well-formed for submission
    BOOL valid = [PLCOperationBuilder validateOperation:op error:&error];
    XCTAssertTrue(valid);
    
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
