// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "PLC/PLCAuditor.h"
#import "PLC/PLCMockStore.h"
#import "PLC/PLCOperation.h"
#import "PLC/PLCDIDKey.h"
#import "Auth/Secp256k1.h"
#import "Auth/CryptoUtils.h"
#import "Auth/Crypto/AuthCryptoECDSA.h"
#import "Core/CID.h"
#import "Core/ATProtoCBORSerialization.h"
#import <Security/Security.h>

// Expose private PLCAuditor methods for testing
@interface PLCAuditor (Testing)
- (nullable NSString *)verifySignatureForOperation:(PLCOperation *)op
                                        allowedKeys:(NSArray<NSString *> *)allowedKeys
                                              error:(NSError **)error;
- (NSDictionary *)unsignedDataForOperation:(PLCOperation *)op;
@end

@interface PLCAuditorTests : XCTestCase
@property (nonatomic, strong) PLCMockStore *store;
@property (nonatomic, strong) PLCAuditor *auditor;
@end

@implementation PLCAuditorTests

- (void)setUp {
    [super setUp];
    self.store = [[PLCMockStore alloc] init];
    self.auditor = [[PLCAuditor alloc] initWithStore:self.store];
}

- (NSString *)base64URLEncode:(NSData *)data {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return base64;
}

- (void)testAuditorFailsOnEmptyHistory {
    NSError *error = nil;
    BOOL success = [self.auditor verifyDID:@"did:plc:test" error:&error];
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
}

- (void)testAuditorRejectsInvalidSignature {
    Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:nil];
    XCTAssertNotNil(keyPair);

    NSString *didKey = [keyPair didKeyString];
    NSDictionary *opData = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[didKey],
        @"verificationMethods": @{@"atproto": didKey},
        @"alsoKnownAs": @[@"at://test.com"],
        @"services": @{},
        @"prev": [NSNull null]
    };

    // For this test, we just provide a dummy signature
    PLCOperation *op = [[PLCOperation alloc] init];
    op.sig = @"invalid_signature";
    op.data = opData;
    op.prev = nil;
    op.did = [PLCOperation calculateDIDForSignedOperation:[op toDictionary]];

    [self.store appendOperation:op nullifyCIDs:@[] error:nil];

    NSError *error = nil;
    BOOL success = [self.auditor verifyDID:op.did error:&error];
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
    XCTAssertNotNil(error.localizedDescription);
}

- (void)testAuditorRejectsMismatchedPrevHash {
    Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:nil];
    NSString *didKey = [keyPair didKeyString];

    // 1. Genesis operation
    NSDictionary *op1Data = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[didKey],
        @"verificationMethods": @{@"atproto": didKey},
        @"alsoKnownAs": @[@"at://test.com"],
        @"services": @{},
        @"prev": [NSNull null]
    };
    NSData *op1Hash = [self.auditor hashForOperationData:op1Data];
    NSData *op1Sig = [keyPair signHash:op1Hash error:nil];

    PLCOperation *op1 = [[PLCOperation alloc] init];
    op1.sig = [self base64URLEncode:op1Sig];
    op1.data = op1Data;
    op1.prev = nil;
    op1.did = [PLCOperation calculateDIDForSignedOperation:[op1 toDictionary]];
    [self.store appendOperation:op1 nullifyCIDs:@[] error:nil];

    // 2. Second operation with WRONG prev hash
    NSDictionary *op2Data = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[didKey],
        @"verificationMethods": @{@"atproto": didKey},
        @"alsoKnownAs": @[@"at://test.com"],
        @"services": @{},
        @"prev": @"bafkqabaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    };
    NSData *op2Hash = [self.auditor hashForOperationData:op2Data];
    NSData *op2Sig = [keyPair signHash:op2Hash error:nil];

    PLCOperation *op2 = [[PLCOperation alloc] init];
    op2.did = op1.did;
    op2.sig = [self base64URLEncode:op2Sig];
    op2.data = op2Data;
    op2.prev = @"bafkqabaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    [self.store appendOperation:op2 nullifyCIDs:@[] error:nil];

    NSError *error = nil;
    BOOL success = [self.auditor verifyDID:op1.did error:&error];
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
    XCTAssertNotNil(error.localizedDescription);
}

