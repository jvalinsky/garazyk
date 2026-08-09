// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "CharacterizationTestBase.h"
#import "Repository/MST.h"
#import "Core/CID.h"

@interface MSTCharacterizationTests : CharacterizationTestBase

@property (nonatomic, strong) ATProtoMST *subject;

@end

@implementation MSTCharacterizationTests

- (void)setUp {
    [super setUp];
    self.subject = [[ATProtoMST alloc] init];
}

- (void)tearDown {
    self.subject = nil;
    [super tearDown];
}

/*
 * Characterization Tests for ATProtoMST
 * Generated automatically. Please implement specific scenarios.
 */

- (void)testCharacterization_initWithRootCIDMatchesEmptyTreeHash {
    /* Target Method:
     - (instancetype)initWithRootCID:(nullable ATProtoCID *)rootCID;
    */
    
    ATProtoMST *tree = [[ATProtoMST alloc] initWithRootCID:nil];
    XCTAssertNotNil(tree);
    XCTAssertNotNil(tree.emptyTreeHash);
    XCTAssertTrue([tree isKindOfClass:[ATProtoMST class]]);
}

- (void)testCharacterization_initWithRootNodeMatchesRootCID {
    /* Target Method:
     - (instancetype)initWithRootNode:(nullable ATProtoMSTNode *)rootNode;
    */

    ATProtoMSTNode *rootNode = [ATProtoMSTNode leafNodeWithEntries:@[]];
    ATProtoMST *tree = [[ATProtoMST alloc] initWithRootNode:rootNode];
    XCTAssertNotNil(tree);
    XCTAssertNotNil(tree.rootCID);
    XCTAssertTrue([tree isKindOfClass:[ATProtoMST class]]);
}

- (void)testCharacterization_getMatchesValueCID {
    /* Target Method:
     - (nullable ATProtoCID *)get:(NSString *)key;
    */
    
    ATProtoCID *cid = [ATProtoCID sha256:[@"value" dataUsingEncoding:NSUTF8StringEncoding]];
    [self.subject put:@"key" valueCID:cid];

    ATProtoCID *result = [self.subject get:@"key"];
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result.stringValue, cid.stringValue);
}

- (void)testCharacterization_get_2MatchesValueCID {
    /* Target Method:
     - (nullable ATProtoCID *)get:(NSString *)key subKey:(nullable NSString *)subKey;
    */
    
    ATProtoCID *cid = [ATProtoCID sha256:[@"value" dataUsingEncoding:NSUTF8StringEncoding]];
    [self.subject put:@"app.bsky.feed.post" valueCID:cid subKey:@"rkey1"];

    XCTAssertNil([self.subject get:@"app.bsky.feed.post"]);
    ATProtoCID *result = [self.subject get:@"app.bsky.feed.post" subKey:@"rkey1"];
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result.stringValue, cid.stringValue);
}

- (void)testCharacterization_putMatchesValueCID {
    /* Target Method:
     - (void)put:(NSString *)key valueCID:(ATProtoCID *)valueCID;
    */
    
    ATProtoCID *cid = [ATProtoCID sha256:[@"value" dataUsingEncoding:NSUTF8StringEncoding]];
    [self.subject put:@"key" valueCID:cid];
    XCTAssertNotNil([self.subject get:@"key"]);
    XCTAssertEqualObjects([self.subject get:@"key"].stringValue, cid.stringValue);
}

- (void)testCharacterization_put_2MatchesValueCID {
    /* Target Method:
     - (void)put:(NSString *)key valueCID:(ATProtoCID *)valueCID subKey:(nullable NSString *)subKey;
    */

    ATProtoCID *cid = [ATProtoCID sha256:[@"value" dataUsingEncoding:NSUTF8StringEncoding]];
    [self.subject put:@"app.bsky.feed.post" valueCID:cid subKey:@"rkey1"];

    XCTAssertNotNil([self.subject get:@"app.bsky.feed.post" subKey:@"rkey1"]);
    XCTAssertEqualObjects([self.subject get:@"app.bsky.feed.post" subKey:@"rkey1"].stringValue, cid.stringValue);
}

- (void)testCharacterization_deleteGetIsNil {
    /* Target Method:
     - (void)delete:(NSString *)key;
    */
    
    ATProtoCID *cid = [ATProtoCID sha256:[@"value" dataUsingEncoding:NSUTF8StringEncoding]];
    [self.subject put:@"key" valueCID:cid];
    XCTAssertNotNil([self.subject get:@"key"]);

    [self.subject delete:@"key"];
    XCTAssertNil([self.subject get:@"key"]);
}

