#import <XCTest/XCTest.h>
#import "PLC/PLCAuditor.h"
#import "PLC/PLCMockStore.h"
#import "PLC/PLCOperation.h"
#import "Auth/Secp256k1.h"
#import "Auth/CryptoUtils.h"
#import "Auth/Crypto/AuthCryptoECDSA.h"
#import "Core/CID.h"
#import <Security/Security.h>

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
    op.did = [PLCOperation calculateDIDForData:opData];
    op.sig = @"invalid_signature";
    op.data = opData;
    op.prev = nil;

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
    op1.did = [PLCOperation calculateDIDForData:op1Data];
    op1.sig = [self base64URLEncode:op1Sig];
    op1.data = op1Data;
    op1.prev = nil;
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
    op1.did = [PLCOperation calculateDIDForData:op1Data];
    op1.sig = [self base64URLEncode:op1Sig];
    op1.data = op1Data;
    op1.prev = nil;
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
    op1.did = [PLCOperation calculateDIDForData:op1Data];
    op1.sig = [self base64URLEncode:op1Sig];
    op1.data = op1Data;
    op1.prev = nil;
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
    op.did = [PLCOperation calculateDIDForData:opData];
    op.sig = [self base64URLEncode:rawSig];
    op.data = opData;
    op.prev = nil;
    
    [self.store appendOperation:op nullifyCIDs:@[] error:nil];
    
    // 6. Verify
    NSError *verifyError = nil;
    BOOL success = [self.auditor verifyDID:op.did error:&verifyError];
    XCTAssertTrue(success, @"Auditor should verify P-256 signed operation. Error: %@", verifyError);
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

@end