- (void)testAuditorValidatesMultiStepChainWithKeyRotation {
    Secp256k1KeyPair *key1 = [[Secp256k1 shared] generateKeyPairWithError:nil];
    Secp256k1KeyPair *key2 = [[Secp256k1 shared] generateKeyPairWithError:nil];
    NSString *key1Did = [key1 didKeyString];
    NSString *key2Did = [key2 didKeyString];

    // 1. Genesis operation signed by key1, authorizing key1
    NSDictionary *op1Data = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[key1Did],
        @"verificationMethods": @{@"atproto": key1Did},
        @"alsoKnownAs": @[@"at://test.com"],
        @"services": @{},
        @"prev": [NSNull null]
    };
    NSData *op1Hash = [self.auditor hashForOperationData:op1Data];
    NSData *op1Sig = [key1 signHash:op1Hash error:nil];

    PLCOperation *op1 = [[PLCOperation alloc] init];
    op1.sig = [self base64URLEncode:op1Sig];
    op1.data = op1Data;
    op1.prev = nil;
    op1.did = [PLCOperation calculateDIDForSignedOperation:[op1 toDictionary]];
    [self.store appendOperation:op1 nullifyCIDs:@[] error:nil];

    // 2. Second operation signed by key1, rotating to key2
    NSString *prevCid1 = [PLCOperation calculateCIDForOperation:[op1 toDictionary] error:nil];
    NSDictionary *op2Data = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[key2Did],
        @"verificationMethods": @{@"atproto": key2Did},
        @"alsoKnownAs": @[@"at://test.com"],
        @"services": @{},
        @"prev": prevCid1
    };
    NSData *op2Hash = [self.auditor hashForOperationData:op2Data];
    NSData *op2Sig = [key1 signHash:op2Hash error:nil]; // Signed by key1 (authorized by op1)

    PLCOperation *op2 = [[PLCOperation alloc] init];
    op2.did = op1.did;
    op2.sig = [self base64URLEncode:op2Sig];
    op2.data = op2Data;
    op2.prev = prevCid1;
    [self.store appendOperation:op2 nullifyCIDs:@[] error:nil];

    // 3. Third operation signed by key2
    NSString *prevCid2 = [PLCOperation calculateCIDForOperation:[op2 toDictionary] error:nil];
    NSDictionary *op3Data = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[key2Did],
        @"verificationMethods": @{@"atproto": key2Did},
        @"alsoKnownAs": @[@"at://test.com"],
        @"services": @{},
        @"prev": prevCid2
    };
    NSData *op3Hash = [self.auditor hashForOperationData:op3Data];
    NSData *op3Sig = [key2 signHash:op3Hash error:nil]; // Signed by key2 (authorized by op2)

    PLCOperation *op3 = [[PLCOperation alloc] init];
    op3.did = op1.did;
    op3.sig = [self base64URLEncode:op3Sig];
    op3.data = op3Data;
    op3.prev = prevCid2;
    [self.store appendOperation:op3 nullifyCIDs:@[] error:nil];

    NSError *error = nil;
    BOOL success = [self.auditor verifyDID:op1.did error:&error];
    XCTAssertTrue(success, @"Auditor should accept valid chain with key rotation. Error: %@", error);
}

- (void)testAuditorValidatesHandleUpdate {
    Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:nil];
    NSString *didKey = [keyPair didKeyString];

    NSDictionary *op1Data = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[didKey],
        @"verificationMethods": @{@"atproto": didKey},
        @"alsoKnownAs": @[@"at://test.bsky.social"],
        @"services": @{},
        @"prev": [NSNull null]
    };
    NSData *op1Hash = [self.auditor hashForOperationData:op1Data];
    NSData *op1Sig = [keyPair signHash:op1Hash error:nil];

    PLCOperation *op1 = [[PLCOperation alloc] init];
    op1.sig = [self base64URLEncode:op1Sig];
    op1.data = op1Data;
    op1.prev = nil;
    op1.did = [PLCOperation calculateDIDForSignedOperation:[op1 toDictionary]];
    [self.store appendOperation:op1 nullifyCIDs:@[] error:nil];

    NSString *prevCid = [PLCOperation calculateCIDForOperation:[op1 toDictionary] error:nil];
    NSDictionary *op2Data = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[didKey],
        @"verificationMethods": @{@"atproto": didKey},
        @"alsoKnownAs": @[@"at://newhandle.bsky.social"],
        @"services": @{},
        @"prev": prevCid
    };
    NSData *op2Hash = [self.auditor hashForOperationData:op2Data];
    NSData *op2Sig = [keyPair signHash:op2Hash error:nil];

    PLCOperation *op2 = [[PLCOperation alloc] init];
    op2.did = op1.did;
    op2.sig = [self base64URLEncode:op2Sig];
    op2.data = op2Data;
    op2.prev = prevCid;
    [self.store appendOperation:op2 nullifyCIDs:@[] error:nil];

    NSError *error = nil;
    BOOL success = [self.auditor verifyDID:op1.did error:&error];
    XCTAssertTrue(success, @"Auditor should accept valid handle update. Error: %@", error);
}

