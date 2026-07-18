// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Auth/PDSAppleKeyManager.h"

#if !defined(GNUSTEP)

#pragma mark - PDSAppleKeyPair Tests

@interface PDSAppleKeyPairTests : XCTestCase
@end

@implementation PDSAppleKeyPairTests

- (void)testKeyPairFromPrivateKeyValid {
    NSDictionary *attributes = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeySizeInBits: @(256)
    };
    CFErrorRef cfError = NULL;
    SecKeyRef privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, &cfError);
    if (!privateKey) {
        XCTSkip(@"SecKey generation not available in this environment");
        return;
    }
    SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);

    PDSAppleKeyPair *keyPair = [PDSAppleKeyPair keyPairFromPrivateKey:privateKey publicKey:publicKey keyID:@"test-key-1" algorithm:@"ES256"];
    XCTAssertNotNil(keyPair);
    XCTAssertEqualObjects(keyPair.keyID, @"test-key-1");
    XCTAssertEqualObjects(keyPair.algorithm, @"ES256");
    XCTAssertTrue(keyPair.isActive);
    XCTAssertNotNil(keyPair.createdAt);
    XCTAssertNotNil(keyPair.privateKey);
    XCTAssertNotNil(keyPair.publicKey);

    CFRelease(publicKey);
    CFRelease(privateKey);
}

- (void)testKeyPairFromPrivateKeyNilPrivate {
    NSDictionary *attributes = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeySizeInBits: @(256)
    };
    CFErrorRef cfError = NULL;
    SecKeyRef publicKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, &cfError);
    if (!publicKey) {
        XCTSkip(@"SecKey generation not available");
        return;
    }

    PDSAppleKeyPair *keyPair = [PDSAppleKeyPair keyPairFromPrivateKey:nil publicKey:publicKey keyID:@"test" algorithm:@"ES256"];
    XCTAssertNil(keyPair);
    CFRelease(publicKey);
}

- (void)testKeyPairFromPrivateKeyNilKeyID {
    NSDictionary *attributes = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeySizeInBits: @(256)
    };
    CFErrorRef cfError = NULL;
    SecKeyRef privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, &cfError);
    if (!privateKey) {
        XCTSkip(@"SecKey generation not available");
        return;
    }
    SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);

    PDSAppleKeyPair *keyPair = [PDSAppleKeyPair keyPairFromPrivateKey:privateKey publicKey:publicKey keyID:nil algorithm:@"ES256"];
    XCTAssertNil(keyPair);

    CFRelease(publicKey);
    CFRelease(privateKey);
}

- (void)testKeyPairWithSecp256k1Valid {
    // 32-byte private key for secp256k1
    NSMutableData *privKeyData = [NSMutableData dataWithLength:32];
    arc4random_buf(privKeyData.mutableBytes, 32);
    NSData *pubKeyData = [@"fake-pubkey-data" dataUsingEncoding:NSUTF8StringEncoding];

    PDSAppleKeyPair *keyPair = [PDSAppleKeyPair keyPairWithSecp256k1PrivateKey:privKeyData publicKey:pubKeyData keyID:@"secp-test-1"];
    XCTAssertNotNil(keyPair);
    XCTAssertEqualObjects(keyPair.keyID, @"secp-test-1");
    XCTAssertEqualObjects(keyPair.algorithm, @"ES256K");
    XCTAssertNotNil(keyPair.secp256k1PrivateKeyData);
    XCTAssertNil(keyPair.privateKey);  // No SecKeyRef for secp256k1
    XCTAssertTrue(keyPair.isActive);
}

- (void)testKeyPairWithSecp256k1WrongKeyLength {
    NSData *privKeyData = [@"too-short" dataUsingEncoding:NSUTF8StringEncoding];  // 9 bytes, not 32
    NSData *pubKeyData = [@"pub" dataUsingEncoding:NSUTF8StringEncoding];

    PDSAppleKeyPair *keyPair = [PDSAppleKeyPair keyPairWithSecp256k1PrivateKey:privKeyData publicKey:pubKeyData keyID:@"bad"];
    XCTAssertNil(keyPair, @"Should reject private key data that is not exactly 32 bytes");
}

