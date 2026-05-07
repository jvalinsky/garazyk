#import <XCTest/XCTest.h>
#import "Repository/MST.h"
#import "Core/CID.h"

@interface MSTUTF8Tests : XCTestCase
@end

@implementation MSTUTF8Tests

- (void)testMSTWithUTF8Keys {
    MST *tree = [[MST alloc] init];
    // Use real-looking CID digest (32 bytes for SHA-256)
    uint8_t digest[32] = {0};
    digest[0] = 1; digest[1] = 2; digest[2] = 3;
    CID *cid = [CID cidWithDigest:[NSData dataWithBytes:digest length:32] codec:0x71];
    
    // Non-ASCII keys (emojis and multi-byte chars)
    // "🔥" is 4 bytes in UTF-8
    NSString *key1 = @"app.bsky.feed.post/🔥";
    NSString *key2 = @"app.bsky.feed.post/🔥🔥";
    
    [tree put:key1 valueCID:cid];
    [tree put:key2 valueCID:cid];
    
    XCTAssertEqualObjects([tree get:key1], cid, @"Should retrieve key1 correctly");
    XCTAssertEqualObjects([tree get:key2], cid, @"Should retrieve key2 correctly");
    
    // Verify serialization/deserialization
    NSData *cbor = [tree serializeToCBOR];
    XCTAssertNotNil(cbor, @"Serialization should produce data");
    
    MST *roundTrip = [MST deserializeFromCBOR:cbor];
    XCTAssertNotNil(roundTrip, @"Deserialization should succeed");
    
    XCTAssertEqualObjects([roundTrip get:key1], cid, @"Round-tripped tree should retrieve key1 correctly");
    XCTAssertEqualObjects([roundTrip get:key2], cid, @"Round-tripped tree should retrieve key2 correctly");
    
    NSArray<MSTEntry *> *all = [roundTrip allEntries];
    XCTAssertEqual(all.count, 2, @"Should have exactly 2 entries");
    
    // MST entries are sorted by key bytes
    XCTAssertEqualObjects(all[0].key, key1);
    XCTAssertEqualObjects(all[1].key, key2);
}

@end