#pragma mark - P-256 Helpers

- (void)testAuditorVerifiesP256Signature {
    // 1. Import a fixed P-256 keypair (SecKeyCreateRandomKey can be unavailable in some sandboxes)
    NSData *xData = [self dataFromHexString:@"44073c1c6da8c2c9736c011ff13a2b3602a1d819e687582bdf87262ad1b12f50" expectedLength:32];
    NSData *yData = [self dataFromHexString:@"79720e75ce2eaae05079972dd065b2eb437d9af5c9a974d3ce186525494bdc3c" expectedLength:32];
    NSData *dData = [self dataFromHexString:@"8d12e99fb324f3c1bafed77fa91968a36c252590f0e55fef10f9bfb027b59504" expectedLength:32];
    XCTAssertNotNil(xData);
    XCTAssertNotNil(yData);
    XCTAssertNotNil(dData);

    NSMutableData *privateKeyData = [NSMutableData dataWithCapacity:97];
    uint8_t prefix = 0x04;
    [privateKeyData appendBytes:&prefix length:1];
    [privateKeyData appendData:xData];
    [privateKeyData appendData:yData];
    [privateKeyData appendData:dData];

    NSDictionary *attrs = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPrivate,
        (__bridge id)kSecAttrKeySizeInBits: @256
    };

    CFErrorRef errorRef = NULL;
    SecKeyRef privateKey = SecKeyCreateWithData((__bridge CFDataRef)privateKeyData, (__bridge CFDictionaryRef)attrs, &errorRef);
    if (!privateKey) {
        NSError *nsError = errorRef ? CFBridgingRelease(errorRef) : nil;
        XCTSkip(@"Skipping PLC P-256 signature test: key import unavailable (%@)", nsError);
        return;
    }
    if (errorRef) CFRelease(errorRef);

    // 2. Derive compressed public key from (x,y): 02/03 || x
    NSMutableData *compressedPub = [NSMutableData dataWithCapacity:33];
    const uint8_t *yBytes = yData.bytes;
    uint8_t compressedPrefix = (yBytes[31] & 1) ? 0x03 : 0x02;
    [compressedPub appendBytes:&compressedPrefix length:1];
    [compressedPub appendData:xData];
    
    // 3. Create DID Key String (did:key:zDn...)
    // Prefix 0x80 0x24 (p256-pub varint)
    uint8_t codec[] = {0x80, 0x24};
    NSMutableData *prefixed = [NSMutableData dataWithBytes:codec length:2];
    [prefixed appendData:compressedPub];
    NSString *didKey = [NSString stringWithFormat:@"did:key:z%@", [CID base58btcEncode:prefixed]];
    
    // 4. Create Operation
    NSDictionary *opData = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[didKey],
        @"verificationMethods": @{@"atproto": didKey},
        @"alsoKnownAs": @[@"at://p256.test"],
        @"services": @{},
        @"prev": [NSNull null]
    };
    
    // 5. Sign Operation Hash
    NSData *opHash = [self.auditor hashForOperationData:opData];
    
    NSData *derSig = (__bridge_transfer NSData *)SecKeyCreateSignature(privateKey,
                                                                       kSecKeyAlgorithmECDSASignatureDigestX962SHA256,
                                                                       (__bridge CFDataRef)opHash,
                                                                       &errorRef);
    XCTAssertNotNil(derSig);
    CFRelease(privateKey);
    
    // Convert DER to Raw (r||s)
    NSData *rawSig = [self rawSignatureFromDER:derSig];
    XCTAssertNotNil(rawSig);
    
    // Normalize to low-S form per PLC spec
    // https://web.plc.directory/spec/v0.1/did-plc — "high-S values rejected as invalid"
    NSError *normalizeError = nil;
    rawSig = [AuthCryptoECDSA normalizeLowS:rawSig error:&normalizeError];
    XCTAssertNotNil(rawSig, @"Low-S normalization failed: %@", normalizeError);
    
    PLCOperation *op = [[PLCOperation alloc] init];
    op.sig = [self base64URLEncode:rawSig];
    op.data = opData;
    op.prev = nil;
    op.did = [PLCOperation calculateDIDForSignedOperation:[op toDictionary]];
    
    [self.store appendOperation:op nullifyCIDs:@[] error:nil];
    
    // 6. Verify
    NSError *verifyError = nil;
    BOOL success = [self.auditor verifyDID:op.did error:&verifyError];
    XCTAssertTrue(success, @"Auditor should verify P-256 signed operation. Error: %@", verifyError);
}

