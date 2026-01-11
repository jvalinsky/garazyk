#import <XCTest/XCTest.h>
#import "Core/ATProtoValidator.h"
#import "App/Services/PDSAccountService.h"
#import "App/Services/PDSRecordService.h"
#import "App/Services/PDSBlobService.h"

#import "Core/ATProtoCBORSerialization.h"

@interface IdentifierTests : XCTestCase
@end

@implementation IdentifierTests

- (void)testCBORMapSorting {
    // { "b": 2, "a": 1 } should encode same as { "a": 1, "b": 2 }
    // DAG-CBOR requires bytewise sorting of keys
    NSDictionary *dict1 = @{@"b": @2, @"a": @1};
    NSDictionary *dict2 = @{@"a": @1, @"b": @2};
    
    NSError *error = nil;
    NSData *data1 = [ATProtoCBORSerialization encodeDataWithJSONObject:dict1 error:&error];
    XCTAssertNil(error);
    NSData *data2 = [ATProtoCBORSerialization encodeDataWithJSONObject:dict2 error:&error];
    XCTAssertNil(error);
    
    XCTAssertEqualObjects(data1, data2);
    
    // Ensure "a" comes before "b" in encoding
    // Map header 0xA2 (map(2))
    // Key "a" (0x61 'a') -> value 1 (0x01)
    // Key "b" (0x61 'b') -> value 2 (0x02)
    // Expected: A2 61 61 01 61 62 02
    const uint8_t expected[] = {0xA2, 0x61, 0x61, 0x01, 0x61, 0x62, 0x02};
    NSData *expectedData = [NSData dataWithBytes:expected length:sizeof(expected)];
    XCTAssertEqualObjects(data1, expectedData);
}

- (void)testDIDValidation {
    // Valid cases
    XCTAssertTrue([ATProtoValidator validateDID:@"did:plc:z72i7hdynmk6r22z27h6tvur" error:nil]);
    XCTAssertTrue([ATProtoValidator validateDID:@"did:web:blueskyweb.xyz" error:nil]);

    // Invalid cases
    NSError *error = nil;
    XCTAssertFalse([ATProtoValidator validateDID:@"did:plc:AF85A362-B87D-4858-BCE5-85BD4EFC6E1D" error:&error]); // Uppercase UUID
    XCTAssertNotNil(error);

    XCTAssertFalse([ATProtoValidator validateDID:@"did:method:val" error:nil]); // Unsupported method
    XCTAssertFalse([ATProtoValidator validateDID:@"did:plc:short" error:nil]); // Too short
    XCTAssertFalse([ATProtoValidator validateDID:(id)nil error:nil]);
}

- (void)testHandleValidation {
    // Valid cases
    XCTAssertTrue([ATProtoValidator validateHandle:@"jay.bsky.social" error:nil]);
    XCTAssertTrue([ATProtoValidator validateHandle:@"alice.test" error:nil]); // .test allowed for dev

    XCTAssertTrue([ATProtoValidator validateHandle:@"8.cn" error:nil]);

    // Invalid cases
    XCTAssertFalse([ATProtoValidator validateHandle:@"jo@hn.test" error:nil]);
    XCTAssertFalse([ATProtoValidator validateHandle:@"john..test" error:nil]);
    XCTAssertFalse([ATProtoValidator validateHandle:@"example.arpa" error:nil]); // Reserved
    XCTAssertFalse([ATProtoValidator validateHandle:@"example.onion" error:nil]); // Reserved
}

- (void)testCIDValidation {
    // Valid cases
    // Use a valid base32 CID (generated from "test data")
    XCTAssertTrue([ATProtoValidator validateCID:@"bafyreiern4acpjlva5gookrtc534gr4nmuj7pbvfsg6yslnbuv336izv7e" error:nil]);

    // Invalid cases
    XCTAssertFalse([ATProtoValidator validateCID:@"bAFKTO5NR2ACPEXZYSTB6TPSIK3RUVQHUK52UOU3SLZMYJVINGXYVXKY" error:nil]); // Uppercase
    XCTAssertFalse([ATProtoValidator validateCID:@"Qm..." error:nil]); // CIDv0
    // Invalid base32 chars (0, 1, 8, 9)
    XCTAssertFalse([ATProtoValidator validateCID:@"bafyrei3775b1d004f25f3894c3e9be4856e34ac0f457754753725e5984d50d3" error:nil]);
    XCTAssertFalse([ATProtoValidator validateCID:(id)nil error:nil]);
}

- (void)testDIDGeneration {
    PDSAccountService *service = [[PDSAccountService alloc] initWithDatabasePool:(id)nil];
    SEL selector = NSSelectorFromString(@"generatePlcIdentifier");
    if ([service respondsToSelector:selector]) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        NSString *did = [service performSelector:selector];
        #pragma clang diagnostic pop
        
        NSLog(@"Generated DID: %@", did);
        XCTAssertTrue([ATProtoValidator validateDID:did error:nil]);
        XCTAssertTrue([did hasPrefix:@"did:plc:"]);
        XCTAssertEqual(did.length, 32); // did:plc: + 24 chars = 8 + 24 = 32
        XCTAssertEqualObjects(did, [did lowercaseString]);
    } else {
        XCTFail(@"generatePlcIdentifier method not found");
    }
}

- (void)testCIDGeneration {
    PDSRecordService *service = [[PDSRecordService alloc] initWithDatabasePool:(id)nil];
    NSData *testData = [@"test data" dataUsingEncoding:NSUTF8StringEncoding];
    
    SEL selector = NSSelectorFromString(@"generateCIDForData:error:");
    if ([service respondsToSelector:selector]) {
        NSMethodSignature *signature = [service methodSignatureForSelector:selector];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        [invocation setSelector:selector];
        [invocation setTarget:service];
        [invocation setArgument:&testData atIndex:2];
        
        [invocation invoke];
        
        __unsafe_unretained NSString *cid = nil;
        [invocation getReturnValue:&cid];
        
        NSLog(@"Generated CID: %@", cid);
        XCTAssertTrue([ATProtoValidator validateCID:cid error:nil]);
        XCTAssertEqualObjects(cid, [cid lowercaseString]);
        XCTAssertTrue([cid hasPrefix:@"bafyrei"]);
    } else {
        XCTFail(@"generateCIDForData:error: method not found");
    }
}

@end
