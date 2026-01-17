#import <Foundation/Foundation.h>
#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif
#import "../../Sources/PLC/PLCOperation.h"
#import "Auth/Secp256k1.h"
#import "Auth/CryptoUtils.h"
#import "Core/ATProtoCBORSerialization.h"

@interface PLCOperationTests : XCTestCase
@end

@implementation PLCOperationTests

- (void)testParseFromDictionary {
    NSDictionary *json = @{
        @"did": @"did:plc:123",
        @"prev": @"cid:456",
        @"sig": @"sig789",
        @"type": @"plc_operation"
    };
    
    NSError *error = nil;
    PLCOperation *op = [PLCOperation operationFromDictionary:json error:&error];
    
    XCTAssertNil(error);
    XCTAssertNotNil(op);
    XCTAssertEqualObjects(op.did, @"did:plc:123");
    XCTAssertEqualObjects(op.prev, @"cid:456");
    XCTAssertEqualObjects(op.sig, @"sig789");
    XCTAssertEqualObjects(op.data[@"type"], @"plc_operation");
}

- (void)testParseFromDictionaryMissingOptionalPrev {
    NSDictionary *json = @{
        @"did": @"did:plc:123",
        @"sig": @"sig789",
        @"type": @"plc_operation"
    };
    
    NSError *error = nil;
    PLCOperation *op = [PLCOperation operationFromDictionary:json error:&error];
    
    XCTAssertNil(error);
    XCTAssertNotNil(op);
    XCTAssertEqualObjects(op.did, @"did:plc:123");
    XCTAssertNil(op.prev);
    XCTAssertEqualObjects(op.sig, @"sig789");
    XCTAssertEqualObjects(op.data[@"type"], @"plc_operation");
}

- (void)testParseFromDictionaryMissingRequiredField {
    NSDictionary *json = @{
        @"did": @"did:plc:123"
        // missing sig
    };
    
    NSError *error = nil;
    PLCOperation *op = [PLCOperation operationFromDictionary:json error:&error];
    
    XCTAssertNotNil(error);
    XCTAssertNil(op);
}

- (void)testStateReplayerUpdateHandle {
    Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:nil];
    NSString *didKey = [keyPair didKeyString];
    
    NSDictionary *createData = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[didKey],
        @"verificationMethods": @{@"atproto": didKey},
        @"alsoKnownAs": @[@"at://oldhandle.bsky.social"],
        @"services": @{},
        @"prev": [NSNull null]
    };
    
    NSString *did = [PLCOperation calculateDIDForData:createData];
    
    PLCOperation *createOp = [[PLCOperation alloc] init];
    createOp.did = did;
    createOp.prev = nil;
    createOp.sig = @"test_sig";
    createOp.data = createData;
    
    NSError *cidError = nil;
    NSString *prevCid = [PLCOperation calculateCIDForOperation:[createOp toDictionary] error:&cidError];
    XCTAssertNotNil(prevCid);
    
    NSDictionary *updateHandleData = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[didKey],
        @"verificationMethods": @{@"atproto": didKey},
        @"alsoKnownAs": @[@"at://newhandle.bsky.social"],
        @"services": @{},
        @"prev": prevCid
    };
    
    PLCOperation *updateOp = [[PLCOperation alloc] init];
    updateOp.did = did;
    updateOp.prev = prevCid;
    updateOp.sig = @"test_sig";
    updateOp.data = updateHandleData;
    
    NSError *error = nil;
    PLCDIDState *state = [PLCStateReplayer replayHistory:@[createOp, updateOp] error:&error];
    
    XCTAssertNil(error);
    XCTAssertNotNil(state);
    XCTAssertEqualObjects(state.did, did);
    XCTAssertNotNil(state.alsoKnownAs);
    XCTAssertEqual(state.alsoKnownAs.count, 1);
    XCTAssertEqualObjects(state.alsoKnownAs.firstObject, @"at://newhandle.bsky.social");
}