- (void)testCharacterization_delete_2GetIsNil {
    /* Target Method:
     - (void)delete:(NSString *)key subKey:(nullable NSString *)subKey;
    */

    ATProtoCID *cid = [ATProtoCID sha256:[@"value" dataUsingEncoding:NSUTF8StringEncoding]];
    [self.subject put:@"app.bsky.feed.post" valueCID:cid subKey:@"rkey1"];
    XCTAssertNotNil([self.subject get:@"app.bsky.feed.post" subKey:@"rkey1"]);

    [self.subject delete:@"app.bsky.feed.post" subKey:@"rkey1"];
    XCTAssertNil([self.subject get:@"app.bsky.feed.post" subKey:@"rkey1"]);
}

- (void)testCharacterization_allEntries {
    /* Target Method:
     - (NSArray<ATProtoMSTEntry *> *)allEntries;
    */
    
    [self.subject put:@"a" valueCID:[ATProtoCID sha256:[@"1" dataUsingEncoding:NSUTF8StringEncoding]]];
    [self.subject put:@"b" valueCID:[ATProtoCID sha256:[@"2" dataUsingEncoding:NSUTF8StringEncoding]]];

    NSArray<ATProtoMSTEntry *> *entries = [self.subject allEntries];
    XCTAssertEqual(entries.count, 2);
    NSSet<NSString *> *keys = [NSSet setWithArray:[entries valueForKey:@"key"]];
    XCTAssertTrue([keys containsObject:@"a"]);
    XCTAssertTrue([keys containsObject:@"b"]);
}

- (void)testCharacterization_entriesWithPrefixMatchesEntries {
    /* Target Method:
     - (NSArray<ATProtoMSTEntry *> *)entriesWithPrefix:(NSString *)prefix;
    */
    
    [self.subject put:@"app.bsky.feed.post/1" valueCID:[ATProtoCID sha256:[@"1" dataUsingEncoding:NSUTF8StringEncoding]]];
    [self.subject put:@"app.bsky.feed.post/2" valueCID:[ATProtoCID sha256:[@"2" dataUsingEncoding:NSUTF8StringEncoding]]];
    [self.subject put:@"app.bsky.actor.profile/self" valueCID:[ATProtoCID sha256:[@"3" dataUsingEncoding:NSUTF8StringEncoding]]];

    NSArray<ATProtoMSTEntry *> *feedEntries = [self.subject entriesWithPrefix:@"app.bsky.feed."];
    XCTAssertEqual(feedEntries.count, 2);
}

- (void)testCharacterization_exportCARReturnsData {
    /* Target Method:
     - (NSData *)exportCAR;
    */

    [self.subject put:@"a" valueCID:[ATProtoCID sha256:[@"1" dataUsingEncoding:NSUTF8StringEncoding]]];
    [self.subject put:@"b" valueCID:[ATProtoCID sha256:[@"2" dataUsingEncoding:NSUTF8StringEncoding]]];

    NSData *carData = [self.subject exportCAR];
    XCTAssertNotNil(carData);
    XCTAssertGreaterThan(carData.length, 0U);
}

- (void)testCharacterization_serializeToCBORReturnsData {
    /* Target Method:
     - (NSData *)serializeToCBOR;
    */
    
    ATProtoCID *cid = [ATProtoCID sha256:[@"value" dataUsingEncoding:NSUTF8StringEncoding]];
    [self.subject put:@"key" valueCID:cid];

    NSData *cbor = [self.subject serializeToCBOR];
    XCTAssertNotNil(cbor);
    XCTAssertGreaterThan(cbor.length, 0U);
}

- (void)testRoundtripEqualObjectStringValue {
    /* Target Method:
     + (nullable instancetype)deserializeFromCBOR:(NSData *)data;
    */
    
    ATProtoCID *cid = [ATProtoCID sha256:[@"value" dataUsingEncoding:NSUTF8StringEncoding]];
    [self.subject put:@"key" valueCID:cid];

    NSData *cbor = [self.subject serializeToCBOR];
    ATProtoMST *roundTrip = [ATProtoMST deserializeFromCBOR:cbor];
    XCTAssertNotNil(roundTrip);
    XCTAssertEqualObjects([roundTrip get:@"key"].stringValue, cid.stringValue);
}

- (void)testCharacterization_diffFrom {
    /* Target Method:
     - (NSArray<ATProtoMSTDiffOperation *> *)diffFrom:(nullable ATProtoMST *)oldTree;
    */
    
    ATProtoMST *oldTree = [[ATProtoMST alloc] init];
    ATProtoCID *oldCID = [ATProtoCID sha256:[@"old" dataUsingEncoding:NSUTF8StringEncoding]];
    [oldTree put:@"k1" valueCID:oldCID];

    ATProtoCID *newCID = [ATProtoCID sha256:[@"new" dataUsingEncoding:NSUTF8StringEncoding]];
    [self.subject put:@"k1" valueCID:newCID];
    [self.subject put:@"k2" valueCID:[ATProtoCID sha256:[@"add" dataUsingEncoding:NSUTF8StringEncoding]]];

    NSArray<ATProtoMSTDiffOperation *> *ops = [self.subject diffFrom:oldTree];
    XCTAssertEqual(ops.count, 2);
    XCTAssertEqualObjects(ops[0].key, @"k1");
    XCTAssertEqual(ops[0].type, MSTDiffOperationTypeUpdate);
    XCTAssertEqualObjects(ops[1].key, @"k2");
    XCTAssertEqual(ops[1].type, MSTDiffOperationTypeAdd);
}

