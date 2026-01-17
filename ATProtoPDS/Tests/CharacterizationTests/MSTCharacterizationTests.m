#import "CharacterizationTestBase.h"
#import "Repository/MST.h"

@interface MSTCharacterizationTests : CharacterizationTestBase

@property (nonatomic, strong) MST *subject;

@end

@implementation MSTCharacterizationTests

- (void)setUp {
    [super setUp];
    // TODO: Initialize self.subject
    // self.subject = [[MST alloc] init];
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
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject initWithRootCID...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
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
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject get...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_get_2 {
    /* Target Method:
     - (nullable CID *)get:(NSString *)key subKey:(nullable NSString *)subKey;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject get...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_put {
    /* Target Method:
     - (void)put:(NSString *)key valueCID:(CID *)valueCID;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject put...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
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
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject delete...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
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
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject allEntries...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_entriesWithPrefix {
    /* Target Method:
     - (NSArray<MSTEntry *> *)entriesWithPrefix:(NSString *)prefix;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject entriesWithPrefix...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
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
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject serializeToCBOR...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_Class_deserializeFromCBOR {
    /* Target Method:
     + (nullable instancetype)deserializeFromCBOR:(NSData *)data;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [MST deserializeFromCBOR...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_diffFrom {
    /* Target Method:
     - (NSArray<MSTDiffOperation *> *)diffFrom:(nullable MST *)oldTree;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject diffFrom...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_Class_keyDepthString {
    /* Target Method:
     + (NSUInteger)keyDepthString:(NSString *)key;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [MST keyDepthString...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
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
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject getProofNodesForKey...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
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