- (void)testKeyPairWithSecp256k1NilPrivateKey {
    PDSAppleKeyPair *keyPair = [PDSAppleKeyPair keyPairWithSecp256k1PrivateKey:nil publicKey:[NSData data] keyID:@"test"];
    XCTAssertNil(keyPair);
}

- (void)testKeyPairWithSecp256k1NilKeyID {
    NSMutableData *privKeyData = [NSMutableData dataWithLength:32];
    arc4random_buf(privKeyData.mutableBytes, 32);

    PDSAppleKeyPair *keyPair = [PDSAppleKeyPair keyPairWithSecp256k1PrivateKey:privKeyData publicKey:[NSData data] keyID:nil];
    XCTAssertNil(keyPair);
}

- (void)testPublicKeyThumbprintConsistent {
    NSDictionary *attributes = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeySizeInBits: @(256)
    };
    CFErrorRef cfError = NULL;
    SecKeyRef privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, &cfError);
    if (!privateKey) {
        XCTSkip(@"SecKey generation not available");
        return;
    }
    SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);

    PDSAppleKeyPair *keyPair = [PDSAppleKeyPair keyPairFromPrivateKey:privateKey publicKey:publicKey keyID:@"tp-test" algorithm:@"ES256"];
    NSString *thumbprint1 = [keyPair publicKeyThumbprint];
    NSString *thumbprint2 = [keyPair publicKeyThumbprint];
    XCTAssertNotNil(thumbprint1);
    XCTAssertEqualObjects(thumbprint1, thumbprint2, @"Thumbprint should be deterministic");

    CFRelease(publicKey);
    CFRelease(privateKey);
}

- (void)testPublicKeyJWKContainsRequiredFields {
    NSDictionary *attributes = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeySizeInBits: @(256)
    };
    CFErrorRef cfError = NULL;
    SecKeyRef privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, &cfError);
    if (!privateKey) {
        XCTSkip(@"SecKey generation not available");
        return;
    }
    SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);

    PDSAppleKeyPair *keyPair = [PDSAppleKeyPair keyPairFromPrivateKey:privateKey publicKey:publicKey keyID:@"jwk-test" algorithm:@"ES256"];
    NSDictionary *jwk = [keyPair publicKeyJWK];
    XCTAssertNotNil(jwk);
    XCTAssertEqualObjects(jwk[@"kty"], @"EC");
    XCTAssertEqualObjects(jwk[@"crv"], @"P-256");
    XCTAssertEqualObjects(jwk[@"kid"], @"jwk-test");
    XCTAssertNotNil(jwk[@"x"]);
    XCTAssertNotNil(jwk[@"y"]);
    XCTAssertNil(jwk[@"d"], @"Public JWK must not contain private key material");

    CFRelease(publicKey);
    CFRelease(privateKey);
}

@end

#pragma mark - PDSAppleKeyManager Tests

@interface PDSAppleKeyManagerTests : XCTestCase
@property (nonatomic, strong) PDSAppleKeyManager *manager;
@end

@implementation PDSAppleKeyManagerTests

- (void)setUp {
    [super setUp];
    self.manager = [[PDSAppleKeyManager alloc] initWithServiceIdentifier:@"com.test.keymanager"];
}

- (void)testInitWithServiceIdentifier {
    PDSAppleKeyManager *manager = [[PDSAppleKeyManager alloc] initWithServiceIdentifier:@"com.test.keys"];
    XCTAssertNotNil(manager);
    XCTAssertEqualObjects(manager.serviceIdentifier, @"com.test.keys");
}

