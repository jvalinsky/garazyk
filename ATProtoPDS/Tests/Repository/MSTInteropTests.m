#import <XCTest/XCTest.h>
#import "Repository/MST.h"
#import "Core/CID.h"

@interface MSTInteropTests : XCTestCase
@end

@implementation MSTInteropTests

- (void)testLeadingZeros {
    // MST 'depth' computation (SHA-256 leading zeros)
    // Reference values from indigo/mst/mst_interop_test.go
    
    XCTAssertEqual([MST keyDepthBytes:[@"" dataUsingEncoding:NSUTF8StringEncoding]], 0);
    XCTAssertEqual([MST keyDepthBytes:[@"asdf" dataUsingEncoding:NSUTF8StringEncoding]], 0);
    XCTAssertEqual([MST keyDepthBytes:[@"blue" dataUsingEncoding:NSUTF8StringEncoding]], 1);
    XCTAssertEqual([MST keyDepthBytes:[@"2653ae71" dataUsingEncoding:NSUTF8StringEncoding]], 0);
    XCTAssertEqual([MST keyDepthBytes:[@"88bfafc7" dataUsingEncoding:NSUTF8StringEncoding]], 2);
    XCTAssertEqual([MST keyDepthBytes:[@"2a92d355" dataUsingEncoding:NSUTF8StringEncoding]], 4);
    XCTAssertEqual([MST keyDepthBytes:[@"884976f5" dataUsingEncoding:NSUTF8StringEncoding]], 6);
    XCTAssertEqual([MST keyDepthBytes:[@"app.bsky.feed.post/454397e440ec" dataUsingEncoding:NSUTF8StringEncoding]], 4);
    XCTAssertEqual([MST keyDepthBytes:[@"app.bsky.feed.post/9adeb165882c" dataUsingEncoding:NSUTF8StringEncoding]], 8);
}

- (void)testInteropKnownMaps {
    fprintf(stderr, "testInteropKnownMaps started\n");
    NSString *cid1str = @"bafyreie5cvv4h45feadgeuwhbcutmh6t2ceseocckahdoe6uat64zmz454";
    CID *cid1 = [CID cidFromString:cid1str];
    fprintf(stderr, "cid1 created\n");
    
    // Empty map
    MST *emptyMST = [[MST alloc] init];
    fprintf(stderr, "emptyMST created\n");
    XCTAssertEqualObjects(emptyMST.rootCID.stringValue, @"bafyreie5737gdxlw5i64vzichcalba3z2v5n6icifvx5xytvske7mr3hpm");
    fprintf(stderr, "emptyMST rootCID checked\n");

    // Trivial map
    MST *trivialMST = [[MST alloc] init];
    fprintf(stderr, "trivialMST created\n");
    [trivialMST put:@"com.example.record/3jqfcqzm3fo2j" valueCID:cid1];
    fprintf(stderr, "trivialMST put finished\n");
    XCTAssertEqualObjects(trivialMST.rootCID.stringValue, @"bafyreibj4lsc3aqnrvphp5xmrnfoorvru4wynt6lwidqbm2623a6tatzdu");
    fprintf(stderr, "trivialMST rootCID checked\n");
    
    // Layer 2 map
    MST *layer2MST = [[MST alloc] init];
    [layer2MST put:@"com.example.record/3jqfcqzm3fx2j" valueCID:cid1];
    XCTAssertEqualObjects(layer2MST.rootCID.stringValue, @"bafyreih7wfei65pxzhauoibu3ls7jgmkju4bspy4t2ha2qdjnzqvoy33ai");
    
    // Simple map
    MST *simpleMST = [[MST alloc] init];
    [simpleMST put:@"com.example.record/3jqfcqzm3fp2j" valueCID:cid1];
    [simpleMST put:@"com.example.record/3jqfcqzm3fr2j" valueCID:cid1];
    [simpleMST put:@"com.example.record/3jqfcqzm3fs2j" valueCID:cid1];
    [simpleMST put:@"com.example.record/3jqfcqzm3ft2j" valueCID:cid1];
    [simpleMST put:@"com.example.record/3jqfcqzm4fc2j" valueCID:cid1];
    XCTAssertEqualObjects(simpleMST.rootCID.stringValue, @"bafyreicmahysq4n6wfuxo522m6dpiy7z7qzym3dzs756t5n7nfdgccwq7m");
}