- (void)testStateReplayerMultipleHandleUpdates {
    Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:nil];
    NSString *didKey = [keyPair didKeyString];
    
    NSDictionary *createData = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[didKey],
        @"verificationMethods": @{@"atproto": didKey},
        @"alsoKnownAs": @[@"at://handle1.bsky.social"],
        @"services": @{},
        @"prev": [NSNull null]
    };
    
    NSString *did = [PLCOperation calculateDIDForData:createData];
    
    PLCOperation *createOp = [[PLCOperation alloc] init];
    createOp.did = did;
    createOp.prev = nil;
    createOp.sig = @"test_sig";
    createOp.data = createData;
    
    NSError *cidError = nil;
    NSString *prevCid1 = [PLCOperation calculateCIDForOperation:[createOp toDictionary] error:&cidError];
    XCTAssertNotNil(prevCid1);
    
    NSDictionary *updateHandleData1 = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[didKey],
        @"verificationMethods": @{@"atproto": didKey},
        @"alsoKnownAs": @[@"at://handle2.bsky.social"],
        @"services": @{},
        @"prev": prevCid1
    };
    
    PLCOperation *updateOp1 = [[PLCOperation alloc] init];
    updateOp1.did = did;
    updateOp1.prev = prevCid1;
    updateOp1.sig = @"test_sig";
    updateOp1.data = updateHandleData1;
    
    NSString *prevCid2 = [PLCOperation calculateCIDForOperation:[updateOp1 toDictionary] error:&cidError];
    XCTAssertNotNil(prevCid2);
    
    NSDictionary *updateHandleData2 = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[didKey],
        @"verificationMethods": @{@"atproto": didKey},
        @"alsoKnownAs": @[@"at://handle3.bsky.social"],
        @"services": @{},
        @"prev": prevCid2
    };
    
    PLCOperation *updateOp2 = [[PLCOperation alloc] init];
    updateOp2.did = did;
    updateOp2.prev = prevCid2;
    updateOp2.sig = @"test_sig";
    updateOp2.data = updateHandleData2;
    
    NSError *error = nil;
    PLCDIDState *state = [PLCStateReplayer replayHistory:@[createOp, updateOp1, updateOp2] error:&error];
    
    XCTAssertNil(error);
    XCTAssertNotNil(state);
    XCTAssertNotNil(state.alsoKnownAs);
    XCTAssertEqual(state.alsoKnownAs.count, 1);
    XCTAssertEqualObjects(state.alsoKnownAs.firstObject, @"at://handle3.bsky.social");
}

- (NSData *)hashForData:(NSDictionary *)data {
    NSError *error = nil;
    NSData *cbor = [ATProtoCBORSerialization encodeDataWithJSONObject:data error:&error];
    if (!cbor) return [NSData data];
    return [CryptoUtils sha256:cbor];
}

#pragma mark - Test Vectors (Reference: reference/indigo/plc/client_test.go)

