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

- (void)testUpdateHandleOperationValidation {
    NSDictionary *json = @{
        @"did": @"did:plc:123",
        @"prev": @"cid:456",
        @"sig": @"sig789",
        @"type": @"update_handle",
        @"handle": @"newhandle.bsky.social"
    };
    
    NSError *error = nil;
    PLCOperation *op = [PLCOperation operationFromDictionary:json error:&error];
    
    XCTAssertNil(error);
    XCTAssertNotNil(op);
    XCTAssertEqualObjects(op.data[@"type"], @"update_handle");
    XCTAssertEqualObjects(op.data[@"handle"], @"newhandle.bsky.social");
}

- (void)testUpdateHandleOperationMissingHandle {
    NSDictionary *json = @{
        @"did": @"did:plc:123",
        @"prev": @"cid:456",
        @"sig": @"sig789",
        @"type": @"update_handle"
    };
    
    NSError *error = nil;
    PLCOperation *op = [PLCOperation operationFromDictionary:json error:&error];
    
    XCTAssertNotNil(error);
    XCTAssertNil(op);
}

- (void)testUpdateHandleOperationInvalidHandle {
    NSDictionary *json = @{
        @"did": @"did:plc:123",
        @"prev": @"cid:456",
        @"sig": @"sig789",
        @"type": @"update_handle",
        @"handle": @"not a valid handle"
    };
    
    NSError *error = nil;
    PLCOperation *op = [PLCOperation operationFromDictionary:json error:&error];
    
    XCTAssertNotNil(error);
    XCTAssertNil(op);
}

- (void)testStateReplayerUpdateHandle {
    Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:nil];
    NSString *pubKeyHex = [[CryptoUtils hexStringFromData:keyPair.compressedPublicKey] lowercaseString];
    
    NSDictionary *createData = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[pubKeyHex],
        @"verificationMethods": @{@"atproto": pubKeyHex},
        @"alsoKnownAs": @[@"oldhandle.bsky.social"],
        @"services": @{},
        @"prev": [NSNull null]
    };
    
    NSString *did = [PLCOperation calculateDIDForData:createData];
    
    PLCOperation *createOp = [[PLCOperation alloc] init];
    createOp.did = did;
    createOp.prev = nil;
    createOp.sig = @"test_sig";
    createOp.data = createData;
    
    NSData *createHash = [self hashForData:createData];
    
    NSString *prevHash = [CryptoUtils hexStringFromData:createHash];
    
    NSDictionary *updateHandleData = @{
        @"type": @"update_handle",
        @"handle": @"newhandle.bsky.social",
        @"prev": prevHash
    };
    
    PLCOperation *updateOp = [[PLCOperation alloc] init];
    updateOp.did = did;
    updateOp.prev = prevHash;
    updateOp.sig = @"test_sig";
    updateOp.data = updateHandleData;
    
    NSError *error = nil;
    PLCDIDState *state = [PLCStateReplayer replayHistory:@[createOp, updateOp] error:&error];
    
    XCTAssertNil(error);
    XCTAssertNotNil(state);
    XCTAssertEqualObjects(state.did, did);
    XCTAssertNotNil(state.alsoKnownAs);
    XCTAssertEqual(state.alsoKnownAs.count, 1);
    XCTAssertEqualObjects(state.alsoKnownAs.firstObject, @"newhandle.bsky.social");
}

- (void)testStateReplayerMultipleHandleUpdates {
    Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:nil];
    NSString *pubKeyHex = [[CryptoUtils hexStringFromData:keyPair.compressedPublicKey] lowercaseString];
    
    NSDictionary *createData = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[pubKeyHex],
        @"verificationMethods": @{@"atproto": pubKeyHex},
        @"alsoKnownAs": @[@"handle1.bsky.social"],
        @"services": @{},
        @"prev": [NSNull null]
    };
    
    NSString *did = [PLCOperation calculateDIDForData:createData];
    
    PLCOperation *createOp = [[PLCOperation alloc] init];
    createOp.did = did;
    createOp.prev = nil;
    createOp.sig = @"test_sig";
    createOp.data = createData;
    
    NSData *createHash = [self hashForData:createData];
    NSString *prevHash1 = [CryptoUtils hexStringFromData:createHash];
    
    NSDictionary *updateHandleData1 = @{
        @"type": @"update_handle",
        @"handle": @"handle2.bsky.social",
        @"prev": prevHash1
    };
    
    PLCOperation *updateOp1 = [[PLCOperation alloc] init];
    updateOp1.did = did;
    updateOp1.prev = prevHash1;
    updateOp1.sig = @"test_sig";
    updateOp1.data = updateHandleData1;
    
    NSData *updateHash1 = [self hashForData:updateHandleData1];
    NSString *prevHash2 = [CryptoUtils hexStringFromData:updateHash1];
    
    NSDictionary *updateHandleData2 = @{
        @"type": @"update_handle",
        @"handle": @"handle3.bsky.social",
        @"prev": prevHash2
    };
    
    PLCOperation *updateOp2 = [[PLCOperation alloc] init];
    updateOp2.did = did;
    updateOp2.prev = prevHash2;
    updateOp2.sig = @"test_sig";
    updateOp2.data = updateHandleData2;
    
    NSError *error = nil;
    PLCDIDState *state = [PLCStateReplayer replayHistory:@[createOp, updateOp1, updateOp2] error:&error];
    
    XCTAssertNil(error);
    XCTAssertNotNil(state);
    XCTAssertNotNil(state.alsoKnownAs);
    XCTAssertEqual(state.alsoKnownAs.count, 1);
    XCTAssertEqualObjects(state.alsoKnownAs.firstObject, @"handle3.bsky.social");
}

- (NSData *)hashForData:(NSDictionary *)data {
    NSError *error = nil;
    NSData *cbor = [ATProtoCBORSerialization encodeDataWithJSONObject:data error:&error];
    if (!cbor) return [NSData data];
    return [CryptoUtils sha256:cbor];
}

@end