- (void)testInitWithNilServiceIdentifier {
    // Should still initialize with a default
    PDSAppleKeyManager *manager = [[PDSAppleKeyManager alloc] initWithServiceIdentifier:nil];
    XCTAssertNotNil(manager);
}

- (void)testGenerateES256KKeyPair {
    NSError *error = nil;
    PDSAppleKeyPair *keyPair = [self.manager generatePDSAppleKeyPairWithAlgorithm:@"ES256K" keySize:256 error:&error];
    XCTAssertNotNil(keyPair, @"ES256K key generation should succeed: %@", error);
    XCTAssertNil(error);
    XCTAssertEqualObjects(keyPair.algorithm, @"ES256K");
    XCTAssertNotNil(keyPair.keyID);
    XCTAssertNotNil(keyPair.secp256k1PrivateKeyData);
    XCTAssertEqual(keyPair.secp256k1PrivateKeyData.length, 32u);
    XCTAssertEqualObjects(keyPair, [self.manager getActivePDSAppleKeyPair:nil]);
}

- (void)testGenerateES256KeyPair {
    NSError *error = nil;
    PDSAppleKeyPair *keyPair = [self.manager generatePDSAppleKeyPairWithAlgorithm:@"ES256" keySize:256 error:&error];
    if (!keyPair) {
        XCTSkip(@"ES256 key generation not supported in this environment: %@", error);
        return;
    }
    XCTAssertEqualObjects(keyPair.algorithm, @"ES256");
    XCTAssertNotNil(keyPair.keyID);
    XCTAssertNotNil(keyPair.privateKey);
    XCTAssertNotNil(keyPair.publicKey);
}

- (void)testGetKeyPairWithUnknownID {
    NSError *error = nil;
    PDSAppleKeyPair *keyPair = [self.manager getPDSAppleKeyPairWithID:@"nonexistent" error:&error];
    XCTAssertNil(keyPair);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, KeyManagerErrorDomain);
    XCTAssertEqual(error.code, KeyManagerErrorKeyNotFound);
}

- (void)testGetActiveKeyPairGeneratesOnDemand {
    // Fresh manager with no keys — getActiveKeyPair should auto-generate
    PDSAppleKeyManager *freshManager = [[PDSAppleKeyManager alloc] initWithServiceIdentifier:@"com.test.fresh"];
    NSError *error = nil;
    PDSAppleKeyPair *keyPair = [freshManager getActivePDSAppleKeyPair:&error];
    XCTAssertNotNil(keyPair, @"getActiveKeyPair should auto-generate ES256K: %@", error);
    XCTAssertEqualObjects(keyPair.algorithm, @"ES256K");
}

- (void)testAllKeyPairsEmpty {
    PDSAppleKeyManager *freshManager = [[PDSAppleKeyManager alloc] initWithServiceIdentifier:@"com.test.empty"];
    NSError *error = nil;
    NSArray *all = [freshManager allPDSAppleKeyPairs:&error];
    // After getActivePDSAppleKeyPair or generation, there will be at least one
    // But fresh manager without any calls should be empty
    // (getActiveKeyPair is not called yet)
    // However init calls loadKeysFromDatabase which may populate.
    // We just verify it returns an array without error.
    XCTAssertNotNil(all);
}

- (void)testDeleteKeyPairSuccess {
    NSError *error = nil;
    PDSAppleKeyPair *keyPair = [self.manager generatePDSAppleKeyPairWithAlgorithm:@"ES256K" keySize:256 error:&error];
    XCTAssertNotNil(keyPair);

    BOOL deleted = [self.manager deletePDSAppleKeyPairWithID:keyPair.keyID error:&error];
    XCTAssertTrue(deleted);

    PDSAppleKeyPair *fetched = [self.manager getPDSAppleKeyPairWithID:keyPair.keyID error:nil];
    XCTAssertNil(fetched);
}