- (void)testInteropEdgeCasesTrimTop {
    NSString *cid1str = @"bafyreie5cvv4h45feadgeuwhbcutmh6t2ceseocckahdoe6uat64zmz454";
    CID *cid1 = [CID cidFromString:cid1str];
    
    NSString *l1root = @"bafyreifnqrwbk6ffmyaz5qtujqrzf5qmxf7cbxvgzktl4e3gabuxbtatv4";
    NSString *l0root = @"bafyreie4kjuxbwkhzg2i5dljaswcroeih4dgiqq6pazcmunwt2byd725vi";
    
    MST *mst = [[MST alloc] init];
    [mst put:@"com.example.record/3jqfcqzm3fn2j" valueCID:cid1];
    [mst put:@"com.example.record/3jqfcqzm3fo2j" valueCID:cid1];
    [mst put:@"com.example.record/3jqfcqzm3fp2j" valueCID:cid1];
    [mst put:@"com.example.record/3jqfcqzm3fs2j" valueCID:cid1];
    [mst put:@"com.example.record/3jqfcqzm3ft2j" valueCID:cid1];
    [mst put:@"com.example.record/3jqfcqzm3fu2j" valueCID:cid1];
    
    XCTAssertEqualObjects(mst.rootCID.stringValue, l1root);
    
    [mst delete:@"com.example.record/3jqfcqzm3fs2j"];
    XCTAssertEqualObjects(mst.rootCID.stringValue, l0root);
}

- (void)testInteropEdgeCasesInsertion {
    NSString *cid1str = @"bafyreie5cvv4h45feadgeuwhbcutmh6t2ceseocckahdoe6uat64zmz454";
    CID *cid1 = [CID cidFromString:cid1str];
    
    NSString *l1root = @"bafyreiettyludka6fpgp33stwxfuwhkzlur6chs4d2v4nkmq2j3ogpdjem";
    NSString *l2root = @"bafyreid2x5eqs4w4qxvc5jiwda4cien3gw2q6cshofxwnvv7iucrmfohpm";

    MST *mst = [[MST alloc] init];
    [mst put:@"com.example.record/3jqfcqzm3fo2j" valueCID:cid1];
    [mst put:@"com.example.record/3jqfcqzm3fp2j" valueCID:cid1];
    [mst put:@"com.example.record/3jqfcqzm3fr2j" valueCID:cid1];
    [mst put:@"com.example.record/3jqfcqzm3fs2j" valueCID:cid1];
    [mst put:@"com.example.record/3jqfcqzm3ft2j" valueCID:cid1];
    [mst put:@"com.example.record/3jqfcqzm3fz2j" valueCID:cid1];
    [mst put:@"com.example.record/3jqfcqzm4fc2j" valueCID:cid1];
    [mst put:@"com.example.record/3jqfcqzm4fd2j" valueCID:cid1];
    [mst put:@"com.example.record/3jqfcqzm4ff2j" valueCID:cid1];
    [mst put:@"com.example.record/3jqfcqzm4fg2j" valueCID:cid1];
    [mst put:@"com.example.record/3jqfcqzm4fh2j" valueCID:cid1];
    
    XCTAssertEqualObjects(mst.rootCID.stringValue, l1root);
    
    [mst put:@"com.example.record/3jqfcqzm3fx2j" valueCID:cid1];
    XCTAssertEqualObjects(mst.rootCID.stringValue, l2root);
    
    [mst delete:@"com.example.record/3jqfcqzm3fx2j"];
    XCTAssertEqualObjects(mst.rootCID.stringValue, l1root);
}

- (void)testInteropEdgeCasesHigher {
    NSString *cid1str = @"bafyreie5cvv4h45feadgeuwhbcutmh6t2ceseocckahdoe6uat64zmz454";
    CID *cid1 = [CID cidFromString:cid1str];
    
    NSString *l0root = @"bafyreidfcktqnfmykz2ps3dbul35pepleq7kvv526g47xahuz3rqtptmky";
    NSString *l2root = @"bafyreiavxaxdz7o7rbvr3zg2liox2yww46t7g6hkehx4i4h3lwudly7dhy";

    MST *mst = [[MST alloc] init];
    [mst put:@"com.example.record/3jqfcqzm3ft2j" valueCID:cid1];
    [mst put:@"com.example.record/3jqfcqzm3fz2j" valueCID:cid1];
    
    XCTAssertEqualObjects(mst.rootCID.stringValue, l0root);
    
    [mst put:@"com.example.record/3jqfcqzm3fx2j" valueCID:cid1];
    XCTAssertEqualObjects(mst.rootCID.stringValue, l2root);
    
    [mst delete:@"com.example.record/3jqfcqzm3fx2j"];
    XCTAssertEqualObjects(mst.rootCID.stringValue, l0root);
}

