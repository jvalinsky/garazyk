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

    // Correct signature would be over opData (canonicalized)
    // For this test, we just provide a dummy signature
    PLCOperation *op = [[PLCOperation alloc] init];
    op.did = @"did:plc:test";
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
    op1.did = @"did:plc:test";
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
    op2.did = @"did:plc:test";
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
    op1.did = @"did:plc:test";
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
    op2.did = @"did:plc:test";
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
    op3.did = @"did:plc:test";
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
    op1.did = @"did:plc:test";
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
    op2.did = @"did:plc:test";
    op2.sig = [self base64URLEncode:op2Sig];
    op2.data = op2Data;
    op2.prev = prevCid;
    [self.store appendOperation:op2 nullifyCIDs:@[] error:nil];

    NSError *error = nil;
    BOOL success = [self.auditor verifyDID:op1.did error:&error];
    XCTAssertTrue(success, @"Auditor should accept valid handle update. Error: %@", error);
}

@end