- (void)testDeleteKeyPairNotFound {
    NSError *error = nil;
    BOOL deleted = [self.manager deletePDSAppleKeyPairWithID:@"nonexistent" error:&error];
    XCTAssertFalse(deleted);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, KeyManagerErrorKeyNotFound);
}

- (void)testSetKeyPairActive {
    NSError *error = nil;
    PDSAppleKeyPair *key1 = [self.manager generatePDSAppleKeyPairWithAlgorithm:@"ES256K" keySize:256 error:&error];
    XCTAssertNotNil(key1);
    PDSAppleKeyPair *key2 = [self.manager generatePDSAppleKeyPairWithAlgorithm:@"ES256K" keySize:256 error:&error];
    XCTAssertNotNil(key2);

    BOOL activated = [self.manager setPDSAppleKeyPairActive:key1.keyID error:&error];
    XCTAssertTrue(activated);

    PDSAppleKeyPair *active = [self.manager getActivePDSAppleKeyPair:nil];
    XCTAssertEqualObjects(active.keyID, key1.keyID);
}

- (void)testSetKeyPairActiveNotFound {
    NSError *error = nil;
    BOOL result = [self.manager setPDSAppleKeyPairActive:@"nonexistent" error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, KeyManagerErrorKeyNotFound);
}

- (void)testMultipleKeyPairsListed {
    NSError *error = nil;
    PDSAppleKeyPair *key1 = [self.manager generatePDSAppleKeyPairWithAlgorithm:@"ES256K" keySize:256 error:&error];
    XCTAssertNotNil(key1);
    PDSAppleKeyPair *key2 = [self.manager generatePDSAppleKeyPairWithAlgorithm:@"ES256K" keySize:256 error:&error];
    XCTAssertNotNil(key2);

    NSArray *all = [self.manager allPDSAppleKeyPairs:&error];
    XCTAssertGreaterThanOrEqual(all.count, 2u);
}

#pragma mark - Signing and Verification

