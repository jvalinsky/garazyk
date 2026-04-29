#import <XCTest/XCTest.h>
#import "TutorialIdentityService.h"

@interface TutorialIdentityServiceTests : XCTestCase
@property (nonatomic, strong) NSString *cacheDir;
@property (nonatomic, strong) TutorialIdentityService *service;
@end

@implementation TutorialIdentityServiceTests

- (void)setUp {
    [super setUp];
    self.cacheDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"identity_test_%@", [[NSUUID UUID] UUIDString]]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.cacheDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    self.service = [[TutorialIdentityService alloc] initWithCacheDirectory:self.cacheDir];
}

- (void)tearDown {
    self.service = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.cacheDir error:nil];
    [super tearDown];
}

- (void)testResolveDidWebLocal {
    NSError *error = nil;
    TutorialDIDDocument *doc = [self.service resolveDID:@"did:web:localhost:2583" error:&error];
    XCTAssertNotNil(doc, @"Local did:web resolution should succeed");
    XCTAssertNil(error);
    XCTAssertEqualObjects(doc.did, @"did:web:localhost:2583", @"DID document should have correct id");
}

- (void)testResolveDidWebHasHandle {
    NSError *error = nil;
    TutorialDIDDocument *doc = [self.service resolveDID:@"did:web:localhost:2583" error:&error];
    XCTAssertNotNil(doc);
    XCTAssertNotNil(doc.handle, @"DID document should have handle");
    XCTAssertTrue(doc.handle.length > 0, @"Handle should not be empty");
}

- (void)testResolveDidWebHasVerificationMethod {
    NSError *error = nil;
    TutorialDIDDocument *doc = [self.service resolveDID:@"did:web:localhost:2583" error:&error];
    XCTAssertNotNil(doc);
    XCTAssertNotNil(doc.verificationMethods, @"DID document should have verificationMethods");
    XCTAssertTrue(doc.verificationMethods.count > 0, @"Should have at least one verification method");
}

- (void)testResolveDidWebHasService {
    NSError *error = nil;
    TutorialDIDDocument *doc = [self.service resolveDID:@"did:web:localhost:2583" error:&error];
    XCTAssertNotNil(doc);
    XCTAssertNotNil(doc.services, @"DID document should have services");
    XCTAssertTrue(doc.services.count > 0, @"Should have at least one service");
}

- (void)testResolveDidPlcRequiresNetwork {
    // did:plc resolution requires network access — may fail in test environments
    NSError *error = nil;
    TutorialDIDDocument *doc = [self.service resolveDID:@"did:plc:ewvi7nxzy7lk2pg3z7hw4r6e" error:&error];
    // Don't assert success/failure since network may be unavailable
    (void)doc;
}

- (void)testCacheBehavior {
    NSError *error = nil;
    TutorialDIDDocument *doc1 = [self.service resolveDID:@"did:web:localhost:2583" error:&error];
    XCTAssertNotNil(doc1);

    TutorialDIDDocument *doc2 = [self.service resolveDID:@"did:web:localhost:2583" error:&error];
    XCTAssertNotNil(doc2);
    XCTAssertEqualObjects(doc1.did, doc2.did, @"Cached resolution should return same DID");
}

- (void)testClearCache {
    [self.service resolveDID:@"did:web:localhost:2583" error:nil];
    [self.service clearCache];
    NSError *error = nil;
    TutorialDIDDocument *doc = [self.service resolveDID:@"did:web:localhost:2583" error:&error];
    XCTAssertNotNil(doc, @"Should re-resolve after cache clear");
}

- (void)testVerifyHandle {
    NSError *error = nil;
    // Verify that the DID document's handle matches
    BOOL valid = [self.service verifyHandle:@"handle.localhost"
                                     forDID:@"did:web:localhost:2583"
                                      error:&error];
    // May fail in test environment without DNS, but shouldn't crash
    (void)valid;
}

@end
