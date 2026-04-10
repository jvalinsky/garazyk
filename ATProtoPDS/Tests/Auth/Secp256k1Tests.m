#import <XCTest/XCTest.h>
#import "Auth/Secp256k1.h"
#import <CommonCrypto/CommonDigest.h>

@interface Secp256k1Tests : XCTestCase
@end

@implementation Secp256k1Tests

#pragma mark - Key Generation

- (void)testGenerateKeyPairReturnsValidKeys {
    NSError *error = nil;
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:&error];
    
    XCTAssertNotNil(keyPair, @"Key pair should be generated");
    XCTAssertNil(error, @"No error should occur");
    XCTAssertNotNil(keyPair.privateKey, @"Private key should not be nil");
    XCTAssertNotNil(keyPair.publicKey, @"Public key should not be nil");
    XCTAssertNotNil(keyPair.compressedPublicKey, @"Compressed public key should not be nil");
}

- (void)testGenerateKeyPairProducesDifferentKeysEachTime {
    NSError *error = nil;
    Secp256k1KeyPair *keyPair1 = [Secp256k1KeyPair generateKeyPair:&error];
    Secp256k1KeyPair *keyPair2 = [Secp256k1KeyPair generateKeyPair:&error];
    
    XCTAssertNotNil(keyPair1);
    XCTAssertNotNil(keyPair2);
    XCTAssertFalse([keyPair1.privateKey isEqualToData:keyPair2.privateKey],
                   @"Generated keys should be different each time");
}

- (void)testKeyPairWithPrivateKeyValidInput {
    uint8_t testPrivateKey[32] = {
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01
    };
    NSData *privateKey = [NSData dataWithBytes:testPrivateKey length:32];
    NSError *error = nil;
    
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair keyPairWithPrivateKey:privateKey error:&error];
    
    XCTAssertNotNil(keyPair, @"Key pair should be created from valid private key");
    XCTAssertNil(error, @"No error should occur");
    XCTAssertEqualObjects(keyPair.privateKey, privateKey);
}

- (void)testKeyPairWithPrivateKeyRejectsInvalidLength {
    NSData *shortKey = [@"short" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *longKey = [@"this_is_a_very_long_private_key_that_should_fail" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    
    XCTAssertNil([Secp256k1KeyPair keyPairWithPrivateKey:shortKey error:&error],
                 @"Should reject private key that is too short");
    XCTAssertNotNil(error, @"Error should be set for short key");
    XCTAssertEqual(error.code, Secp256k1ErrorInvalidPrivateKey);
    
    error = nil;
    XCTAssertNil([Secp256k1KeyPair keyPairWithPrivateKey:longKey error:&error],
                 @"Should reject private key that is too long");
    XCTAssertNotNil(error, @"Error should be set for long key");
    XCTAssertEqual(error.code, Secp256k1ErrorInvalidPrivateKey);
}

- (void)testKeyPairWithPrivateKeyRejectsZeroKey {
    uint8_t zeroKey[32] = {0};
    NSData *privateKey = [NSData dataWithBytes:zeroKey length:32];
    NSError *error = nil;
    
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair keyPairWithPrivateKey:privateKey error:&error];
    
    XCTAssertNil(keyPair, @"Should reject zero private key");
    XCTAssertNotNil(error, @"Error should occur for zero key");
}

#pragma mark - Signing

- (void)testSignHashReturnsValidSignature {
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:nil];
    XCTAssertNotNil(keyPair);
    
    uint8_t hashData[32] = {0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
                            0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
                            0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
                            0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f};
    NSData *hash = [NSData dataWithBytes:hashData length:32];
    NSError *error = nil;
    
    NSData *signature = [keyPair signHash:hash error:&error];
    
    XCTAssertNotNil(signature, @"Signature should be generated");
    XCTAssertNil(error, @"No error should occur");
    XCTAssertEqual(signature.length, 64, @"Signature should be 64 bytes");
}