- (void)testAuditorRejectsHighSP256Signature {
    // Same fixed P-256 keypair as testAuditorVerifiesP256Signature, but this
    // time the signature is deliberately denormalized to high-S. did:plc
    // requires low-S canonical signatures
    // (https://web.plc.directory/spec/v0.1/did-plc); AuthCryptoJWK's shared
    // verifier accepts both forms per ADR 0007 (that fix is for DPoP/JWT/
    // WebAuthn callers, which must not reject high-S), so PLCAuditor must
    // enforce low-S itself rather than relying on the shared verifier.
    NSData *xData = [self dataFromHexString:@"44073c1c6da8c2c9736c011ff13a2b3602a1d819e687582bdf87262ad1b12f50" expectedLength:32];
    NSData *yData = [self dataFromHexString:@"79720e75ce2eaae05079972dd065b2eb437d9af5c9a974d3ce186525494bdc3c" expectedLength:32];
    NSData *dData = [self dataFromHexString:@"8d12e99fb324f3c1bafed77fa91968a36c252590f0e55fef10f9bfb027b59504" expectedLength:32];
    XCTAssertNotNil(xData);
    XCTAssertNotNil(yData);
    XCTAssertNotNil(dData);

    NSMutableData *privateKeyData = [NSMutableData dataWithCapacity:97];
    uint8_t prefix = 0x04;
    [privateKeyData appendBytes:&prefix length:1];
    [privateKeyData appendData:xData];
    [privateKeyData appendData:yData];
    [privateKeyData appendData:dData];

    NSDictionary *attrs = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPrivate,
        (__bridge id)kSecAttrKeySizeInBits: @256
    };

    CFErrorRef errorRef = NULL;
    SecKeyRef privateKey = SecKeyCreateWithData((__bridge CFDataRef)privateKeyData, (__bridge CFDictionaryRef)attrs, &errorRef);
    if (!privateKey) {
        NSError *nsError = errorRef ? CFBridgingRelease(errorRef) : nil;
        XCTSkip(@"Skipping PLC P-256 signature test: key import unavailable (%@)", nsError);
        return;
    }
    if (errorRef) CFRelease(errorRef);

    NSMutableData *compressedPub = [NSMutableData dataWithCapacity:33];
    const uint8_t *yBytes = yData.bytes;
    uint8_t compressedPrefix = (yBytes[31] & 1) ? 0x03 : 0x02;
    [compressedPub appendBytes:&compressedPrefix length:1];
    [compressedPub appendData:xData];

    uint8_t codec[] = {0x80, 0x24};
    NSMutableData *prefixed = [NSMutableData dataWithBytes:codec length:2];
    [prefixed appendData:compressedPub];
    NSString *didKey = [NSString stringWithFormat:@"did:key:z%@", [CID base58btcEncode:prefixed]];

    NSDictionary *opData = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[didKey],
        @"verificationMethods": @{@"atproto": didKey},
        @"alsoKnownAs": @[@"at://p256-highs.test"],
        @"services": @{},
        @"prev": [NSNull null]
    };

    NSData *opHash = [self.auditor hashForOperationData:opData];

    NSData *derSig = (__bridge_transfer NSData *)SecKeyCreateSignature(privateKey,
                                                                       kSecKeyAlgorithmECDSASignatureDigestX962SHA256,
                                                                       (__bridge CFDataRef)opHash,
                                                                       &errorRef);
    XCTAssertNotNil(derSig);
    CFRelease(privateKey);

    NSData *rawSig = [self rawSignatureFromDER:derSig];
    XCTAssertNotNil(rawSig);

    // Force high-S: normalize first (SecKeyCreateSignature's S form isn't
    // guaranteed either way), then denormalize to guarantee a genuine,
    // otherwise-valid high-S signature over this exact data.
    NSError *normalizeError = nil;
    NSData *lowS = [AuthCryptoECDSA normalizeLowS:rawSig error:&normalizeError];
    XCTAssertNotNil(lowS, @"Low-S normalization failed: %@", normalizeError);
    NSError *denormalizeError = nil;
    NSData *highS = [AuthCryptoECDSA denormalizeLowS:lowS error:&denormalizeError];
    XCTAssertNotNil(highS, @"High-S denormalization failed: %@", denormalizeError);
    XCTAssertFalse([AuthCryptoECDSA isLowS:highS error:nil], @"sanity: signature must actually be high-S");

    PLCOperation *op = [[PLCOperation alloc] init];
    op.sig = [self base64URLEncode:highS];
    op.data = opData;
    op.prev = nil;
    op.did = [PLCOperation calculateDIDForSignedOperation:[op toDictionary]];

    [self.store appendOperation:op nullifyCIDs:@[] error:nil];

    NSError *verifyError = nil;
    BOOL success = [self.auditor verifyDID:op.did error:&verifyError];
    XCTAssertFalse(success, @"Auditor must reject a high-S PLC operation signature (did:plc requires low-S canonical form)");
}

