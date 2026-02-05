#import "CharacterizationTestBase.h"
#import "Auth/KeyManager.h"

@interface KeyManagerCharacterizationTests : CharacterizationTestBase

@property (nonatomic, strong) KeyManager *subject;

@end

@implementation KeyManagerCharacterizationTests

- (void)setUp {
    [super setUp];
    self.subject = [[KeyManager alloc] initWithDatabase:self.testDatabase serviceIdentifier:@"com.atproto.pds.test.keys"];
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
    
    KeyManager *manager = [[KeyManager alloc] initWithServiceIdentifier:@"com.atproto.pds.test.keys2"];
    XCTAssertNotNil(manager);
    XCTAssertEqualObjects(manager.serviceIdentifier, @"com.atproto.pds.test.keys2");
}

- (void)testCharacterization_initWithDatabase {
    /* Target Method:
     - (nullable instancetype)initWithDatabase:(PDSDatabase *)database serviceIdentifier:(NSString *)serviceIdentifier;
    */
    
    KeyManager *manager = [[KeyManager alloc] initWithDatabase:self.testDatabase serviceIdentifier:@"com.atproto.pds.test.keys3"];
    XCTAssertNotNil(manager);
    XCTAssertEqualObjects(manager.serviceIdentifier, @"com.atproto.pds.test.keys3");
    XCTAssertNotNil(manager.database);
}

- (void)testCharacterization_generateKeyPairWithAlgorithm {
    /* Target Method:
     - (nullable KeyPair *)generateKeyPairWithAlgorithm:(NSString *)algorithm
                                          keySize:(NSUInteger)keySize
                                             error:(NSError **)error;
    */
    
    NSError *error = nil;
    KeyPair *keyPair = [self.subject generateKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error];
    XCTAssertNotNil(keyPair, @"Key generation failed: %@", error);
    XCTAssertNil(error);
    XCTAssertEqualObjects(keyPair.algorithm, @"RS256");
    XCTAssertNotNil(keyPair.keyID);
    XCTAssertEqualObjects(self.subject.currentKeyID, keyPair.keyID);
}

- (void)testCharacterization_getKeyPairWithID {
    /* Target Method:
     - (nullable KeyPair *)getKeyPairWithID:(NSString *)keyID error:(NSError **)error;
    */
    
    NSError *error = nil;
    KeyPair *keyPair = [self.subject generateKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error];
    XCTAssertNotNil(keyPair, @"Key generation failed: %@", error);

    KeyPair *fetched = [self.subject getKeyPairWithID:keyPair.keyID error:&error];
    XCTAssertNotNil(fetched);
    XCTAssertEqualObjects(fetched.keyID, keyPair.keyID);
}

- (void)testCharacterization_getActiveKeyPair {
    /* Target Method:
     - (nullable KeyPair *)getActiveKeyPair:(NSError **)error;
    */
    
    NSError *error = nil;
    KeyPair *keyPair = [self.subject generateKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error];
    XCTAssertNotNil(keyPair, @"Key generation failed: %@", error);

    KeyPair *active = [self.subject getActiveKeyPair:&error];
    XCTAssertNotNil(active);
    XCTAssertNil(error);
    XCTAssertEqualObjects(active.keyID, keyPair.keyID);
}

- (void)testCharacterization_allKeyPairs {
    /* Target Method:
     - (NSArray<KeyPair *> *)allKeyPairs:(NSError **)error;
    */
    
    NSError *error = nil;
    XCTAssertNotNil([self.subject generateKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error]);
    XCTAssertNotNil([self.subject generateKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error]);

    NSArray<KeyPair *> *pairs = [self.subject allKeyPairs:&error];
    XCTAssertNil(error);
    XCTAssertGreaterThanOrEqual(pairs.count, 2U);
}

- (void)testCharacterization_deleteKeyPairWithID {
    /* Target Method:
     - (BOOL)deleteKeyPairWithID:(NSString *)keyID error:(NSError **)error;
    */
    
    NSError *error = nil;
    KeyPair *keyPair = [self.subject generateKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error];
    XCTAssertNotNil(keyPair, @"Key generation failed: %@", error);

    BOOL deleted = [self.subject deleteKeyPairWithID:keyPair.keyID error:&error];
    XCTAssertTrue(deleted);

    NSError *fetchError = nil;
    XCTAssertNil([self.subject getKeyPairWithID:keyPair.keyID error:&fetchError]);
    XCTAssertNotNil(fetchError);
}