- (void)testSignHashRejectsInvalidHashLength {
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:nil];
    XCTAssertNotNil(keyPair);
    
    NSData *shortHash = [@"short" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    
    XCTAssertNil([keyPair signHash:shortHash error:&error],
                 @"Should reject hash that is too short");
    XCTAssertNotNil(error, @"Error should be set for short hash");
    XCTAssertEqual(error.code, Secp256k1ErrorSigningFailed);
    
    error = nil;
    NSData *longHash = [@"this_is_a_very_long_hash_that_should_also_fail" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertNil([keyPair signHash:longHash error:&error],
                 @"Should reject hash that is too long");
    XCTAssertNotNil(error, @"Error should be set for long hash");
    XCTAssertEqual(error.code, Secp256k1ErrorSigningFailed);
}

- (void)testSignHashProducesDeterministicOutput {
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:nil];
    XCTAssertNotNil(keyPair);
    
    uint8_t hashData[32] = {0xab};
    NSData *hash = [NSData dataWithBytes:hashData length:32];
    
    NSData *sig1 = [keyPair signHash:hash error:nil];
    NSData *sig2 = [keyPair signHash:hash error:nil];
    
    XCTAssertNotNil(sig1);
    XCTAssertNotNil(sig2);
    XCTAssertEqualObjects(sig1, sig2, @"Same hash should produce same signature");
}

#pragma mark - Verification

- (void)testVerifySignatureValidSignatureReturnsTrue {
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:nil];
    XCTAssertNotNil(keyPair);
    
    uint8_t hashData[32] = {0x01};
    NSData *hash = [NSData dataWithBytes:hashData length:32];
    NSData *signature = [keyPair signHash:hash error:nil];
    
    XCTAssertNotNil(signature);
    
    NSError *error = nil;
    BOOL valid = [keyPair verifySignature:signature forHash:hash error:&error];
    
    XCTAssertTrue(valid, @"Valid signature should verify");
    XCTAssertNil(error, @"No error for valid signature");
}

- (void)testVerifySignatureInvalidSignatureReturnsFalse {
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:nil];
    XCTAssertNotNil(keyPair);
    
    uint8_t hashData[32] = {0x01};
    NSData *hash = [NSData dataWithBytes:hashData length:32];
    uint8_t invalidSig[64] = {0xff};
    NSData *invalidSignature = [NSData dataWithBytes:invalidSig length:64];
    
    NSError *error = nil;
    BOOL valid = [keyPair verifySignature:invalidSignature forHash:hash error:&error];
    
    XCTAssertFalse(valid, @"Invalid signature should not verify");
    XCTAssertNotNil(error, @"Error should be set for invalid signature");
}

- (void)testVerifySignatureRejectsInvalidLength {
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:nil];
    XCTAssertNotNil(keyPair);
    
    uint8_t hashData[32] = {0x01};
    NSData *hash = [NSData dataWithBytes:hashData length:32];
    NSData *shortSig = [@"short" dataUsingEncoding:NSUTF8StringEncoding];
    
    NSError *error = nil;
    BOOL valid = [keyPair verifySignature:shortSig forHash:hash error:&error];
    
    XCTAssertFalse(valid, @"Should reject signature with invalid length");
    XCTAssertEqual(error.code, Secp256k1ErrorInvalidSignature);
}

- (void)testVerifySignatureWithWrongHash {
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:nil];
    XCTAssertNotNil(keyPair);
    
    uint8_t hash1[32] = {0x01};
    uint8_t hash2[32] = {0x02};
    NSData *hash = [NSData dataWithBytes:hash1 length:32];
    NSData *wrongHash = [NSData dataWithBytes:hash2 length:32];
    NSData *signature = [keyPair signHash:hash error:nil];
    
    XCTAssertNotNil(signature);
    
    NSError *error = nil;
    BOOL valid = [keyPair verifySignature:signature forHash:wrongHash error:&error];
    
    XCTAssertFalse(valid, @"Signature should not verify against different hash");
}

#pragma mark - DID Key

- (void)testDidKeyStringFormat {
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:nil];
    XCTAssertNotNil(keyPair);
    
    NSString *didKey = keyPair.didKeyString;
    
    XCTAssertNotNil(didKey, @"DID key string should not be nil");
    XCTAssertTrue([didKey hasPrefix:@"did:key:z"], @"DID key should have correct prefix");
    XCTAssertTrue(didKey.length > 10, @"DID key should have substantial length");
}

#pragma mark - Singleton Interface

- (void)testSharedSingleton {
    Secp256k1 *instance1 = [Secp256k1 shared];
    Secp256k1 *instance2 = [Secp256k1 shared];
    
    XCTAssertNotNil(instance1);
    XCTAssertEqual(instance1, instance2, @"Shared should return singleton");
}