- (NSData *)dataFromHexString:(NSString *)hex expectedLength:(NSUInteger)expectedLength {
    if (![hex isKindOfClass:[NSString class]]) {
        return nil;
    }

    NSString *normalized = [[hex stringByReplacingOccurrencesOfString:@":" withString:@""] lowercaseString];
    if (normalized.length != expectedLength * 2) {
        return nil;
    }

    NSMutableData *data = [NSMutableData dataWithCapacity:expectedLength];
    for (NSUInteger i = 0; i < normalized.length; i += 2) {
        unsigned int value = 0;
        NSScanner *scanner = [NSScanner scannerWithString:[normalized substringWithRange:NSMakeRange(i, 2)]];
        if (![scanner scanHexInt:&value]) {
            return nil;
        }
        uint8_t byte = (uint8_t)value;
        [data appendBytes:&byte length:1];
    }
    return data.length == expectedLength ? data : nil;
}

- (NSData *)rawSignatureFromDER:(NSData *)derSig {
    const uint8_t *bytes = derSig.bytes;
    if (derSig.length < 8) return nil; // minimal sanity check
    
    NSUInteger offset = 2; // skip SEQ tag and length (assuming < 128 bytes total)
    if (bytes[1] & 0x80) { // long form length
         offset += (bytes[1] & 0x7F);
    }
    
    // r
    offset++; // tag 0x02
    NSUInteger rLen = bytes[offset++];
    const uint8_t *rBytes = bytes + offset;
    // Remove leading zero
    if (rLen > 0 && rBytes[0] == 0x00) {
        rBytes++;
        rLen--;
    }
    offset += (bytes[offset - 1]); // use original length for offset
    
    // s
    offset++; // tag 0x02
    NSUInteger sLen = bytes[offset++];
    const uint8_t *sBytes = bytes + offset;
    // Remove leading zero
    if (sLen > 0 && sBytes[0] == 0x00) {
        sBytes++;
        sLen--;
    }
    
    NSMutableData *raw = [NSMutableData dataWithLength:64];
    uint8_t *rawPtr = raw.mutableBytes;
    
    if (rLen > 32 || sLen > 32) return nil;
    
    memcpy(rawPtr + (32 - rLen), rBytes, rLen);
    memcpy(rawPtr + 32 + (32 - sLen), sBytes, sLen);
    
    return raw;
}

#pragma mark - PLC Directory Reference Operation Tests