- (void)testCharacterization_setKeyPairActive {
    /* Target Method:
     - (BOOL)setKeyPairActive:(NSString *)keyID error:(NSError **)error;
    */
    
    NSError *error = nil;
    KeyPair *first = [self.subject generateKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error];
    KeyPair *second = [self.subject generateKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error];
    XCTAssertNotNil(first);
    XCTAssertNotNil(second);

    BOOL activated = [self.subject setKeyPairActive:second.keyID error:&error];
    XCTAssertTrue(activated);
    XCTAssertNil(error);

    KeyPair *active = [self.subject getActiveKeyPair:&error];
    XCTAssertNotNil(active);
    XCTAssertEqualObjects(active.keyID, second.keyID);
}

- (void)testCharacterization_signData {
    /* Target Method:
     - (nullable NSData *)signData:(NSData *)data
                     withKeyID:(NSString *)keyID
                         error:(NSError **)error;
    */
    
    NSError *error = nil;
    KeyPair *keyPair = [self.subject generateKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error];
    XCTAssertNotNil(keyPair, @"Key generation failed: %@", error);

    NSData *data = [@"hello" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *signature = [self.subject signData:data withKeyID:keyPair.keyID error:&error];
    XCTAssertNotNil(signature, @"Signature failed: %@", error);
    XCTAssertNil(error);

    BOOL verified = [self.subject verifySignature:signature forData:data withKey:keyPair.publicKey error:&error];
    XCTAssertTrue(verified);
    XCTAssertNil(error);
}

- (void)testCharacterization_signPayload {
    /* Target Method:
     - (nullable NSDictionary *)signPayload:(NSDictionary *)payload
                              withKeyID:(NSString *)keyID
                                  error:(NSError **)error;
    */
    
    NSError *error = nil;
    KeyPair *keyPair = [self.subject generateKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error];
    XCTAssertNotNil(keyPair, @"Key generation failed: %@", error);

    NSDictionary *payload = @{@"iss": @"test.issuer", @"sub": @"did:plc:test"};
    NSDictionary *result = [self.subject signPayload:payload withKeyID:keyPair.keyID error:&error];
    XCTAssertNotNil(result);
    XCTAssertNil(error);
    XCTAssertTrue([result[@"token"] isKindOfClass:[NSString class]]);
}

- (void)testCharacterization_signString {
    /* Target Method:
     - (nullable NSString *)signString:(NSString *)string
                         withKeyID:(NSString *)keyID
                             error:(NSError **)error;
    */
    
    NSError *error = nil;
    KeyPair *keyPair = [self.subject generateKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error];
    XCTAssertNotNil(keyPair, @"Key generation failed: %@", error);

    NSString *sig = [self.subject signString:@"hello" withKeyID:keyPair.keyID error:&error];
    XCTAssertNotNil(sig);
    XCTAssertNil(error);
}

- (void)testCharacterization_verifySignature {
    /* Target Method:
     - (BOOL)verifySignature:(NSData *)signature
               forData:(NSData *)data
               withKey:(SecKeyRef)publicKey
                  error:(NSError **)error;
    */
    
    NSError *error = nil;
    KeyPair *keyPair = [self.subject generateKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error];
    XCTAssertNotNil(keyPair, @"Key generation failed: %@", error);

    NSData *data = [@"hello" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *signature = [self.subject signData:data withKeyID:keyPair.keyID error:&error];
    XCTAssertNotNil(signature, @"Signature failed: %@", error);

    BOOL verified = [self.subject verifySignature:signature forData:data withKey:keyPair.publicKey error:&error];
    XCTAssertTrue(verified);
    XCTAssertNil(error);
}

- (void)testCharacterization_toJWKS {
    /* Target Method:
     - (NSDictionary *)toJWKS;
    */
    
    NSError *error = nil;
    XCTAssertNotNil([self.subject generateKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error]);
    NSDictionary *jwks = [self.subject toJWKS];
    XCTAssertTrue([jwks isKindOfClass:[NSDictionary class]]);
    XCTAssertGreaterThan(jwks.count, 0U);
}

- (void)testCharacterization_toJWKSArray {
    /* Target Method:
     - (NSArray<NSDictionary *> *)toJWKSArray;
    */
    
    NSError *error = nil;
    XCTAssertNotNil([self.subject generateKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error]);
    NSArray<NSDictionary *> *jwks = [self.subject toJWKSArray];
    XCTAssertTrue([jwks isKindOfClass:[NSArray class]]);
    XCTAssertGreaterThan(jwks.count, 0U);
}

@end
