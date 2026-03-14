// Tests for DPoPUtil and DPoPToken (RFC 9449 DPoP proof creation).
// Apple-only — requires Security.framework for key generation.

#if defined(__APPLE__)

#import <XCTest/XCTest.h>
#import "Auth/DPoPUtil.h"
#import <Security/Security.h>

NS_ASSUME_NONNULL_BEGIN

@interface DPoPUtilTests : XCTestCase
@property (nonatomic, assign) SecKeyRef privateKey;
@property (nonatomic, assign) SecKeyRef publicKey;
@end

@implementation DPoPUtilTests

- (void)setUp {
    [super setUp];

    // Generate an EC P-256 key pair for testing
    NSDictionary *params = @{
        (__bridge id)kSecAttrKeyType:       (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeySizeInBits: @256
    };
    CFErrorRef cfErr = NULL;
    SecKeyRef privKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)params, &cfErr);
    if (cfErr) {
        CFRelease(cfErr);
    }
    XCTAssertNotEqual(privKey, (SecKeyRef)NULL, @"Failed to generate test EC key");
    self.privateKey = privKey;
    self.publicKey  = SecKeyCopyPublicKey(privKey);
}

- (void)tearDown {
    if (self.privateKey)  { CFRelease(self.privateKey);  self.privateKey  = NULL; }
    if (self.publicKey)   { CFRelease(self.publicKey);   self.publicKey   = NULL; }
    [super tearDown];
}

#pragma mark - DPoPToken creation

- (void)testCreateDPoPTokenSucceedsForValidInputs {
    NSError *error = nil;
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"POST"
                                                  uri:@"https://pds.example.com/xrpc/com.atproto.server.createSession"
                                               nonce:nil
                                                 key:self.privateKey
                                               error:&error];
    XCTAssertNotNil(token, @"createDPoP must succeed for valid inputs: %@", error);
    XCTAssertNil(error);
}

- (void)testDPoPTokenHTMMatchesInput {
    NSError *error = nil;
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"GET"
                                                  uri:@"https://pds.example.com/xrpc/com.atproto.sync.getRepo"
                                               nonce:nil
                                                 key:self.privateKey
                                               error:&error];
    XCTAssertNotNil(token);
    XCTAssertEqualObjects(token.htm, @"GET", @"htm must match the input HTTP method");
}

- (void)testDPoPTokenHTUIsCanonical {
    NSError *error = nil;
    // URI with query + fragment — canonical HTU should drop both
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"GET"
                                                  uri:@"https://pds.example.com/xrpc/foo?bar=1#section"
                                               nonce:nil
                                                 key:self.privateKey
                                               error:&error];
    XCTAssertNotNil(token);
    XCTAssertFalse([token.htu containsString:@"?"],
                   @"Canonical HTU must not contain a query string");
    XCTAssertFalse([token.htu containsString:@"#"],
                   @"Canonical HTU must not contain a fragment");
}

- (void)testDPoPTokenContainsNonceWhenProvided {
    NSError *error = nil;
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"POST"
                                                  uri:@"https://pds.example.com/xrpc/test"
                                               nonce:@"test-nonce-12345"
                                                 key:self.privateKey
                                               error:&error];
    XCTAssertNotNil(token);
    XCTAssertEqualObjects(token.nonce, @"test-nonce-12345",
                          @"Token nonce must match provided nonce");
}

- (void)testDPoPTokenIATIsRecent {
    NSError *error = nil;
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"GET"
                                                  uri:@"https://pds.example.com/xrpc/test"
                                               nonce:nil
                                                 key:self.privateKey
                                               error:&error];
    XCTAssertNotNil(token);
    NSTimeInterval ageSeconds = [[NSDate date] timeIntervalSinceDate:token.iat];
    XCTAssertLessThan(fabs(ageSeconds), 10.0,
                      @"iat must be within 10 seconds of the current time");
}

- (void)testDPoPTokenJTIIsNonEmpty {
    NSError *error = nil;
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"POST"
                                                  uri:@"https://pds.example.com/xrpc/test"
                                               nonce:nil
                                                 key:self.privateKey
                                               error:&error];
    XCTAssertNotNil(token);
    XCTAssertGreaterThan(token.jti.length, (NSUInteger)0,
                         @"jti must be non-empty");
}