- (void)testPrefixLen {
    // length of common prefix between strings
    // Reference values from indigo/mst/mst_interop_test.go
    
    XCTAssertEqual([self countPrefixLen:@"abc" and:@"abc"], 3);
    XCTAssertEqual([self countPrefixLen:@"" and:@"abc"], 0);
    XCTAssertEqual([self countPrefixLen:@"abc" and:@""], 0);
    XCTAssertEqual([self countPrefixLen:@"ab" and:@"abc"], 2);
    XCTAssertEqual([self countPrefixLen:@"abc" and:@"ab"], 2);
    XCTAssertEqual([self countPrefixLen:@"abcde" and:@"abc"], 3);
    XCTAssertEqual([self countPrefixLen:@"abc" and:@"abcde"], 3);
    XCTAssertEqual([self countPrefixLen:@"abcde" and:@"abc1"], 3);
    XCTAssertEqual([self countPrefixLen:@"abcde" and:@"abb"], 2);
    XCTAssertEqual([self countPrefixLen:@"abcde" and:@"qbb"], 0);
}

- (NSUInteger)countPrefixLen:(NSString *)s1 and:(NSString *)s2 {
    NSUInteger len1 = s1.length;
    NSUInteger len2 = s2.length;
    NSUInteger minLen = MIN(len1, len2);
    for (NSUInteger i = 0; i < minLen; i++) {
        if ([s1 characterAtIndex:i] != [s2 characterAtIndex:i]) {
            return i;
        }
    }
    return minLen;
}

- (void)testPutAndGet {
    MST *mst = [[MST alloc] init];
    CID *cid1 = [CID cidFromString:@"bafyreie5cvv4h45feadgeuwhbcutmh6t2ceseocckahdoe6uat64zmz454"];
    CID *cid2 = [CID cidFromString:@"bafyreifnqrwbk6ffmyaz5qtujqrzf5qmxf7cbxvgzktl4e3gabuxbtatv4"];
    
    [mst put:@"com.example.record/1" valueCID:cid1];
    [mst put:@"com.example.record/2" valueCID:cid2];
    
    XCTAssertEqualObjects([mst get:@"com.example.record/1"], cid1);
    XCTAssertEqualObjects([mst get:@"com.example.record/2"], cid2);
    XCTAssertNil([mst get:@"com.example.record/3"]);
}

- (void)testDeletion {
    MST *mst = [[MST alloc] init];
    CID *cid1 = [CID cidFromString:@"bafyreie5cvv4h45feadgeuwhbcutmh6t2ceseocckahdoe6uat64zmz454"];
    
    [mst put:@"com.example.record/1" valueCID:cid1];
    XCTAssertEqualObjects([mst get:@"com.example.record/1"], cid1);
    
    [mst delete:@"com.example.record/1"];
    XCTAssertNil([mst get:@"com.example.record/1"]);
    XCTAssertEqualObjects(mst.rootCID.stringValue, @"bafyreie5737gdxlw5i64vzichcalba3z2v5n6icifvx5xytvske7mr3hpm"); // Empty tree
}

- (void)testListing {
    MST *mst = [[MST alloc] init];
    CID *cid = [CID cidFromString:@"bafyreie5cvv4h45feadgeuwhbcutmh6t2ceseocckahdoe6uat64zmz454"];
    
    // Insert out of order
    [mst put:@"b" valueCID:cid];
    [mst put:@"a" valueCID:cid];
    [mst put:@"c" valueCID:cid];
    
    NSArray<MSTEntry *> *entries = [mst allEntries];
    XCTAssertEqual(entries.count, 3);
    XCTAssertEqualObjects(entries[0].key, @"a");
    XCTAssertEqualObjects(entries[1].key, @"b");
    XCTAssertEqualObjects(entries[2].key, @"c");
}

- (void)testCARGeneration {
    MST *mst = [[MST alloc] init];
    CID *cid = [CID cidFromString:@"bafyreie5cvv4h45feadgeuwhbcutmh6t2ceseocckahdoe6uat64zmz454"];
    [mst put:@"test" valueCID:cid];
    
    NSData *carData = [mst exportCAR];
    XCTAssertNotNil(carData);
    XCTAssertGreaterThan(carData.length, 0);
    // Further CAR validation would require a full CAR parser test util
}

