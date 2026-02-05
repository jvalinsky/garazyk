#import "CharacterizationTestBase.h"
#import "Repository/MST.h"
#import "Core/CID.h"

@interface MSTCharacterizationTests : CharacterizationTestBase

@property (nonatomic, strong) MST *subject;

@end

@implementation MSTCharacterizationTests

- (void)setUp {
    [super setUp];
    self.subject = [[MST alloc] init];
}

- (void)tearDown {
    self.subject = nil;
    [super tearDown];
}

/*
 * Characterization Tests for MST
 * Generated automatically. Please implement specific scenarios.
 */

- (void)testCharacterization_initWithRootCID {
    /* Target Method:
     - (instancetype)initWithRootCID:(nullable CID *)rootCID;
    */
    
    MST *tree = [[MST alloc] initWithRootCID:nil];
    XCTAssertNotNil(tree);
    XCTAssertNotNil(tree.emptyTreeHash);
}

- (void)testCharacterization_initWithRootNode {
    /* Target Method:
     - (instancetype)initWithRootNode:(nullable MSTNode *)rootNode;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject initWithRootNode...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_get {
    /* Target Method:
     - (nullable CID *)get:(NSString *)key;
    */
    
    CID *cid = [CID sha256:[@"value" dataUsingEncoding:NSUTF8StringEncoding]];
    [self.subject put:@"key" valueCID:cid];

    CID *result = [self.subject get:@"key"];
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result.stringValue, cid.stringValue);
}

- (void)testCharacterization_get_2 {
    /* Target Method:
     - (nullable CID *)get:(NSString *)key subKey:(nullable NSString *)subKey;
    */
    
    CID *cid = [CID sha256:[@"value" dataUsingEncoding:NSUTF8StringEncoding]];
    [self.subject put:@"app.bsky.feed.post" valueCID:cid subKey:@"rkey1"];

    XCTAssertNil([self.subject get:@"app.bsky.feed.post"]);
    CID *result = [self.subject get:@"app.bsky.feed.post" subKey:@"rkey1"];
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result.stringValue, cid.stringValue);
}

- (void)testCharacterization_put {
    /* Target Method:
     - (void)put:(NSString *)key valueCID:(CID *)valueCID;
    */
    
    CID *cid = [CID sha256:[@"value" dataUsingEncoding:NSUTF8StringEncoding]];
    [self.subject put:@"key" valueCID:cid];
    XCTAssertNotNil([self.subject get:@"key"]);
}

- (void)testCharacterization_put_2 {
    /* Target Method:
     - (void)put:(NSString *)key valueCID:(CID *)valueCID subKey:(nullable NSString *)subKey;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject put...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_delete {
    /* Target Method:
     - (void)delete:(NSString *)key;
    */
    
    CID *cid = [CID sha256:[@"value" dataUsingEncoding:NSUTF8StringEncoding]];
    [self.subject put:@"key" valueCID:cid];
    XCTAssertNotNil([self.subject get:@"key"]);

    [self.subject delete:@"key"];
    XCTAssertNil([self.subject get:@"key"]);
}

- (void)testCharacterization_delete_2 {
    /* Target Method:
     - (void)delete:(NSString *)key subKey:(nullable NSString *)subKey;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject delete...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_allEntries {
    /* Target Method:
     - (NSArray<MSTEntry *> *)allEntries;
    */
    
    [self.subject put:@"a" valueCID:[CID sha256:[@"1" dataUsingEncoding:NSUTF8StringEncoding]]];
    [self.subject put:@"b" valueCID:[CID sha256:[@"2" dataUsingEncoding:NSUTF8StringEncoding]]];

    NSArray<MSTEntry *> *entries = [self.subject allEntries];
    XCTAssertEqual(entries.count, 2);
    NSSet<NSString *> *keys = [NSSet setWithArray:[entries valueForKey:@"key"]];
    XCTAssertTrue([keys containsObject:@"a"]);
    XCTAssertTrue([keys containsObject:@"b"]);
}

