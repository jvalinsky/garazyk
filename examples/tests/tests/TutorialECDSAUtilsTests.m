#import <XCTest/XCTest.h>
#import "TutorialECDSAUtils.h"
#import "TutorialBase64URL.h"

@interface TutorialECDSAUtilsTests : XCTestCase
@end

@implementation TutorialECDSAUtilsTests

- (void)testGenerateKeyPair {
    NSError *error = nil;
    TutorialECDSAKeyPair *keyPair = [TutorialECDSAUtils generateKeyPairWithError:&error];
    XCTAssertNotNil(keyPair, @"Key generation should succeed");
    XCTAssertNil(error, @"No error should be returned");
}

- (void)testKeyPairHasJWK {
    NSError *error = nil;
    TutorialECDSAKeyPair *keyPair = [TutorialECDSAUtils generateKeyPairWithError:&error];
    XCTAssertNotNil(keyPair);

    NSDictionary *publicJWK = keyPair.publicJWK;
    XCTAssertEqualObjects(publicJWK[@"kty"], @"EC", @"Key type should be EC");
    XCTAssertEqualObjects(publicJWK[@"crv"], @"P-256", @"Curve should be P-256");
    XCTAssertNotNil(publicJWK[@"x"], @"x coordinate should be present");
    XCTAssertNotNil(publicJWK[@"y"], @"y coordinate should be present");

    NSDictionary *privateJWK = keyPair.privateJWK;
    XCTAssertNotNil(privateJWK[@"d"], @"Private key scalar d should be present");
    XCTAssertEqualObjects(privateJWK[@"x"], publicJWK[@"x"], @"x should match");
    XCTAssertEqualObjects(privateJWK[@"y"], publicJWK[@"y"], @"y should match");
}

- (void)testKeyPairHasThumbprint {
    NSError *error = nil;
    TutorialECDSAKeyPair *keyPair = [TutorialECDSAUtils generateKeyPairWithError:&error];
    XCTAssertNotNil(keyPair);
    XCTAssertNotNil(keyPair.thumbprint, @"Thumbprint should be generated");
    XCTAssertTrue(keyPair.thumbprint.length > 0, @"Thumbprint should not be empty");
}

- (void)testKeyPairHasPublicKeyData {
    NSError *error = nil;
    TutorialECDSAKeyPair *keyPair = [TutorialECDSAUtils generateKeyPairWithError:&error];
    XCTAssertNotNil(keyPair);
    XCTAssertNotNil(keyPair.publicKeyData, @"Public key data should be present");
    XCTAssertEqual(keyPair.publicKeyData.length, 65, @"Uncompressed EC point should be 65 bytes");
    XCTAssertEqual(((const uint8_t *)keyPair.publicKeyData.bytes)[0], 0x04,
                   @"First byte should be 0x04 (uncompressed point)");
}

- (void)testSignAndVerify {
    NSError *error = nil;
    TutorialECDSAKeyPair *keyPair = [TutorialECDSAUtils generateKeyPairWithError:&error];
    XCTAssertNotNil(keyPair);

    NSData *message = [@"Hello, ATProto!" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *signature = [TutorialECDSAUtils signData:message withPrivateKey:keyPair.privateJWK error:&error];
    XCTAssertNotNil(signature, @"Signing should succeed");
    XCTAssertNil(error, @"No error on signing");
    XCTAssertEqual(signature.length, 64, @"ES256 raw signature should be 64 bytes");
}

- (void)testVerifyWithCorrectKey {
    NSError *error = nil;
    TutorialECDSAKeyPair *keyPair = [TutorialECDSAUtils generateKeyPairWithError:&error];
    XCTAssertNotNil(keyPair);

    NSData *message = [@"Verify this message" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *signature = [TutorialECDSAUtils signData:message withPrivateKey:keyPair.privateJWK error:nil];
    XCTAssertNotNil(signature);

    BOOL valid = [TutorialECDSAUtils verifySignature:signature forData:message withPublicKey:keyPair.publicJWK error:nil];
    XCTAssertTrue(valid, @"Signature should verify with correct public key");
}

- (void)testVerifyWithWrongKeyFails {
    NSError *error = nil;
    TutorialECDSAKeyPair *keyPair1 = [TutorialECDSAUtils generateKeyPairWithError:&error];
    TutorialECDSAKeyPair *keyPair2 = [TutorialECDSAUtils generateKeyPairWithError:&error];
    XCTAssertNotNil(keyPair1);
    XCTAssertNotNil(keyPair2);

    NSData *message = [@"Signed by key1" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *signature = [TutorialECDSAUtils signData:message withPrivateKey:keyPair1.privateJWK error:nil];
    XCTAssertNotNil(signature);

    NSError *verifyError = nil;
    BOOL valid = [TutorialECDSAUtils verifySignature:signature forData:message withPublicKey:keyPair2.publicJWK error:&verifyError];
    XCTAssertFalse(valid, @"Signature should NOT verify with wrong public key");
}

- (void)testThumbprintDeterministic {
    NSError *error = nil;
    TutorialECDSAKeyPair *keyPair = [TutorialECDSAUtils generateKeyPairWithError:&error];
    XCTAssertNotNil(keyPair);

    NSString *tp1 = [TutorialECDSAUtils thumbprintForJWK:keyPair.publicJWK error:nil];
    NSString *tp2 = [TutorialECDSAUtils thumbprintForJWK:keyPair.publicJWK error:nil];
    XCTAssertEqualObjects(tp1, tp2, @"Same JWK should produce same thumbprint");
}

- (void)testDifferentKeysDifferentThumbprints {
    NSError *error = nil;
    TutorialECDSAKeyPair *keyPair1 = [TutorialECDSAUtils generateKeyPairWithError:&error];
    TutorialECDSAKeyPair *keyPair2 = [TutorialECDSAUtils generateKeyPairWithError:&error];
    XCTAssertNotNil(keyPair1);
    XCTAssertNotNil(keyPair2);

    NSString *tp1 = [TutorialECDSAUtils thumbprintForJWK:keyPair1.publicJWK error:nil];
    NSString *tp2 = [TutorialECDSAUtils thumbprintForJWK:keyPair2.publicJWK error:nil];
    XCTAssertNotEqualObjects(tp1, tp2, @"Different keys should produce different thumbprints");
}

@end
