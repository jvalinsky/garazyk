#import <XCTest/XCTest.h>
#import "PLC/PLCAuditor.h"
#import "PLC/PLCMockStore.h"
#import "PLC/PLCOperation.h"
#import "Auth/Secp256k1.h"
#import "Auth/CryptoUtils.h"

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

- (void)testAuditorFailsOnEmptyHistory {
    NSError *error = nil;
    BOOL success = [self.auditor verifyDID:@"did:plc:test" error:&error];
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
}

- (void)testAuditorRejectsInvalidSignature {
    Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:nil];
    XCTAssertNotNil(keyPair);

    NSDictionary *opData = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[[CryptoUtils hexStringFromData:keyPair.compressedPublicKey]],
        @"verificationMethods": @{@"atproto": [CryptoUtils hexStringFromData:keyPair.compressedPublicKey]},
        @"alsoKnownAs": @[@"at://test.com"],
        @"services": @{},
        @"prev": [NSNull null]
    };

    // Correct signature would be over opData (canonicalized)
    // For this test, we just provide a dummy signature
    PLCOperation *op = [[PLCOperation alloc] init];
    op.did = @"did:plc:test";
    op.sig = @"invalid_signature_hex";
    op.data = opData;
    op.prev = nil;

    [self.store appendOperation:op error:nil];

    NSError *error = nil;
    BOOL success = [self.auditor verifyDID:op.did error:&error];
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.localizedDescription containsString:@"Signature"]);
}

- (void)testAuditorRejectsMismatchedPrevHash {
    Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:nil];
    NSString *pubKeyHex = [CryptoUtils hexStringFromData:keyPair.compressedPublicKey];

    // 1. Genesis operation
    NSDictionary *op1Data = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[pubKeyHex],
        @"verificationMethods": @{@"atproto": pubKeyHex},
        @"alsoKnownAs": @[@"at://test.com"],
        @"services": @{},
        @"prev": [NSNull null]
    };
    NSData *op1Hash = [self.auditor hashForOperationData:op1Data];
    NSData *op1Sig = [keyPair signHash:op1Hash error:nil];

    PLCOperation *op1 = [[PLCOperation alloc] init];
    op1.did = @"did:plc:test";
    op1.sig = [CryptoUtils hexStringFromData:op1Sig];
    op1.data = op1Data;
    op1.prev = nil;
    [self.store appendOperation:op1 error:nil];

    // 2. Second operation with WRONG prev hash
    NSDictionary *op2Data = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[pubKeyHex],
        @"verificationMethods": @{@"atproto": pubKeyHex},
        @"alsoKnownAs": @[@"at://test.com"],
        @"services": @{},
        @"prev": @"wrong_prev_hash"
    };
    NSData *op2Hash = [self.auditor hashForOperationData:op2Data];
    NSData *op2Sig = [keyPair signHash:op2Hash error:nil];

    PLCOperation *op2 = [[PLCOperation alloc] init];
    op2.did = @"did:plc:test";
    op2.sig = [CryptoUtils hexStringFromData:op2Sig];
    op2.data = op2Data;
    op2.prev = @"wrong_prev_hash";
    [self.store appendOperation:op2 error:nil];

    NSError *error = nil;
    BOOL success = [self.auditor verifyDID:op1.did error:&error];
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.localizedDescription containsString:@"Prev hash mismatch"]);
}

- (void)testAuditorValidatesMultiStepChainWithKeyRotation {
    Secp256k1KeyPair *key1 = [[Secp256k1 shared] generateKeyPairWithError:nil];
    Secp256k1KeyPair *key2 = [[Secp256k1 shared] generateKeyPairWithError:nil];
    NSString *key1Hex = [CryptoUtils hexStringFromData:key1.compressedPublicKey];
    NSString *key2Hex = [CryptoUtils hexStringFromData:key2.compressedPublicKey];

    // 1. Genesis operation signed by key1, authorizing key1
    NSDictionary *op1Data = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[key1Hex],
        @"verificationMethods": @{@"atproto": key1Hex},
        @"alsoKnownAs": @[@"at://test.com"],
        @"services": @{},
        @"prev": [NSNull null]
    };
    NSData *op1Hash = [self.auditor hashForOperationData:op1Data];
    NSData *op1Sig = [key1 signHash:op1Hash error:nil];

    PLCOperation *op1 = [[PLCOperation alloc] init];
    op1.did = @"did:plc:test";
    op1.sig = [CryptoUtils hexStringFromData:op1Sig];
    op1.data = op1Data;
    op1.prev = nil;
    [self.store appendOperation:op1 error:nil];

    // 2. Second operation signed by key1, rotating to key2
    NSDictionary *op2Data = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[key2Hex],
        @"verificationMethods": @{@"atproto": key2Hex},
        @"alsoKnownAs": @[@"at://test.com"],
        @"services": @{},
        @"prev": [CryptoUtils hexStringFromData:op1Hash]
    };
    NSData *op2Hash = [self.auditor hashForOperationData:op2Data];
    NSData *op2Sig = [key1 signHash:op2Hash error:nil]; // Signed by key1 (authorized by op1)

    PLCOperation *op2 = [[PLCOperation alloc] init];
    op2.did = @"did:plc:test";
    op2.sig = [CryptoUtils hexStringFromData:op2Sig];
    op2.data = op2Data;
    op2.prev = [CryptoUtils hexStringFromData:op1Hash];
    [self.store appendOperation:op2 error:nil];

    // 3. Third operation signed by key2
    NSDictionary *op3Data = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[key2Hex],
        @"verificationMethods": @{@"atproto": key2Hex},
        @"alsoKnownAs": @[@"at://test.com"],
        @"services": @{},
        @"prev": [CryptoUtils hexStringFromData:op2Hash]
    };
    NSData *op3Hash = [self.auditor hashForOperationData:op3Data];
    NSData *op3Sig = [key2 signHash:op3Hash error:nil]; // Signed by key2 (authorized by op2)

    PLCOperation *op3 = [[PLCOperation alloc] init];
    op3.did = @"did:plc:test";
    op3.sig = [CryptoUtils hexStringFromData:op3Sig];
    op3.data = op3Data;
    op3.prev = [CryptoUtils hexStringFromData:op2Hash];
    [self.store appendOperation:op3 error:nil];

    NSError *error = nil;
    BOOL success = [self.auditor verifyDID:op1.did error:&error];
    XCTAssertTrue(success, @"Auditor should accept valid chain with key rotation. Error: %@", error);
}

@end