/// Helper: convert NSData to hex string for comparison with reference output.
- (NSString *)hexStringFromData:(NSData *)data {
    const uint8_t *bytes = data.bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:data.length * 2];
    for (NSUInteger i = 0; i < data.length; i++) {
        [hex appendFormat:@"%02x", bytes[i]];
    }
    return hex;
}

/// Test that our CBOR encoding matches the reference @ipld/dag-cbor output
/// for a real legacy "create" operation from plc.directory.
- (void)testLegacyCreateOperationCBORMatchesReference {
    // Real operation from plc.directory export (did:plc:ragtjsm2j2vknwkz3zp4oxrd)
    NSDictionary *opDict = @{
        @"sig": @"DyaPWDItkJnVkN1izINSW-fdjUzP9BkIKlD7SnzD5axfK_870ZZ-1EYcrQLQtP9VkWcp2cdbyIHprjPfeUs8WQ",
        @"prev": [NSNull null],
        @"type": @"create",
        @"handle": @"paul.bsky.social",
        @"service": @"https://bsky.social",
        @"signingKey": @"did:key:zQ3shP5TBe1sQfSttXty15FAEHV1DZgcxRZNxvEWnPfLFwLxJ",
        @"recoveryKey": @"did:key:zQ3shhCGUqDKjStzuDxPkTxN6ujddP4RkEKJJouJGRRkaLGbg"
    };

    PLCOperation *op = [PLCOperation operationFromDictionary:opDict error:nil];
    XCTAssertNotNil(op, @"operationFromDictionary should parse legacy create op");

    // Get unsigned data (strips sig, did, cid)
    NSDictionary *unsignedData = [self.auditor unsignedDataForOperation:op];
    XCTAssertNotNil(unsignedData);

    // CBOR-encode the unsigned data
    NSError *cborError = nil;
    NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:unsignedData error:&cborError];
    XCTAssertNotNil(cborData, @"CBOR encoding should succeed: %@", cborError);
    NSString *cborHex = [self hexStringFromData:cborData];

    // Reference CBOR hex from @ipld/dag-cbor (Node.js):
    // a66470726576f66474797065666372656174656668616e646c65707061756c2e62736b792e736f6369616c67736572766963657368747470733a2f2f62736b792e736f6369616c6a7369676e696e674b657978396469643a6b65793a7a513373685035544265317351665374745874793135464145485631445a676378525a4e787645576e50664c46774c784a6b7265636f766572794b657978396469643a6b65793a7a513373686843475571444b6a53747a754478506b54784e36756a64645034526b454b4a4a6f754a4752526b614c476267
    NSString *referenceCBORHex = @"a66470726576f66474797065666372656174656668616e646c65707061756c2e62736b792e736f6369616c67736572766963657368747470733a2f2f62736b792e736f6369616c6a7369676e696e674b657978396469643a6b65793a7a513373685035544265317351665374745874793135464145485631445a676378525a4e787645576e50664c46774c784a6b7265636f766572794b657978396469643a6b65793a7a513373686843475571444b6a53747a754478506b54784e36756a64645034526b454b4a4a6f754a4752526b614c476267";

    XCTAssertEqualObjects(cborHex, referenceCBORHex,
        @"CBOR encoding must match @ipld/dag-cbor reference. Got: %@", cborHex);

    // Verify SHA-256 hash matches reference
    NSData *hash = [CryptoUtils sha256:cborData];
    NSString *hashHex = [self hexStringFromData:hash];
    NSString *referenceHashHex = @"8fe117c12e21f8e40cd83d95df85c9589c880619a93e96de1da31d17c84f60c9";

    XCTAssertEqualObjects(hashHex, referenceHashHex,
        @"SHA-256 hash must match reference. Got: %@", hashHex);
}

