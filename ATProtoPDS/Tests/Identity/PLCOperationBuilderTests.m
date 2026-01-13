#import <XCTest/XCTest.h>
#import "Identity/PLCOperationBuilder.h"
#import "Identity/DIDKeyEncoder.h"
#import "Auth/Secp256k1.h"

@interface PLCOperationBuilderTests : XCTestCase
@end

@implementation PLCOperationBuilderTests

- (void)testInitWithNewRotationKey {
    NSError *error;
    PLCOperationBuilder *builder = [[PLCOperationBuilder alloc] initWithNewRotationKeyWithError:&error];
    
    XCTAssertNotNil(builder, @"Failed to create builder: %@", error);
    XCTAssertEqual(builder.rotationPrivateKey.length, 32);
    XCTAssertTrue([builder.rotationDIDKey hasPrefix:@"did:key:z"], @"Invalid rotation did:key format: %@", builder.rotationDIDKey);
}

- (void)testInitWithExistingKey {
    // Generate a key
    NSError *error;
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:&error];
    XCTAssertNotNil(keyPair);
    
    // Create builder with that key
    PLCOperationBuilder *builder = [[PLCOperationBuilder alloc] initWithRotationPrivateKey:keyPair.privateKey
                                                                                     error:&error];
    
    XCTAssertNotNil(builder, @"Failed to create builder: %@", error);
    XCTAssertEqualObjects(builder.rotationPrivateKey, keyPair.privateKey);
}

- (void)testBuildGenesisOperation {
    NSError *error;
    PLCOperationBuilder *builder = [[PLCOperationBuilder alloc] initWithNewRotationKeyWithError:&error];
    XCTAssertNotNil(builder);
    
    // Generate signing key
    Secp256k1KeyPair *signingKey = [Secp256k1KeyPair generateKeyPair:&error];
    XCTAssertNotNil(signingKey);
    
    NSString *signingDIDKey = [DIDKeyEncoder encodeDIDKeyFromCompressedPublicKey:signingKey.compressedPublicKey
                                                                         keyType:DIDKeyTypeSecp256k1
                                                                           error:&error];
    XCTAssertNotNil(signingDIDKey);
    
    builder.signingDIDKey = signingDIDKey;
    builder.handle = @"alice.test";
    builder.pdsEndpoint = @"https://pds.test";
    
    NSDictionary *op = [builder buildGenesisOperationWithError:&error];
    
    XCTAssertNotNil(op, @"Failed to build genesis operation: %@", error);
    
    // Verify required fields
    XCTAssertEqualObjects(op[@"type"], @"plc_operation");
    XCTAssertNotNil(op[@"rotationKeys"]);
    XCTAssertNotNil(op[@"verificationMethods"]);
    XCTAssertNotNil(op[@"alsoKnownAs"]);
    XCTAssertNotNil(op[@"services"]);
    XCTAssertNotNil(op[@"sig"]);
    
    // prev should be null for genesis
    XCTAssertEqualObjects(op[@"prev"], [NSNull null]);
}

- (void)testGenesisOperationStructure {
    NSError *error;
    PLCOperationBuilder *builder = [[PLCOperationBuilder alloc] initWithNewRotationKeyWithError:&error];
    XCTAssertNotNil(builder);
    
    Secp256k1KeyPair *signingKey = [Secp256k1KeyPair generateKeyPair:&error];
    XCTAssertNotNil(signingKey);
    
    NSString *signingDIDKey = [DIDKeyEncoder encodeDIDKeyFromCompressedPublicKey:signingKey.compressedPublicKey
                                                                         keyType:DIDKeyTypeSecp256k1
                                                                           error:&error];
    
    builder.signingDIDKey = signingDIDKey;
    builder.handle = @"alice.test";
    builder.pdsEndpoint = @"https://pds.test";
    
    NSDictionary *op = [builder buildGenesisOperationWithError:&error];
    XCTAssertNotNil(op);
    
    // Check rotationKeys
    NSArray *rotationKeys = op[@"rotationKeys"];
    XCTAssertGreaterThanOrEqual(rotationKeys.count, 1);
    XCTAssertEqualObjects(rotationKeys[0], builder.rotationDIDKey);
    
    // Check verificationMethods
    NSDictionary *verificationMethods = op[@"verificationMethods"];
    XCTAssertEqualObjects(verificationMethods[@"atproto"], signingDIDKey);
    
    // Check alsoKnownAs
    NSArray *alsoKnownAs = op[@"alsoKnownAs"];
    XCTAssertEqual(alsoKnownAs.count, 1);
    XCTAssertEqualObjects(alsoKnownAs[0], @"at://alice.test");
    
    // Check services
    NSDictionary *services = op[@"services"];
    NSDictionary *pds = services[@"atproto_pds"];
    XCTAssertEqualObjects(pds[@"type"], @"AtprotoPersonalDataServer");
    XCTAssertEqualObjects(pds[@"endpoint"], @"https://pds.test");
}

- (void)testComputeDIDFromGenesis {
    NSError *error;
    PLCOperationBuilder *builder = [[PLCOperationBuilder alloc] initWithNewRotationKeyWithError:&error];
    XCTAssertNotNil(builder);
    
    Secp256k1KeyPair *signingKey = [Secp256k1KeyPair generateKeyPair:&error];
    XCTAssertNotNil(signingKey);
    
    builder.signingDIDKey = [DIDKeyEncoder encodeDIDKeyFromCompressedPublicKey:signingKey.compressedPublicKey
                                                                       keyType:DIDKeyTypeSecp256k1
                                                                         error:&error];
    builder.handle = @"alice.test";
    builder.pdsEndpoint = @"https://pds.test";
    
    NSDictionary *op = [builder buildGenesisOperationWithError:&error];
    XCTAssertNotNil(op);
    
    NSString *did = [PLCOperationBuilder computeDIDFromGenesisOperation:op error:&error];
    
    XCTAssertNotNil(did, @"Failed to compute DID: %@", error);
    XCTAssertTrue([did hasPrefix:@"did:plc:"], @"Invalid DID prefix: %@", did);
    
    NSString *identifier = [did substringFromIndex:8];
    XCTAssertEqual(identifier.length, 24);
    
    // Check all lowercase
    XCTAssertEqualObjects(identifier, [identifier lowercaseString]);
}

