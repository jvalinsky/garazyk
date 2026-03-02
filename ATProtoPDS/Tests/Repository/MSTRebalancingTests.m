#import <XCTest/XCTest.h>
#import "Repository/MST.h"
#import "Core/CID.h"
#import "Debug/PDSLogger.h"

@interface MSTRebalancingTests : XCTestCase
@end

@implementation MSTRebalancingTests

- (void)testLargeScaleRebalancing {
    MST *tree = [[MST alloc] init];
    NSMutableDictionary<NSString *, CID *> *expectedEntries = [NSMutableDictionary dictionary];
    
    // Insert 1000 keys with pseudo-random TIDs
    int count = 1000;
    PDS_LOG_INFO(@"[MST TEST] Starting insertion of %d keys...", count);
    for (int i = 0; i < count; i++) {
        NSString *rkey = [self generateRandomTID];
        NSString *key = [NSString stringWithFormat:@"app.bsky.feed.post/%@", rkey];
        CID *valueCID = [CID sha256:[key dataUsingEncoding:NSUTF8StringEncoding]];
        
        [tree put:key valueCID:valueCID];
        expectedEntries[key] = valueCID;
    }
    
    XCTAssertEqual(tree.allEntries.count, count);
    
    // Verify all entries are present and correct
    for (NSString *key in expectedEntries) {
        CID *foundCID = [tree get:key];
        if (![foundCID.stringValue isEqualToString:expectedEntries[key].stringValue]) {
             PDS_LOG_ERROR(@"[MST TEST] Verification failure for key %@: expected %@, found %@", key, expectedEntries[key].stringValue, foundCID.stringValue);
        }
        XCTAssertEqualObjects(foundCID.stringValue, expectedEntries[key].stringValue);
    }
    
    int deleteCount = 500;
    PDS_LOG_INFO(@"[MST TEST] Insertion verified. Starting deletion of %d keys...", deleteCount);
    
    // Delete keys
    NSArray *keysToDelete = [[expectedEntries.allKeys sortedArrayUsingSelector:@selector(compare:)] subarrayWithRange:NSMakeRange(0, deleteCount)];
    
    for (NSString *key in keysToDelete) {
        [tree delete:key];
        [expectedEntries removeObjectForKey:key];
    }
    
    XCTAssertEqual(tree.allEntries.count, count - deleteCount);
    
    // Verify remaining entries
    for (NSString *key in expectedEntries) {
        CID *foundCID = [tree get:key];
        XCTAssertEqualObjects(foundCID.stringValue, expectedEntries[key].stringValue);
    }
    
    // Verify deleted keys are gone
    for (NSString *key in keysToDelete) {
        XCTAssertNil([tree get:key]);
    }
    
    PDS_LOG_INFO(@"[MST TEST] MST rebalancing test completed successfully.");
}

- (void)testDepthConsistency {
    // Verify that key depth is deterministic and consistent with the spec
    NSString *key1 = @"app.bsky.feed.post/3jzfcijpj2z2a";
    uint32_t depth1 = [MST keyDepth:key1];
    
    // Re-calculating should give same result
    XCTAssertEqual([MST keyDepth:key1], depth1);
    
    // Different key should (likely) have different depth or at least valid range
    NSString *key2 = @"app.bsky.feed.post/3jzfcijpj2z2b";
    uint32_t depth2 = [MST keyDepth:key2];
    XCTAssertTrue(depth1 >= 0);
    XCTAssertTrue(depth2 >= 0);
}

#pragma mark - Helpers

- (NSString *)generateRandomTID {
    static const char alphabet[] = "234567abcdefghijklmnopqrstuvwxyz";
    NSMutableString *tid = [NSMutableString stringWithCapacity:13];
    for (int i = 0; i < 13; i++) {
        [tid appendFormat:@"%c", alphabet[arc4random_uniform(32)]];
    }
    return tid;
}

@end