- (void)testCharacterization_Class_keyDepthString {
    /* Target Method:
     + (NSUInteger)keyDepthString:(NSString *)key;
    */
    
    NSString *key = @"app.bsky.feed.post/1";
    NSUInteger depthA = [ATProtoMST keyDepthString:key];
    NSUInteger depthB = [ATProtoMST keyDepthBytes:[key dataUsingEncoding:NSUTF8StringEncoding]];
    XCTAssertEqual(depthA, depthB);
}

- (void)testCharacterization_Class_keyDepthBytes {
    /* Target Method:
     + (NSUInteger)keyDepthBytes:(NSData *)keyBytes;
    */

    NSData *keyBytes = [@"key" dataUsingEncoding:NSUTF8StringEncoding];
    NSUInteger depthA = [ATProtoMST keyDepthBytes:keyBytes];
    NSUInteger depthB = [ATProtoMST keyDepthString:@"key"];
    XCTAssertEqual(depthA, depthB);
}

- (void)testCharacterization_Class_keyDepth {
    /* Target Method:
     + (uint32_t)keyDepth:(NSString *)key;
    */

    NSString *key = @"key";
    uint32_t depthA = [ATProtoMST keyDepth:key];
    NSUInteger depthB = [ATProtoMST keyDepthString:key];
    XCTAssertEqual((NSUInteger)depthA, depthB);
}

- (void)testCharacterization_getProofNodesForKey {
    /* Target Method:
     - (nullable NSArray<ATProtoMSTNode *> *)getProofNodesForKey:(NSString *)key;
    */
    
    [self.subject put:@"proofKey" valueCID:[ATProtoCID sha256:[@"value" dataUsingEncoding:NSUTF8StringEncoding]]];
    NSArray<ATProtoMSTNode *> *nodes = [self.subject getProofNodesForKey:@"proofKey"];
    XCTAssertNotNil(nodes);
    XCTAssertGreaterThan(nodes.count, 0U);
}

- (void)testCharacterization_serializeNode {
    /* Target Method:
     - (nullable NSData *)serializeNode:(ATProtoMSTNode *)node;
    */

    [self.subject put:@"proofKey" valueCID:[ATProtoCID sha256:[@"value" dataUsingEncoding:NSUTF8StringEncoding]]];
    NSArray<ATProtoMSTNode *> *nodes = [self.subject getProofNodesForKey:@"proofKey"];
    XCTAssertNotNil(nodes);
    XCTAssertGreaterThan(nodes.count, 0U);

    NSData *nodeData = [self.subject serializeNode:nodes.firstObject];
    XCTAssertNotNil(nodeData);
    XCTAssertGreaterThan(nodeData.length, 0U);
}

- (void)testCharacterization_toJSONMatchesDictionaryElements {
    /* Target Method:
     - (nullable NSDictionary *)toJSON;
    */

    [self.subject put:@"a" valueCID:[ATProtoCID sha256:[@"1" dataUsingEncoding:NSUTF8StringEncoding]]];
    NSDictionary *json = [self.subject toJSON];
    XCTAssertNotNil(json);
    XCTAssertTrue([json isKindOfClass:[NSDictionary class]]);
    XCTAssertNotNil(json[@"rootCID"]);
    XCTAssertNotNil(json[@"nodeCount"]);
}

- (void)testCharacterization_getStatisticsMatchesDictionaryElements {
    /* Target Method:
     - (NSDictionary *)getStatistics;
    */

    [self.subject put:@"a" valueCID:[ATProtoCID sha256:[@"1" dataUsingEncoding:NSUTF8StringEncoding]]];
    NSDictionary *stats = [self.subject getStatistics];
    XCTAssertNotNil(stats);
    XCTAssertTrue([stats isKindOfClass:[NSDictionary class]]);
    XCTAssertNotNil(stats[@"nodeCount"]);
    XCTAssertNotNil(stats[@"entryCount"]);
}

- (void)testCharacterization_toDOTReturnsString {
    /* Target Method:
     - (nullable NSString *)toDOT;
    */

    [self.subject put:@"a" valueCID:[ATProtoCID sha256:[@"1" dataUsingEncoding:NSUTF8StringEncoding]]];
    NSString *dot = [self.subject toDOT];
    XCTAssertNotNil(dot);
    XCTAssertTrue([dot hasPrefix:@"digraph MST"]);
}

@end
