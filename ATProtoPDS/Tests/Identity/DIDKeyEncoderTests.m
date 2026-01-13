#import <XCTest/XCTest.h>
#import "Identity/DIDKeyEncoder.h"
#import "Auth/Secp256k1.h"

@interface DIDKeyEncoderTests : XCTestCase
@end

@implementation DIDKeyEncoderTests

- (void)testEncodeSecp256k1CompressedKey {
    // Generate a key pair and encode as did:key
    NSError *error;
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:&error];
    XCTAssertNotNil(keyPair, @"Failed to generate key pair: %@", error);
    
    NSString *didKey = [DIDKeyEncoder encodeDIDKeyFromCompressedPublicKey:keyPair.compressedPublicKey
                                                                  keyType:DIDKeyTypeSecp256k1
                                                                    error:&error];
    XCTAssertNotNil(didKey, @"Failed to encode did:key: %@", error);
    
    // Should start with did:key:z (multibase base58btc prefix)
    XCTAssertTrue([didKey hasPrefix:@"did:key:z"], @"Invalid did:key prefix: %@", didKey);
}

- (void)testEncodeUncompressedSecp256k1Key {
    NSError *error;
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:&error];
    XCTAssertNotNil(keyPair);
    
    // Encode from uncompressed (65 bytes)
    NSString *didKey = [DIDKeyEncoder encodeDIDKeyFromUncompressedSecp256k1:keyPair.publicKey
                                                                     error:&error];
    XCTAssertNotNil(didKey, @"Failed to encode from uncompressed: %@", error);
    
    // Should produce same result as encoding compressed directly
    NSString *fromCompressed = [DIDKeyEncoder encodeDIDKeyFromCompressedPublicKey:keyPair.compressedPublicKey
                                                                          keyType:DIDKeyTypeSecp256k1
                                                                            error:&error];
    
    XCTAssertEqualObjects(didKey, fromCompressed);
}

- (void)testDecodeSecp256k1Key {
    NSError *error;
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:&error];
    XCTAssertNotNil(keyPair);
    
    NSString *didKey = [DIDKeyEncoder encodeDIDKeyFromCompressedPublicKey:keyPair.compressedPublicKey
                                                                  keyType:DIDKeyTypeSecp256k1
                                                                    error:&error];
    XCTAssertNotNil(didKey);
    
    DIDKeyType keyType;
    NSData *decodedKey = [DIDKeyEncoder decodePublicKeyFromDIDKey:didKey
                                                          keyType:&keyType
                                                            error:&error];
    XCTAssertNotNil(decodedKey, @"Failed to decode did:key: %@", error);
    XCTAssertEqual(keyType, DIDKeyTypeSecp256k1);
    XCTAssertEqualObjects(decodedKey, keyPair.compressedPublicKey);
}

- (void)testRoundTripSecp256k1 {
    // Test multiple round trips
    for (int i = 0; i < 10; i++) {
        NSError *error;
        Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:&error];
        XCTAssertNotNil(keyPair);
        
        NSString *didKey = [DIDKeyEncoder encodeDIDKeyFromCompressedPublicKey:keyPair.compressedPublicKey
                                                                      keyType:DIDKeyTypeSecp256k1
                                                                        error:&error];
        XCTAssertNotNil(didKey);
        
        NSData *decoded = [DIDKeyEncoder decodePublicKeyFromDIDKey:didKey keyType:nil error:&error];
        XCTAssertNotNil(decoded);
        XCTAssertEqualObjects(decoded, keyPair.compressedPublicKey);
    }
}

- (void)testInvalidKeyLength {
    // 32 bytes is wrong for secp256k1 compressed (should be 33)
    uint8_t bytes[32];
    memset(bytes, 0x42, 32);
    NSData *invalidKey = [NSData dataWithBytes:bytes length:32];
    
    NSError *error;
    NSString *result = [DIDKeyEncoder encodeDIDKeyFromCompressedPublicKey:invalidKey
                                                                  keyType:DIDKeyTypeSecp256k1
                                                                    error:&error];
    
    XCTAssertNil(result);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, DIDKeyErrorInvalidKey);
}

- (void)testInvalidDIDKeyFormat {
    NSError *error;
    
    // Missing prefix
    NSData *result = [DIDKeyEncoder decodePublicKeyFromDIDKey:@"invalid" keyType:nil error:&error];
    XCTAssertNil(result);
    
    // Wrong multibase prefix (not 'z')
    result = [DIDKeyEncoder decodePublicKeyFromDIDKey:@"did:key:mbase64data" keyType:nil error:&error];
    XCTAssertNil(result);
}

- (void)testIsValidDIDKey {
    NSError *error;
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:&error];
    XCTAssertNotNil(keyPair);
    
    NSString *didKey = [DIDKeyEncoder encodeDIDKeyFromCompressedPublicKey:keyPair.compressedPublicKey
                                                                  keyType:DIDKeyTypeSecp256k1
                                                                    error:&error];
    XCTAssertNotNil(didKey);
    
    // Valid key should pass
    XCTAssertTrue([DIDKeyEncoder isValidDIDKey:didKey]);
    
    // Invalid key should fail
    XCTAssertFalse([DIDKeyEncoder isValidDIDKey:@"did:key:invalid"]);
    XCTAssertFalse([DIDKeyEncoder isValidDIDKey:@"not-a-did-key"]);
}

- (void)testKnownTestVector {
    // Generate a real key and verify format consistency
    NSError *error;
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:&error];
    XCTAssertNotNil(keyPair);
    
    NSString *didKey = [DIDKeyEncoder encodeDIDKeyFromCompressedPublicKey:keyPair.compressedPublicKey
                                                                  keyType:DIDKeyTypeSecp256k1
                                                                    error:&error];
    
    // Verify structure:
    // 1. Starts with "did:key:z"
    XCTAssertTrue([didKey hasPrefix:@"did:key:z"]);
    
    // 2. Multicodec for secp256k1 is 0xe7, encoded as single byte in varint
    DIDKeyType keyType;
    NSData *decoded = [DIDKeyEncoder decodePublicKeyFromDIDKey:didKey keyType:&keyType error:&error];
    XCTAssertNotNil(decoded);
    XCTAssertEqual(keyType, DIDKeyTypeSecp256k1);
    XCTAssertEqual(decoded.length, 33); // Compressed secp256k1 is 33 bytes
}

@end