- (void)testDiffFrom {
    CID *cid1 = [CID cidFromString:@"bafyreie5cvv4h45feadgeuwhbcutmh6t2ceseocckahdoe6uat64zmz454"];
    CID *cid2 = [CID cidFromString:@"bafyreifnqrwbk6ffmyaz5qtujqrzf5qmxf7cbxvgzktl4e3gabuxbtatv4"];
    
    // Create old tree with 2 records
    MST *oldTree = [[MST alloc] init];
    [oldTree put:@"com.example/key1" valueCID:cid1];
    [oldTree put:@"com.example/key2" valueCID:cid1];
    
    // Create new tree with:
    // - key1 updated (cid1 -> cid2)
    // - key2 deleted
    // - key3 added
    MST *newTree = [[MST alloc] init];
    [newTree put:@"com.example/key1" valueCID:cid2]; // Update
    [newTree put:@"com.example/key3" valueCID:cid1]; // Add
    
    NSArray<MSTDiffOperation *> *diff = [newTree diffFrom:oldTree];
    XCTAssertEqual(diff.count, 3, "Should have 3 operations: add, update, delete");
    
    // Operations are sorted by key
    MSTDiffOperation *op1 = diff[0];
    XCTAssertEqualObjects(op1.key, @"com.example/key1");
    XCTAssertEqual(op1.type, MSTDiffOperationTypeUpdate);
    XCTAssertEqualObjects(op1.previousCID.stringValue, cid1.stringValue);
    XCTAssertEqualObjects(op1.currentCID.stringValue, cid2.stringValue);
    
    MSTDiffOperation *op2 = diff[1];
    XCTAssertEqualObjects(op2.key, @"com.example/key2");
    XCTAssertEqual(op2.type, MSTDiffOperationTypeDelete);
    XCTAssertEqualObjects(op2.previousCID.stringValue, cid1.stringValue);
    XCTAssertNil(op2.currentCID);
    
    MSTDiffOperation *op3 = diff[2];
    XCTAssertEqualObjects(op3.key, @"com.example/key3");
    XCTAssertEqual(op3.type, MSTDiffOperationTypeAdd);
    XCTAssertNil(op3.previousCID);
    XCTAssertEqualObjects(op3.currentCID.stringValue, cid1.stringValue);
}

- (void)testDiffFromEmptyTree {
    CID *cid = [CID cidFromString:@"bafyreie5cvv4h45feadgeuwhbcutmh6t2ceseocckahdoe6uat64zmz454"];
    
    MST *newTree = [[MST alloc] init];
    [newTree put:@"key1" valueCID:cid];
    [newTree put:@"key2" valueCID:cid];
    
    // Diff from nil (empty) tree - all should be additions
    NSArray<MSTDiffOperation *> *diff = [newTree diffFrom:nil];
    XCTAssertEqual(diff.count, 2);
    XCTAssertEqual(diff[0].type, MSTDiffOperationTypeAdd);
    XCTAssertEqual(diff[1].type, MSTDiffOperationTypeAdd);
}

- (void)testGetProofNodesForKey {
    CID *cid = [CID cidFromString:@"bafyreie5cvv4h45feadgeuwhbcutmh6t2ceseocckahdoe6uat64zmz454"];
    
    MST *mst = [[MST alloc] init];
    [mst put:@"a" valueCID:cid];
    [mst put:@"b" valueCID:cid];
    [mst put:@"c" valueCID:cid];
    
    NSArray<MSTNode *> *proofNodes = [mst getProofNodesForKey:@"b"];
    XCTAssertNotNil(proofNodes, "Should return proof nodes for existing key");
    XCTAssertGreaterThan(proofNodes.count, 0, "Should have at least one node in proof path");
    
    // Verify that the proof path starts from root
    MSTNode *rootProof = proofNodes[0];
    XCTAssertNotNil(rootProof, "First node should be root");
}

- (void)testGetProofNodesForMissingKey {
    CID *cid = [CID cidFromString:@"bafyreie5cvv4h45feadgeuwhbcutmh6t2ceseocckahdoe6uat64zmz454"];
    
    MST *mst = [[MST alloc] init];
    [mst put:@"a" valueCID:cid];
    
    NSArray<MSTNode *> *proofNodes = [mst getProofNodesForKey:@"nonexistent"];
    XCTAssertNil(proofNodes, "Should return nil for non-existent key");
}

- (void)testFullEntries {
    CID *cid = [CID cidFromString:@"bafyreie5cvv4h45feadgeuwhbcutmh6t2ceseocckahdoe6uat64zmz454"];
    
    MST *mst = [[MST alloc] init];
    [mst put:@"a" valueCID:cid];
    [mst put:@"b" valueCID:cid];
    
    // Get proof nodes to access internal nodes
    NSArray<MSTNode *> *proofNodes = [mst getProofNodesForKey:@"a"];
    XCTAssertNotNil(proofNodes);
    
    // Test fullEntries on root node
    MSTNode *root = proofNodes[0];
    NSArray<MSTEntry *> *entries = [root fullEntries];
    XCTAssertGreaterThan(entries.count, 0, "Root should have entries");
}

@end