- (void)testSharedGenerateKeyPair {
    Secp256k1 *secp = [Secp256k1 shared];
    NSError *error = nil;
    
    Secp256k1KeyPair *keyPair = [secp generateKeyPairWithError:&error];
    
    XCTAssertNotNil(keyPair, @"Should generate key pair via singleton");
    XCTAssertNil(error, @"No error should occur");
}

- (void)testSharedSignAndVerify {
    Secp256k1 *secp = [Secp256k1 shared];
    NSError *error = nil;
    
    Secp256k1KeyPair *keyPair = [secp generateKeyPairWithError:&error];
    XCTAssertNotNil(keyPair);
    
    NSData *hash = [@"test_data_for_signing" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *hashSha256 = [self sha256:hash];
    
    NSData *signature = [secp signHash:hashSha256 withPrivateKey:keyPair.privateKey error:&error];
    XCTAssertNotNil(signature, @"Should produce signature");
    XCTAssertNil(error, @"No error during signing");
    
    BOOL valid = [secp verifySignature:signature forHash:hashSha256 withPublicKey:keyPair.publicKey error:&error];
    XCTAssertTrue(valid, @"Signature should verify with singleton method");
}

- (void)testSharedVerifyRejectsInvalidPublicKeyLength {
    Secp256k1 *secp = [Secp256k1 shared];
    NSError *error = nil;
    
    NSData *fakePublicKey = [@"short" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *hash = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *signature = [@"1234567890123456789012345678901234567890123456789012345678901234" dataUsingEncoding:NSUTF8StringEncoding];
    
    BOOL valid = [secp verifySignature:signature forHash:hash withPublicKey:fakePublicKey error:&error];
    
    XCTAssertFalse(valid, @"Should reject public key with invalid length");
    XCTAssertEqual(error.code, Secp256k1ErrorInvalidPublicKey);
}

#pragma mark - Public Key Normalization

- (void)testNormalizedPublicKeyValidCompressed {
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:nil];
    XCTAssertNotNil(keyPair);
    
    NSData *compressed = keyPair.compressedPublicKey;
    XCTAssertEqual(compressed.length, 33, @"Compressed key should be 33 bytes");
    
    NSError *error = nil;
    Secp256k1 *secp = [Secp256k1 shared];
    NSData *normalized = [secp normalizedPublicKey:compressed error:&error];
    
    XCTAssertNotNil(normalized, @"Should normalize compressed key");
    XCTAssertNil(error, @"No error should occur");
    XCTAssertEqual(normalized.length, 65, @"Normalized key should be 65 bytes");
}

- (void)testNormalizedPublicKeyValidUncompressed {
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:nil];
    XCTAssertNotNil(keyPair);
    
    NSData *uncompressed = keyPair.publicKey;
    XCTAssertEqual(uncompressed.length, 65, @"Uncompressed key should be 65 bytes");
    
    NSError *error = nil;
    Secp256k1 *secp = [Secp256k1 shared];
    NSData *normalized = [secp normalizedPublicKey:uncompressed error:&error];
    
    XCTAssertNotNil(normalized, @"Should normalize uncompressed key");
    XCTAssertNil(error, @"No error should occur");
    XCTAssertEqual(normalized.length, 65, @"Normalized key should be 65 bytes");
}

- (void)testNormalizedPublicKeyRejectsInvalidLength {
    Secp256k1 *secp = [Secp256k1 shared];
    NSError *error = nil;
    
    NSData *shortKey = [@"short" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertNil([secp normalizedPublicKey:shortKey error:&error],
                 @"Should reject key with invalid length");
    XCTAssertNotNil(error, @"Error should be set");
    XCTAssertEqual(error.code, Secp256k1ErrorInvalidPublicKey);
}

#pragma mark - Error Domain

- (void)testErrorDomainIsCorrect {
    XCTAssertNotNil(Secp256k1ErrorDomain);
    XCTAssertTrue([Secp256k1ErrorDomain isEqualToString:@"com.atproto.pds.secp256k1"]);
}

#pragma mark - Helpers

- (NSData *)sha256:(NSData *)data {
    uint8_t hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    return [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
}

@end