- (void)testCBOREncodingTestVector {
    NSDictionary *opData = @{
        @"type": @"create",
        @"signingKey": @"did:key:zDnaeRSYs7c2NpcNA5NRAUqS8DCkLWDyNLnATi28D6w7no7hX",
        @"recoveryKey": @"did:key:zDnaeRSYs7c2NpcNA5NRAUqS8DCkLWDyNLnATi28D6w7no7hX",
        @"handle": @"why.bsky.social",
        @"service": @"bsky.social",
        @"prev": [NSNull null]
    };
    
    NSError *error = nil;
    NSData *cbor = [ATProtoCBORSerialization encodeDataWithJSONObject:opData error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(cbor);
    
    // Using Base64 string from indigo/plc/client_test.go's EncodedOp (with padding added for NSData)
    NSData *expectedCBOR = [[NSData alloc] initWithBase64EncodedString:@"pmRwcmV29mR0eXBlZmNyZWF0ZWZoYW5kbGVvd2h5LmJza3kuc29jaWFsZ3NlcnZpY2VrYnNreS5zb2NpYWxqc2lnbmluZ0tleXg5ZGlkOmtleTp6RG5hZVJTWXM3YzJOcGNOQTVOUkFVcVM4RENrTFdEeU5MbkFUaTI4RDZ3N25vN2hYa3JlY292ZXJ5S2V5eDlkaWQ6a2V5OnpEbmFlUlNZczdjMk5wY05BNU5SQVVxUzhEQ2tMV0R5TkxuQVRpMjhENnc3bm83aFg=" options:0];
    
    XCTAssertEqualObjects(cbor, expectedCBOR, @"CBOR encoding should match reference test vector");
}

- (void)testDIDCalculationTestVector {
    NSDictionary *opData = @{
        @"type": @"create",
        @"signingKey": @"did:key:zDnaeRSYs7c2NpcNA5NRAUqS8DCkLWDyNLnATi28D6w7no7hX",
        @"recoveryKey": @"did:key:zDnaeRSYs7c2NpcNA5NRAUqS8DCkLWDyNLnATi28D6w7no7hX",
        @"handle": @"why.bsky.social",
        @"service": @"bsky.social",
        @"prev": [NSNull null]
    };
    
    NSString *calculatedDID = [PLCOperation calculateDIDForData:opData];
    
    XCTAssertEqualObjects(calculatedDID, @"did:plc:taybjzkanfb23appusr452ga");
}

- (void)testDIDCalculationWithPLCOperation {
    NSDictionary *opData = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[@"did:key:zDnaeRSYs7c2NpcNA5NRAUqS8DCkLWDyNLnATi28D6w7no7hX"],
        @"verificationMethods": @{@"atproto": @"did:key:zDnaeRSYs7c2NpcNA5NRAUqS8DCkLWDyNLnATi28D6w7no7hX"},
        @"alsoKnownAs": @[@"at://test.bsky.social"],
        @"services": @{@"atproto_pds": @{@"type": @"AtprotoPersonalDataServer", @"endpoint": @"https://pds.example.com"}},
        @"prev": [NSNull null]
    };
    
    NSString *calculatedDID = [PLCOperation calculateDIDForData:opData];
    
    XCTAssertTrue([calculatedDID hasPrefix:@"did:plc:"], @"DID should have did:plc: prefix");
    XCTAssertEqual(calculatedDID.length, 32, @"DID should be 32 characters (did:plc: + 24 char hash)");
}

- (void)testSignatureVerificationTestVector {
    Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:nil];
    XCTAssertNotNil(keyPair, @"Key pair should be generated");
    
    NSData *message = [@"test message" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *hash = [CryptoUtils sha256:message];
    NSData *signature = [keyPair signHash:hash error:nil];
    XCTAssertNotNil(signature, @"Signature should be created");
    XCTAssertEqual(signature.length, 64, @"Signature should be 64 bytes (R || S)");
    
    BOOL verified = [[Secp256k1 shared] verifySignature:signature forHash:hash withPublicKey:keyPair.publicKey error:nil];
    XCTAssertTrue(verified, @"Signature should verify");
    
    NSData *wrongMessage = [@"wrong message" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *wrongHash = [CryptoUtils sha256:wrongMessage];
    BOOL wrongVerified = [[Secp256k1 shared] verifySignature:signature forHash:wrongHash withPublicKey:keyPair.publicKey error:nil];
    XCTAssertFalse(wrongVerified, @"Wrong message should not verify");
}

- (void)testOperationSignatureRoundTrip {
    Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:nil];
    XCTAssertNotNil(keyPair);
    
    NSString *didKey = [keyPair didKeyString];
    NSDictionary *opData = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[didKey],
        @"verificationMethods": @{@"atproto": didKey},
        @"alsoKnownAs": @[@"at://test.bsky.social"],
        @"services": @{},
        @"prev": [NSNull null]
    };
    
    NSError *error = nil;
    NSData *cbor = [ATProtoCBORSerialization encodeDataWithJSONObject:opData error:&error];
    XCTAssertNil(error);
    
    NSData *hash = [CryptoUtils sha256:cbor];
    NSData *signature = [keyPair signHash:hash error:&error];
    XCTAssertNil(error);
    
    BOOL verified = [[Secp256k1 shared] verifySignature:signature forHash:hash withPublicKey:keyPair.publicKey error:&error];
    XCTAssertTrue(verified, @"Operation signature should verify");
}

@end