/// Test that our CBOR encoding matches the reference @ipld/dag-cbor output
/// for a real "plc_operation" from plc.directory.
- (void)testPlcOperationCBORMatchesReference {
    // Real operation from plc.directory export (did:plc:dyyok4rfpeuuvmqy22kwrwbc)
    NSDictionary *opDict = @{
        @"sig": @"hjZD_Usv6W5_R1UC0lKeT7hShj-HJXpJtAmkpSFUvMFp-ecf6sSVaErNfiUZlGwQ3NUWAVJinu9voBHlThxh6g",
        @"prev": [NSNull null],
        @"type": @"plc_operation",
        @"services": @{
            @"atproto_pds": @{
                @"type": @"AtprotoPersonalDataServer",
                @"endpoint": @"https://amanita.us-east.host.bsky.network"
            }
        },
        @"alsoKnownAs": @[@"at://6v12v.bsky.social"],
        @"rotationKeys": @[
            @"did:key:zQ3shhCGUqDKjStzuDxPkTxN6ujddP4RkEKJJouJGRRkaLGbg",
            @"did:key:zQ3shpKnbdPx3g3CmPf5cRVTPe1HtSwVn5ish3wSnDPQCbLJK"
        ],
        @"verificationMethods": @{
            @"atproto": @"did:key:zQ3shQpHTWXusL1Snk6yEYn6oV8q7ePZmFdcrYGLqDjatxAZW"
        }
    };

    PLCOperation *op = [PLCOperation operationFromDictionary:opDict error:nil];
    XCTAssertNotNil(op, @"operationFromDictionary should parse plc_operation");

    NSDictionary *unsignedData = [self.auditor unsignedDataForOperation:op];
    XCTAssertNotNil(unsignedData);

    NSError *cborError = nil;
    NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:unsignedData error:&cborError];
    XCTAssertNotNil(cborData, @"CBOR encoding should succeed: %@", cborError);
    NSString *cborHex = [self hexStringFromData:cborData];

    // Reference CBOR hex from @ipld/dag-cbor (Node.js):
    NSString *referenceCBORHex = @"a66470726576f664747970656d706c635f6f7065726174696f6e687365727669636573a16b617470726f746f5f706473a264747970657819417470726f746f506572736f6e616c4461746153657276657268656e64706f696e74782968747470733a2f2f616d616e6974612e75732d656173742e686f73742e62736b792e6e6574776f726b6b616c736f4b6e6f776e4173817661743a2f2f36763132762e62736b792e736f6369616c6c726f746174696f6e4b6579738278396469643a6b65793a7a513373686843475571444b6a53747a754478506b54784e36756a64645034526b454b4a4a6f754a4752526b614c47626778396469643a6b65793a7a51337368704b6e62645078336733436d5066356352565450653148745377566e356973683377536e44505143624c4a4b73766572696669636174696f6e4d6574686f6473a167617470726f746f78396469643a6b65793a7a5133736851704854575875734c31536e6b367945596e366f5638713765505a6d4664637259474c71446a617478415a57";

    XCTAssertEqualObjects(cborHex, referenceCBORHex,
        @"CBOR encoding must match @ipld/dag-cbor reference. Got: %@", cborHex);

    NSData *hash = [CryptoUtils sha256:cborData];
    NSString *hashHex = [self hexStringFromData:hash];
    NSString *referenceHashHex = @"58839a04feb4d0eae2feae37c8d37eb352abd30a342b6bc2ff92f36d065aeff7";

    XCTAssertEqualObjects(hashHex, referenceHashHex,
        @"SHA-256 hash must match reference. Got: %@", hashHex);
}

/// Test that a real legacy "create" operation from plc.directory verifies correctly.
- (void)testLegacyCreateOperationSignatureVerification {
    // Real operation from plc.directory export (did:plc:ragtjsm2j2vknwkz3zp4oxrd)
    NSDictionary *opDict = @{
        @"sig": @"DyaPWDItkJnVkN1izINSW-fdjUzP9BkIKlD7SnzD5axfK_870ZZ-1EYcrQLQtP9VkWcp2cdbyIHprjPfeUs8WQ",
        @"prev": [NSNull null],
        @"type": @"create",
        @"handle": @"paul.bsky.social",
        @"service": @"https://bsky.social",
        @"signingKey": @"did:key:zQ3shP5TBe1sQfSttXty15FAEHV1DZgcxRZNxvEWnPfLFwLxJ",
        @"recoveryKey": @"did:key:zQ3shhCGUqDKjStzuDxPkTxN6ujddP4RkEKJJouJGRRkaLGbg"
    };

    PLCOperation *op = [PLCOperation operationFromDictionary:opDict error:nil];
    XCTAssertNotNil(op);

    // Per the PLC spec, legacy create operations are signed by the signingKey.
    // The normalized rotationKeys for a create op are [recoveryKey, signingKey].
    NSArray *rotationKeys = @[
        @"did:key:zQ3shhCGUqDKjStzuDxPkTxN6ujddP4RkEKJJouJGRRkaLGbg",
        @"did:key:zQ3shP5TBe1sQfSttXty15FAEHV1DZgcxRZNxvEWnPfLFwLxJ"
    ];

    NSError *error = nil;
    NSString *verifiedKey = [self.auditor verifySignatureForOperation:op allowedKeys:rotationKeys error:&error];
    XCTAssertNotNil(verifiedKey, @"Signature should verify against one of the rotation keys. Error: %@", error);
    // The signingKey should be the one that verifies (not the recoveryKey)
    XCTAssertEqualObjects(verifiedKey, @"did:key:zQ3shP5TBe1sQfSttXty15FAEHV1DZgcxRZNxvEWnPfLFwLxJ",
        @"Legacy create operations are signed by the signingKey");
}

