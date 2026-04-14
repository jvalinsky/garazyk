#import "CharacterizationTestBase.h"
#import "Auth/PDSAppleKeyManager.h"
#import "Auth/TestKeyFixtures.h"

@interface KeyManagerCharacterizationTests : CharacterizationTestBase

@property (nonatomic, strong) PDSAppleKeyManager *subject;

@end

@implementation KeyManagerCharacterizationTests

- (nullable PDSAppleKeyPair *)seedDeterministicKeyPairWithError:(NSError **)error {
    NSError *keyError = nil;
    SecKeyRef privateKey = PDSTestCreateFixedP256PrivateKey(&keyError);
    if (privateKey == NULL) {
        if (error) {
            *error = keyError;
        }
        return nil;
    }

    SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
    if (publicKey == NULL) {
        CFRelease(privateKey);
        if (error) {
            *error = [NSError errorWithDomain:@"KeyManagerCharacterizationTests"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to derive public key for deterministic fixture"}];
        }
        return nil;
    }

    NSString *keyID = [[NSUUID UUID] UUIDString];
    PDSAppleKeyPair *keyPair = [PDSAppleKeyPair keyPairFromPrivateKey:privateKey
                                                             publicKey:publicKey
                                                                 keyID:keyID
                                                              algorithm:@"ES256"];
    CFRelease(privateKey);
    CFRelease(publicKey);
    if (!keyPair) {
        if (error) {
            *error = [NSError errorWithDomain:@"KeyManagerCharacterizationTests"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to construct deterministic key pair"}];
        }
        return nil;
    }

    keyPair.isActive = YES;
    self.subject.signingAlgorithm = kSecKeyAlgorithmECDSASignatureMessageX962SHA256;

    dispatch_queue_t accessQueue = [self.subject valueForKey:@"accessQueue"];
    NSMutableDictionary *keyPairs = [self.subject valueForKey:@"keyPairs"];
    if (!accessQueue || ![keyPairs isKindOfClass:[NSMutableDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"KeyManagerCharacterizationTests"
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unable to access manager internals for deterministic seeding"}];
        }
        return nil;
    }

    dispatch_sync(accessQueue, ^{
        for (PDSAppleKeyPair *existing in keyPairs.allValues) {
            existing.isActive = NO;
        }
        keyPairs[keyID] = keyPair;
        self.subject.currentKeyID = keyID;
    });

    return keyPair;
}

- (nullable PDSAppleKeyPair *)createUsableKeyPairWithError:(NSError **)error {
    self.subject.signingAlgorithm = kSecKeyAlgorithmECDSASignatureMessageX962SHA256;

    NSError *generationError = nil;
    PDSAppleKeyPair *generated = [self.subject generatePDSAppleKeyPairWithAlgorithm:@"ES256"
                                                                             keySize:256
                                                                               error:&generationError];
    if (generated) {
        return generated;
    }

    return [self seedDeterministicKeyPairWithError:error];
}

- (void)setUp {
    [super setUp];
    self.subject = [[PDSAppleKeyManager alloc] initWithDatabase:self.testDatabase serviceIdentifier:@"com.atproto.pds.test.keys"];
}

- (void)tearDown {
    self.subject = nil;
    [super tearDown];
}

/*
 * Characterization Tests for PDSAppleKeyManager
 * Generated automatically. Please implement specific scenarios.
 */

- (void)testCharacterization_initWithServiceIdentifier {
    /* Target Method:
     - (nullable instancetype)initWithServiceIdentifier:(NSString *)serviceIdentifier;
    */
    
    PDSAppleKeyManager *manager = [[PDSAppleKeyManager alloc] initWithServiceIdentifier:@"com.atproto.pds.test.keys2"];
    XCTAssertNotNil(manager);
    XCTAssertEqualObjects(manager.serviceIdentifier, @"com.atproto.pds.test.keys2");
}

- (void)testCharacterization_initWithDatabase {
    /* Target Method:
     - (nullable instancetype)initWithDatabase:(PDSDatabase *)database serviceIdentifier:(NSString *)serviceIdentifier;
    */
    
    PDSAppleKeyManager *manager = [[PDSAppleKeyManager alloc] initWithDatabase:self.testDatabase serviceIdentifier:@"com.atproto.pds.test.keys3"];
    XCTAssertNotNil(manager);
    XCTAssertEqualObjects(manager.serviceIdentifier, @"com.atproto.pds.test.keys3");
    XCTAssertNotNil(manager.database);
}

- (void)testCharacterization_generatePDSAppleKeyPairWithAlgorithm {
    /* Target Method:
     - (nullable PDSAppleKeyPair *)generatePDSAppleKeyPairWithAlgorithm:(NSString *)algorithm
                                          keySize:(NSUInteger)keySize
                                             error:(NSError **)error;
    */
    
    NSError *error = nil;
    PDSAppleKeyPair *keyPair = [self createUsableKeyPairWithError:&error];
    XCTAssertNotNil(keyPair, @"Key generation failed: %@", error);
    XCTAssertNil(error);
    XCTAssertEqualObjects(keyPair.algorithm, @"ES256");
    XCTAssertNotNil(keyPair.keyID);
    XCTAssertEqualObjects(self.subject.currentKeyID, keyPair.keyID);
}

- (void)testCharacterization_getPDSAppleKeyPairWithID {
    /* Target Method:
     - (nullable PDSAppleKeyPair *)getPDSAppleKeyPairWithID:(NSString *)keyID error:(NSError **)error;
    */
    
    NSError *error = nil;
    PDSAppleKeyPair *keyPair = [self createUsableKeyPairWithError:&error];
    XCTAssertNotNil(keyPair, @"Key generation failed: %@", error);

    PDSAppleKeyPair *fetched = [self.subject getPDSAppleKeyPairWithID:keyPair.keyID error:&error];
    XCTAssertNotNil(fetched);
    XCTAssertEqualObjects(fetched.keyID, keyPair.keyID);
}

- (void)testCharacterization_getActivePDSAppleKeyPair {
    /* Target Method:
     - (nullable PDSAppleKeyPair *)getActivePDSAppleKeyPair:(NSError **)error;
    */
    
    NSError *error = nil;
    PDSAppleKeyPair *keyPair = [self createUsableKeyPairWithError:&error];
    XCTAssertNotNil(keyPair, @"Key generation failed: %@", error);

    PDSAppleKeyPair *active = [self.subject getActivePDSAppleKeyPair:&error];
    XCTAssertNotNil(active);
    XCTAssertNil(error);
    XCTAssertEqualObjects(active.keyID, keyPair.keyID);
}

- (void)testCharacterization_allPDSAppleKeyPairs {
    /* Target Method:
     - (NSArray<PDSAppleKeyPair *> *)allPDSAppleKeyPairs:(NSError **)error;
    */
    
    NSError *error = nil;
    XCTAssertNotNil([self createUsableKeyPairWithError:&error]);
    XCTAssertNotNil([self createUsableKeyPairWithError:&error]);

    NSArray<PDSAppleKeyPair *> *pairs = [self.subject allPDSAppleKeyPairs:&error];
    XCTAssertNil(error);
    XCTAssertGreaterThanOrEqual(pairs.count, 2U);
}

- (void)testCharacterization_deletePDSAppleKeyPairWithID {
    /* Target Method:
     - (BOOL)deletePDSAppleKeyPairWithID:(NSString *)keyID error:(NSError **)error;
    */
    
    NSError *error = nil;
    PDSAppleKeyPair *keyPair = [self createUsableKeyPairWithError:&error];
    XCTAssertNotNil(keyPair, @"Key generation failed: %@", error);

    BOOL deleted = [self.subject deletePDSAppleKeyPairWithID:keyPair.keyID error:&error];
    XCTAssertTrue(deleted);

    NSError *fetchError = nil;
    XCTAssertNil([self.subject getPDSAppleKeyPairWithID:keyPair.keyID error:&fetchError]);
    XCTAssertNotNil(fetchError);
}

- (void)testCharacterization_setPDSAppleKeyPairActive {
    /* Target Method:
     - (BOOL)setPDSAppleKeyPairActive:(NSString *)keyID error:(NSError **)error;
    */
    
    NSError *error = nil;
    PDSAppleKeyPair *first = [self createUsableKeyPairWithError:&error];
    PDSAppleKeyPair *second = [self createUsableKeyPairWithError:&error];
    XCTAssertNotNil(first);
    XCTAssertNotNil(second);

    BOOL activated = [self.subject setPDSAppleKeyPairActive:second.keyID error:&error];
    XCTAssertTrue(activated);
    XCTAssertNil(error);

    PDSAppleKeyPair *active = [self.subject getActivePDSAppleKeyPair:&error];
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
    PDSAppleKeyPair *keyPair = [self createUsableKeyPairWithError:&error];
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
    PDSAppleKeyPair *keyPair = [self createUsableKeyPairWithError:&error];
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
    PDSAppleKeyPair *keyPair = [self createUsableKeyPairWithError:&error];
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
    PDSAppleKeyPair *keyPair = [self createUsableKeyPairWithError:&error];
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
    XCTAssertNotNil([self createUsableKeyPairWithError:&error]);
    NSDictionary *jwks = [self.subject toJWKS];
    XCTAssertTrue([jwks isKindOfClass:[NSDictionary class]]);
    XCTAssertGreaterThan(jwks.count, 0U);
}

- (void)testCharacterization_toJWKSArray {
    /* Target Method:
     - (NSArray<NSDictionary *> *)toJWKSArray;
    */
    
    NSError *error = nil;
    XCTAssertNotNil([self createUsableKeyPairWithError:&error]);
    NSArray<NSDictionary *> *jwks = [self.subject toJWKSArray];
    XCTAssertTrue([jwks isKindOfClass:[NSArray class]]);
    XCTAssertGreaterThan(jwks.count, 0U);
}

@end