- (void)testCharacterization_entriesWithPrefix {
    /* Target Method:
     - (NSArray<MSTEntry *> *)entriesWithPrefix:(NSString *)prefix;
    */
    
    [self.subject put:@"app.bsky.feed.post/1" valueCID:[CID sha256:[@"1" dataUsingEncoding:NSUTF8StringEncoding]]];
    [self.subject put:@"app.bsky.feed.post/2" valueCID:[CID sha256:[@"2" dataUsingEncoding:NSUTF8StringEncoding]]];
    [self.subject put:@"app.bsky.actor.profile/self" valueCID:[CID sha256:[@"3" dataUsingEncoding:NSUTF8StringEncoding]]];

    NSArray<MSTEntry *> *feedEntries = [self.subject entriesWithPrefix:@"app.bsky.feed."];
    XCTAssertEqual(feedEntries.count, 2);
}

- (void)testCharacterization_exportCAR {
    /* Target Method:
     - (NSData *)exportCAR;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject exportCAR...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_serializeToCBOR {
    /* Target Method:
     - (NSData *)serializeToCBOR;
    */
    
    CID *cid = [CID sha256:[@"value" dataUsingEncoding:NSUTF8StringEncoding]];
    [self.subject put:@"key" valueCID:cid];

    NSData *cbor = [self.subject serializeToCBOR];
    XCTAssertNotNil(cbor);
    XCTAssertGreaterThan(cbor.length, 0U);
}

- (void)testCharacterization_Class_deserializeFromCBOR {
    /* Target Method:
     + (nullable instancetype)deserializeFromCBOR:(NSData *)data;
    */
    
    CID *cid = [CID sha256:[@"value" dataUsingEncoding:NSUTF8StringEncoding]];
    [self.subject put:@"key" valueCID:cid];

    NSData *cbor = [self.subject serializeToCBOR];
    MST *roundTrip = [MST deserializeFromCBOR:cbor];
    XCTAssertNotNil(roundTrip);
    XCTAssertEqualObjects([roundTrip get:@"key"].stringValue, cid.stringValue);
}

- (void)testCharacterization_diffFrom {
    /* Target Method:
     - (NSArray<MSTDiffOperation *> *)diffFrom:(nullable MST *)oldTree;
    */
    
    MST *oldTree = [[MST alloc] init];
    CID *oldCID = [CID sha256:[@"old" dataUsingEncoding:NSUTF8StringEncoding]];
    [oldTree put:@"k1" valueCID:oldCID];

    CID *newCID = [CID sha256:[@"new" dataUsingEncoding:NSUTF8StringEncoding]];
    [self.subject put:@"k1" valueCID:newCID];
    [self.subject put:@"k2" valueCID:[CID sha256:[@"add" dataUsingEncoding:NSUTF8StringEncoding]]];

    NSArray<MSTDiffOperation *> *ops = [self.subject diffFrom:oldTree];
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
    NSUInteger depthA = [MST keyDepthString:key];
    NSUInteger depthB = [MST keyDepthBytes:[key dataUsingEncoding:NSUTF8StringEncoding]];
    XCTAssertEqual(depthA, depthB);
}

- (void)testCharacterization_Class_keyDepthBytes {
    /* Target Method:
     + (NSUInteger)keyDepthBytes:(NSData *)keyBytes;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [MST keyDepthBytes...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_Class_keyDepth {
    /* Target Method:
     + (uint32_t)keyDepth:(NSString *)key;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [MST keyDepth...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_getProofNodesForKey {
    /* Target Method:
     - (nullable NSArray<MSTNode *> *)getProofNodesForKey:(NSString *)key;
    */
    
    [self.subject put:@"proofKey" valueCID:[CID sha256:[@"value" dataUsingEncoding:NSUTF8StringEncoding]]];
    NSArray<MSTNode *> *nodes = [self.subject getProofNodesForKey:@"proofKey"];
    XCTAssertNotNil(nodes);
    XCTAssertGreaterThan(nodes.count, 0U);
}

- (void)testCharacterization_serializeNode {
    /* Target Method:
     - (nullable NSData *)serializeNode:(MSTNode *)node;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject serializeNode...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_toJSON {
    /* Target Method:
     - (nullable NSDictionary *)toJSON;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject toJSON...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_getStatistics {
    /* Target Method:
     - (NSDictionary *)getStatistics;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject getStatistics...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_toDOT {
    /* Target Method:
     - (nullable NSString *)toDOT;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject toDOT...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

@end