/// Test that a real "plc_operation" from plc.directory verifies correctly.
- (void)testPlcOperationSignatureVerification {
    NSDictionary *opDict = @{
        @"sig": @"hjZD_Usv6W5_R1UC0lKeT7hShj-HJXpJtAmkpSFUvMFp-ecf6sSVaErNfiUZlGwQ3NUWAVJinu9voBHlThxh6g",
        @"prev": [NSNull null],
        @"type": @"plc_operation",
        @"services": @{
            @"atproto_pds": @{
                @"type": @"AtprotoPersonalDataServer",
                @"endpoint": @"https://amanita.us-east.host.bsky.network"
            }
        },
        @"alsoKnownAs": @[@"at://6v12v.bsky.social"],
        @"rotationKeys": @[
            @"did:key:zQ3shhCGUqDKjStzuDxPkTxN6ujddP4RkEKJJouJGRRkaLGbg",
            @"did:key:zQ3shpKnbdPx3g3CmPf5cRVTPe1HtSwVn5ish3wSnDPQCbLJK"
        ],
        @"verificationMethods": @{
            @"atproto": @"did:key:zQ3shQpHTWXusL1Snk6yEYn6oV8q7ePZmFdcrYGLqDjatxAZW"
        }
    };

    PLCOperation *op = [PLCOperation operationFromDictionary:opDict error:nil];
    XCTAssertNotNil(op);

    NSArray *rotationKeys = @[
        @"did:key:zQ3shhCGUqDKjStzuDxPkTxN6ujddP4RkEKJJouJGRRkaLGbg",
        @"did:key:zQ3shpKnbdPx3g3CmPf5cRVTPe1HtSwVn5ish3wSnDPQCbLJK"
    ];

    NSError *error = nil;
    NSString *verifiedKey = [self.auditor verifySignatureForOperation:op allowedKeys:rotationKeys error:&error];
    XCTAssertNotNil(verifiedKey, @"Signature should verify against one of the rotation keys. Error: %@", error);
}

/// Test DID derivation for a real legacy "create" operation.
- (void)testLegacyCreateOperationDIDDerivation {
    NSDictionary *opDict = @{
        @"sig": @"DyaPWDItkJnVkN1izINSW-fdjUzP9BkIKlD7SnzD5axfK_870ZZ-1EYcrQLQtP9VkWcp2cdbyIHprjPfeUs8WQ",
        @"prev": [NSNull null],
        @"type": @"create",
        @"handle": @"paul.bsky.social",
        @"service": @"https://bsky.social",
        @"signingKey": @"did:key:zQ3shP5TBe1sQfSttXty15FAEHV1DZgcxRZNxvEWnPfLFwLxJ",
        @"recoveryKey": @"did:key:zQ3shhCGUqDKjStzuDxPkTxN6ujddP4RkEKJJouJGRRkaLGbg"
    };

    PLCOperation *op = [PLCOperation operationFromDictionary:opDict error:nil];
    XCTAssertNotNil(op);

    NSString *derivedDID = [PLCOperation calculateDIDForSignedOperation:[op toDictionary]];
    XCTAssertEqualObjects(derivedDID, @"did:plc:ragtjsm2j2vknwkz3zp4oxrd",
        @"DID derivation must match the expected DID from plc.directory");
}

@end