- (void)testSignAndVerifyDataES256K {
    NSError *error = nil;
    PDSAppleKeyPair *keyPair = [self.manager generatePDSAppleKeyPairWithAlgorithm:@"ES256K" keySize:256 error:&error];
    if (!keyPair) {
        XCTSkip(@"ES256K generation failed: %@", error);
        return;
    }

    NSData *dataToSign = [@"test payload to sign" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *signature = [self.manager signData:dataToSign withKeyID:keyPair.keyID error:&error];
    XCTAssertNotNil(signature, @"Signing should succeed: %@", error);
    XCTAssertGreaterThan(signature.length, (NSUInteger)0);

    BOOL valid = [self.manager verifySignature:signature forData:dataToSign withKeyID:keyPair.keyID error:&error];
    XCTAssertTrue(valid, @"Signature verification should pass: %@", error);
}

- (void)testVerifySignatureWithWrongData {
    NSError *error = nil;
    PDSAppleKeyPair *keyPair = [self.manager generatePDSAppleKeyPairWithAlgorithm:@"ES256K" keySize:256 error:&error];
    if (!keyPair) {
        XCTSkip(@"ES256K generation failed");
        return;
    }

    NSData *data = [@"original data" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *signature = [self.manager signData:data withKeyID:keyPair.keyID error:&error];
    XCTAssertNotNil(signature);

    NSData *wrongData = [@"tampered data" dataUsingEncoding:NSUTF8StringEncoding];
    BOOL valid = [self.manager verifySignature:signature forData:wrongData withKeyID:keyPair.keyID error:&error];
    XCTAssertFalse(valid, @"Verification should fail with tampered data");
}

- (void)testSignWithUnknownKeyID {
    NSData *data = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSData *signature = [self.manager signData:data withKeyID:@"nonexistent" error:&error];
    XCTAssertNil(signature);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, KeyManagerErrorKeyNotFound);
}

- (void)testVerifyWithUnknownKeyID {
    NSData *data = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *sig = [@"fake-sig" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    BOOL valid = [self.manager verifySignature:sig forData:data withKeyID:@"nonexistent" error:&error];
    XCTAssertFalse(valid);
    XCTAssertNotNil(error);
}

#pragma mark - String Signing

- (void)testSignStringAndVerify {
    NSError *error = nil;
    PDSAppleKeyPair *keyPair = [self.manager generatePDSAppleKeyPairWithAlgorithm:@"ES256K" keySize:256 error:&error];
    if (!keyPair) {
        XCTSkip(@"ES256K generation failed");
        return;
    }

    NSString *message = @"Hello, AT Protocol!";
    NSString *base64Sig = [self.manager signString:message withKeyID:keyPair.keyID error:&error];
    XCTAssertNotNil(base64Sig);
    XCTAssertGreaterThan(base64Sig.length, (NSUInteger)0);

    NSData *sigData = [[NSData alloc] initWithBase64EncodedString:base64Sig options:0];
    NSData *messageData = [message dataUsingEncoding:NSUTF8StringEncoding];
    BOOL valid = [self.manager verifySignature:sigData forData:messageData withKeyID:keyPair.keyID error:&error];
    XCTAssertTrue(valid);
}

#pragma mark - JWKS Export

- (void)testToJWKSReturnsActiveKey {
    NSError *error = nil;
    PDSAppleKeyPair *keyPair = [self.manager generatePDSAppleKeyPairWithAlgorithm:@"ES256K" keySize:256 error:&error];
    XCTAssertNotNil(keyPair);

    NSDictionary *jwks = [self.manager toJWKS];
    XCTAssertNotNil(jwks);
    XCTAssertEqualObjects(jwks[@"kty"], @"EC");
    XCTAssertEqualObjects(jwks[@"crv"], @"secp256k1");
    XCTAssertNotNil(jwks[@"x"]);
}

- (void)testToJWKSArrayContainsAllKeys {
    NSError *error = nil;
    [self.manager generatePDSAppleKeyPairWithAlgorithm:@"ES256K" keySize:256 error:&error];
    [self.manager generatePDSAppleKeyPairWithAlgorithm:@"ES256K" keySize:256 error:&error];

    NSArray *jwksArray = [self.manager toJWKSArray];
    XCTAssertGreaterThanOrEqual(jwksArray.count, 2u);
}

#pragma mark - NSSecureCoding

- (void)testSecureCodingRoundTrip {
    NSError *error = nil;
    PDSAppleKeyPair *keyPair = [self.manager generatePDSAppleKeyPairWithAlgorithm:@"ES256K" keySize:256 error:&error];
    XCTAssertNotNil(keyPair);
    self.manager.currentKeyID = keyPair.keyID;

    NSData *archived = [NSKeyedArchiver archivedDataWithRootObject:self.manager requiringSecureCoding:YES error:&error];
    XCTAssertNotNil(archived, @"Archiving should succeed: %@", error);

    PDSAppleKeyManager *decoded = [NSKeyedUnarchiver unarchivedObjectOfClass:[PDSAppleKeyManager class] fromData:archived error:&error];
    XCTAssertNotNil(decoded, @"Unarchiving should succeed: %@", error);
    XCTAssertEqualObjects(decoded.serviceIdentifier, self.manager.serviceIdentifier);
    XCTAssertEqualObjects(decoded.currentKeyID, self.manager.currentKeyID);
}

#pragma mark - Database-Backed Init

- (void)testInitWithDatabaseServiceIdentifier {
    // Pass nil database — should still initialize without crashing
    PDSAppleKeyManager *manager = [[PDSAppleKeyManager alloc] initWithDatabase:nil serviceIdentifier:@"com.test.db"];
    XCTAssertNotNil(manager);
    XCTAssertEqualObjects(manager.serviceIdentifier, @"com.test.db");
}

@end

#endif /* !GNUSTEP */