- (void)testDIDIsDeterministic {
    NSError *error;
    PLCOperationBuilder *builder = [[PLCOperationBuilder alloc] initWithNewRotationKeyWithError:&error];
    XCTAssertNotNil(builder);
    
    Secp256k1KeyPair *signingKey = [Secp256k1KeyPair generateKeyPair:&error];
    XCTAssertNotNil(signingKey);
    
    builder.signingDIDKey = [DIDKeyEncoder encodeDIDKeyFromCompressedPublicKey:signingKey.compressedPublicKey
                                                                       keyType:DIDKeyTypeSecp256k1
                                                                         error:&error];
    builder.handle = @"alice.test";
    builder.pdsEndpoint = @"https://pds.test";
    
    NSDictionary *op = [builder buildGenesisOperationWithError:&error];
    XCTAssertNotNil(op);
    
    // Compute DID multiple times - should always be the same
    NSString *did1 = [PLCOperationBuilder computeDIDFromGenesisOperation:op error:&error];
    NSString *did2 = [PLCOperationBuilder computeDIDFromGenesisOperation:op error:&error];
    NSString *did3 = [PLCOperationBuilder computeDIDFromGenesisOperation:op error:&error];
    
    XCTAssertEqualObjects(did1, did2);
    XCTAssertEqualObjects(did2, did3);
}

- (void)testValidateOperation {
    NSError *error;
    PLCOperationBuilder *builder = [[PLCOperationBuilder alloc] initWithNewRotationKeyWithError:&error];
    XCTAssertNotNil(builder);
    
    Secp256k1KeyPair *signingKey = [Secp256k1KeyPair generateKeyPair:&error];
    XCTAssertNotNil(signingKey);
    
    builder.signingDIDKey = [DIDKeyEncoder encodeDIDKeyFromCompressedPublicKey:signingKey.compressedPublicKey
                                                                       keyType:DIDKeyTypeSecp256k1
                                                                         error:&error];
    builder.handle = @"alice.test";
    builder.pdsEndpoint = @"https://pds.test";
    
    NSDictionary *op = [builder buildGenesisOperationWithError:&error];
    XCTAssertNotNil(op);
    
    BOOL valid = [PLCOperationBuilder validateOperation:op error:&error];
    XCTAssertTrue(valid, @"Valid operation failed validation: %@", error);
}

- (void)testInvalidOperationValidation {
    NSError *error;
    
    // Empty dict should fail
    BOOL valid = [PLCOperationBuilder validateOperation:@{} error:&error];
    XCTAssertFalse(valid);
    
    // Missing fields should fail
    valid = [PLCOperationBuilder validateOperation:@{@"type": @"plc_operation"} error:&error];
    XCTAssertFalse(valid);
}

- (void)testSignatureIsBase64URL {
    NSError *error;
    PLCOperationBuilder *builder = [[PLCOperationBuilder alloc] initWithNewRotationKeyWithError:&error];
    XCTAssertNotNil(builder);
    
    Secp256k1KeyPair *signingKey = [Secp256k1KeyPair generateKeyPair:&error];
    XCTAssertNotNil(signingKey);
    
    builder.signingDIDKey = [DIDKeyEncoder encodeDIDKeyFromCompressedPublicKey:signingKey.compressedPublicKey
                                                                       keyType:DIDKeyTypeSecp256k1
                                                                         error:&error];
    builder.handle = @"alice.test";
    builder.pdsEndpoint = @"https://pds.test";
    
    NSDictionary *op = [builder buildGenesisOperationWithError:&error];
    XCTAssertNotNil(op);
    
    NSString *sig = op[@"sig"];
    
    // Should not contain + or /
    XCTAssertEqual([sig rangeOfString:@"+"].location, NSNotFound, @"Signature contains '+' (not base64url)");
    XCTAssertEqual([sig rangeOfString:@"/"].location, NSNotFound, @"Signature contains '/' (not base64url)");
    
    // Should not end with =
    XCTAssertFalse([sig hasSuffix:@"="], @"Signature has padding (not base64url)");
}

- (void)testBuildUpdateOperation {
    NSError *error;
    PLCOperationBuilder *builder = [[PLCOperationBuilder alloc] initWithNewRotationKeyWithError:&error];
    XCTAssertNotNil(builder);
    
    Secp256k1KeyPair *signingKey = [Secp256k1KeyPair generateKeyPair:&error];
    XCTAssertNotNil(signingKey);
    
    builder.signingDIDKey = [DIDKeyEncoder encodeDIDKeyFromCompressedPublicKey:signingKey.compressedPublicKey
                                                                       keyType:DIDKeyTypeSecp256k1
                                                                         error:&error];
    builder.handle = @"alice.test";
    builder.pdsEndpoint = @"https://pds.test";
    
    // Build update operation with fake prev CID
    NSDictionary *op = [builder buildUpdateOperationWithPrev:@"bafyreigfake" error:&error];
    
    XCTAssertNotNil(op, @"Failed to build update operation: %@", error);
    
    // prev should be the CID string
    XCTAssertEqualObjects(op[@"prev"], @"bafyreigfake");
}

@end