- (void)testDPoPTokenJWTIsThreeParts {
    NSError *error = nil;
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"POST"
                                                  uri:@"https://pds.example.com/xrpc/test"
                                               nonce:nil
                                                 key:self.privateKey
                                               error:&error];
    XCTAssertNotNil(token);
    NSArray *parts = [token.jwt componentsSeparatedByString:@"."];
    XCTAssertEqual(parts.count, (NSUInteger)3,
                   @"DPoP JWT must be a three-part dot-separated string");
}

#pragma mark - DPoPUtil verify

- (void)testVerifyDPoPAcceptsValidProof {
    NSError *error = nil;
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"GET"
                                                  uri:@"https://pds.example.com/xrpc/verify.test"
                                               nonce:nil
                                                 key:self.privateKey
                                               error:&error];
    XCTAssertNotNil(token, @"Token creation must succeed before verification");

    BOOL valid = [DPoPUtil verifyDPoP:token.jwt
                         withPublicKey:self.publicKey
                                method:@"GET"
                                   uri:@"https://pds.example.com/xrpc/verify.test"
                                 nonce:nil
                                 error:&error];
    XCTAssertTrue(valid, @"verifyDPoP must return YES for a fresh, valid proof: %@", error);
}

- (void)testVerifyDPoPRejectsWrongMethod {
    NSError *error = nil;
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"GET"
                                                  uri:@"https://pds.example.com/xrpc/method.test"
                                               nonce:nil
                                                 key:self.privateKey
                                               error:&error];
    XCTAssertNotNil(token);

    BOOL valid = [DPoPUtil verifyDPoP:token.jwt
                         withPublicKey:self.publicKey
                                method:@"POST"          // wrong method
                                   uri:@"https://pds.example.com/xrpc/method.test"
                                 nonce:nil
                                 error:&error];
    XCTAssertFalse(valid, @"verifyDPoP must reject a proof bound to a different HTTP method");
}

- (void)testVerifyDPoPRejectsWrongURI {
    NSError *error = nil;
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"POST"
                                                  uri:@"https://pds.example.com/xrpc/correct.path"
                                               nonce:nil
                                                 key:self.privateKey
                                               error:&error];
    XCTAssertNotNil(token);

    BOOL valid = [DPoPUtil verifyDPoP:token.jwt
                         withPublicKey:self.publicKey
                                method:@"POST"
                                   uri:@"https://pds.example.com/xrpc/other.path"  // wrong URI
                                 nonce:nil
                                 error:&error];
    XCTAssertFalse(valid, @"verifyDPoP must reject a proof bound to a different URI");
}

#pragma mark - DPoPToken header/payload

- (void)testDPoPTokenHeaderContainsTypDPoP {
    NSError *error = nil;
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"GET"
                                                  uri:@"https://pds.example.com/xrpc/header.test"
                                               nonce:nil
                                                 key:self.privateKey
                                               error:&error];
    XCTAssertNotNil(token);
    NSDictionary *header = [token header];
    XCTAssertEqualObjects(header[@"typ"], @"dpop+jwt",
                          @"DPoP JWT header must have typ=dpop+jwt");
}

- (void)testDPoPTokenPayloadContainsHTMAndHTU {
    NSError *error = nil;
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"DELETE"
                                                  uri:@"https://pds.example.com/xrpc/payload.test"
                                               nonce:nil
                                                 key:self.privateKey
                                               error:&error];
    XCTAssertNotNil(token);
    NSDictionary *payload = [token payload];
    XCTAssertEqualObjects(payload[@"htm"], @"DELETE");
    XCTAssertNotNil(payload[@"htu"]);
    XCTAssertNotNil(payload[@"jti"]);
    XCTAssertNotNil(payload[@"iat"]);
}

@end

NS_ASSUME_NONNULL_END

#else

// Stub so the test file compiles on GNUstep/Linux without Security.framework

#import "Compat/XCTest/XCTest.h"

@interface DPoPUtilTests : XCTestCase
@end
@implementation DPoPUtilTests
- (void)testSkippedOnGNUstep {
    XCTSkip(@"DPoPUtilTests require Security.framework (Apple only).");
}
@end

#endif
