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
    
    uint32_t blueDepth = (uint32_t)[MST keyDepthString:@"blue"];
    XCTAssertEqual(blueDepth, 1); // 1 bit -> depth 1
    
    XCTAssertEqual([MST keyDepthString:@"2653ae71"], 0);
    XCTAssertEqual([MST keyDepthString:@"88bfafc7"], 2); // 2 bits -> depth 2
    XCTAssertEqual([MST keyDepthString:@"2a92d355"], 4); // 4 bits -> depth 4
    XCTAssertEqual([MST keyDepthString:@"884976f5"], 6); // 6 bits -> depth 6
    XCTAssertEqual([MST keyDepthString:@"app.bsky.feed.post/454397e440ec"], 4); // 4 bits -> depth 4
    XCTAssertEqual([MST keyDepthString:@"app.bsky.feed.post/9adeb165882c"], 8); // 8 bits -> depth 8
}

- (void)testInteropKnownMaps {
    NSString *cid1str = @"bafyreie5cvv4h45feadgeuwhbcutmh6t2ceseocckahdoe6uat64zmz454";
    CID *cid1 = [CID cidFromString:cid1str];
    
    // Empty map
    MST *emptyMST = [[MST alloc] init];
    XCTAssertEqualObjects(emptyMST.rootCID.stringValue, @"bafyreie5737gdxlw5i64vzichcalba3z2v5n6icifvx5xytvske7mr3hpm");

    // Trivial map
    MST *trivialMST = [[MST alloc] init];
    [trivialMST put:@"com.example.record/3jqfcqzm3fo2j" valueCID:cid1];
    XCTAssertEqualObjects(trivialMST.rootCID.stringValue, @"bafyreibj4lsc3aqnrvphp5xmrnfoorvru4wynt6lwidqbm2623a6tatzdu");
    
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

@end
