#import "CharacterizationTestBase.h"
#import "Auth/KeyManager.h"

@interface KeyManagerCharacterizationTests : CharacterizationTestBase

@property (nonatomic, strong) KeyManager *subject;

@end

@implementation KeyManagerCharacterizationTests

- (void)setUp {
    [super setUp];
    // TODO: Initialize self.subject
    // self.subject = [[KeyManager alloc] init];
}

- (void)tearDown {
    self.subject = nil;
    [super tearDown];
}

/*
 * Characterization Tests for KeyManager
 * Generated automatically. Please implement specific scenarios.
 */

- (void)testCharacterization_initWithServiceIdentifier {
    /* Target Method:
     - (nullable instancetype)initWithServiceIdentifier:(NSString *)serviceIdentifier;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject initWithServiceIdentifier...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_initWithDatabase {
    /* Target Method:
     - (nullable instancetype)initWithDatabase:(PDSDatabase *)database serviceIdentifier:(NSString *)serviceIdentifier;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject initWithDatabase...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_generateKeyPairWithAlgorithm {
    /* Target Method:
     - (nullable KeyPair *)generateKeyPairWithAlgorithm:(NSString *)algorithm
                                          keySize:(NSUInteger)keySize
                                             error:(NSError **)error;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject generateKeyPairWithAlgorithm...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_getKeyPairWithID {
    /* Target Method:
     - (nullable KeyPair *)getKeyPairWithID:(NSString *)keyID error:(NSError **)error;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject getKeyPairWithID...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_getActiveKeyPair {
    /* Target Method:
     - (nullable KeyPair *)getActiveKeyPair:(NSError **)error;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject getActiveKeyPair...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_allKeyPairs {
    /* Target Method:
     - (NSArray<KeyPair *> *)allKeyPairs:(NSError **)error;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject allKeyPairs...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_deleteKeyPairWithID {
    /* Target Method:
     - (BOOL)deleteKeyPairWithID:(NSString *)keyID error:(NSError **)error;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject deleteKeyPairWithID...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_setKeyPairActive {
    /* Target Method:
     - (BOOL)setKeyPairActive:(NSString *)keyID error:(NSError **)error;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject setKeyPairActive...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_signData {
    /* Target Method:
     - (nullable NSData *)signData:(NSData *)data
                     withKeyID:(NSString *)keyID
                         error:(NSError **)error;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject signData...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_signPayload {
    /* Target Method:
     - (nullable NSDictionary *)signPayload:(NSDictionary *)payload
                              withKeyID:(NSString *)keyID
                                  error:(NSError **)error;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject signPayload...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_signString {
    /* Target Method:
     - (nullable NSString *)signString:(NSString *)string
                         withKeyID:(NSString *)keyID
                             error:(NSError **)error;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject signString...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_verifySignature {
    /* Target Method:
     - (BOOL)verifySignature:(NSData *)signature
               forData:(NSData *)data
               withKey:(SecKeyRef)publicKey
                  error:(NSError **)error;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject verifySignature...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_toJWKS {
    /* Target Method:
     - (NSDictionary *)toJWKS;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject toJWKS...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_toJWKSArray {
    /* Target Method:
     - (NSArray<NSDictionary *> *)toJWKSArray;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject toJWKSArray...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

@end
