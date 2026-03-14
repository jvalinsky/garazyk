// Extended tests for Secp256k1: key generation, signing, verification, and key derivation.

#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif

#import "Auth/Secp256k1.h"
#import <CommonCrypto/CommonDigest.h>

@interface Secp256k1ExtendedTests : XCTestCase
@end

@implementation Secp256k1ExtendedTests

#pragma mark - Key Generation

- (void)testGenerateKeyPairProduces32BytePrivateKey {
    NSError *error = nil;
    Secp256k1KeyPair *pair = [Secp256k1KeyPair generateKeyPair:&error];
    XCTAssertNotNil(pair, @"generateKeyPair: must succeed: %@", error);
    XCTAssertNil(error);
    XCTAssertEqual(pair.privateKey.length, (NSUInteger)32,
                   @"Private key must be 32 bytes");
}

- (void)testGenerateKeyPairProduces65ByteUncompressedPublicKey {
    Secp256k1KeyPair *pair = [Secp256k1KeyPair generateKeyPair:nil];
    XCTAssertNotNil(pair);
    XCTAssertEqual(pair.publicKey.length, (NSUInteger)65,
                   @"Uncompressed public key must be 65 bytes");
    const uint8_t *bytes = pair.publicKey.bytes;
    XCTAssertEqual(bytes[0], (uint8_t)0x04,
                   @"Uncompressed point must start with 0x04");
}

- (void)testGenerateKeyPairProduces33ByteCompressedPublicKey {
    Secp256k1KeyPair *pair = [Secp256k1KeyPair generateKeyPair:nil];
    XCTAssertNotNil(pair);
    XCTAssertEqual(pair.compressedPublicKey.length, (NSUInteger)33,
                   @"Compressed public key must be 33 bytes");
    const uint8_t *bytes = pair.compressedPublicKey.bytes;
    XCTAssertTrue(bytes[0] == 0x02 || bytes[0] == 0x03,
                  @"Compressed point prefix must be 0x02 or 0x03");
}

- (void)testKeyPairFromPrivateKeyDerivesMatchingPublicKey {
    NSError *error = nil;
    Secp256k1KeyPair *original = [Secp256k1KeyPair generateKeyPair:&error];
    XCTAssertNotNil(original);

    Secp256k1KeyPair *derived = [Secp256k1KeyPair keyPairWithPrivateKey:original.privateKey
                                                                   error:&error];
    XCTAssertNotNil(derived, @"keyPairWithPrivateKey:error: must succeed: %@", error);
    XCTAssertEqualObjects(derived.compressedPublicKey, original.compressedPublicKey,
                          @"Re-derived compressed public key must match original");
    XCTAssertEqualObjects(derived.publicKey, original.publicKey,
                          @"Re-derived uncompressed public key must match original");
}

- (void)testKeyPairWithInvalidPrivateKeyReturnsNil {
    NSData *zeros = [NSData dataWithLength:32]; // All-zero private key is invalid
    NSError *error = nil;
    Secp256k1KeyPair *pair = [Secp256k1KeyPair keyPairWithPrivateKey:zeros error:&error];
    XCTAssertNil(pair, @"All-zero private key must be rejected");
}

#pragma mark - Sign & Verify

- (NSData *)sha256OfString:(NSString *)str {
    NSData *data = [str dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    return [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
}

- (void)testSignAndVerifyWithSameKeyPair {
    NSError *error = nil;
    Secp256k1KeyPair *pair = [Secp256k1KeyPair generateKeyPair:&error];
    XCTAssertNotNil(pair);

    NSData *hash = [self sha256OfString:@"ATProto signing test"];
    NSData *signature = [pair signHash:hash error:&error];
    XCTAssertNotNil(signature, @"signHash:error: must produce a signature: %@", error);
    XCTAssertGreaterThan(signature.length, (NSUInteger)0);

    BOOL verified = [pair verifySignature:signature forHash:hash error:&error];
    XCTAssertTrue(verified, @"Signature must verify with the same key pair: %@", error);
}

- (void)testVerifyFailsWithWrongKey {
    NSError *error = nil;
    Secp256k1KeyPair *pairA = [Secp256k1KeyPair generateKeyPair:nil];
    Secp256k1KeyPair *pairB = [Secp256k1KeyPair generateKeyPair:nil];

    NSData *hash = [self sha256OfString:@"message"];
    NSData *signature = [pairA signHash:hash error:nil];
    XCTAssertNotNil(signature);

    BOOL verified = [pairB verifySignature:signature forHash:hash error:&error];
    XCTAssertFalse(verified, @"Signature from key A must not verify with key B");
}

- (void)testVerifyFailsWithTamperedHash {
    Secp256k1KeyPair *pair = [Secp256k1KeyPair generateKeyPair:nil];
    NSData *hash = [self sha256OfString:@"original message"];
    NSData *signature = [pair signHash:hash error:nil];

    NSData *tamperedHash = [self sha256OfString:@"tampered message"];
    BOOL verified = [pair verifySignature:signature forHash:tamperedHash error:nil];
    XCTAssertFalse(verified, @"Signature must not verify against a different hash");
}

#pragma mark - DID Key String

- (void)testDIDKeyStringFormat {
    Secp256k1KeyPair *pair = [Secp256k1KeyPair generateKeyPair:nil];
    NSString *didKey = [pair didKeyString];
    XCTAssertNotNil(didKey);
    XCTAssertTrue([didKey hasPrefix:@"did:key:"],
                  @"DID key must start with 'did:key:', got: %@", didKey);
}

@end
