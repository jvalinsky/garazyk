#import "CharacterizationTestBase.h"
#import "Auth/PDSAppleKeyManager.h"

@interface KeyManagerCharacterizationTests : CharacterizationTestBase

@property (nonatomic, strong) PDSAppleKeyManager *subject;

@end

@implementation KeyManagerCharacterizationTests

- (void)requireSecurityKeyGeneration {
    static dispatch_once_t onceToken;
    static BOOL isAvailable = NO;
    static NSError *availabilityError = nil;
    dispatch_once(&onceToken, ^{
        NSDictionary *attributes = @{
            (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeRSA,
            (__bridge id)kSecAttrKeySizeInBits: @1024
        };
        CFErrorRef error = NULL;
        SecKeyRef privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, &error);
        if (privateKey != NULL) {
            isAvailable = YES;
            CFRelease(privateKey);
        } else {
            availabilityError = CFBridgingRelease(error);
        }
    });

    if (!isAvailable) {
        XCTSkip(@"Skipping key generation/signing tests: Security key generation unavailable (%@)", availabilityError);
    }
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
    
    [self requireSecurityKeyGeneration];
    NSError *error = nil;
    PDSAppleKeyPair *keyPair = [self.subject generatePDSAppleKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error];
    XCTAssertNotNil(keyPair, @"Key generation failed: %@", error);
    XCTAssertNil(error);
    XCTAssertEqualObjects(keyPair.algorithm, @"RS256");
    XCTAssertNotNil(keyPair.keyID);
    XCTAssertEqualObjects(self.subject.currentKeyID, keyPair.keyID);
}

- (void)testCharacterization_getPDSAppleKeyPairWithID {
    /* Target Method:
     - (nullable PDSAppleKeyPair *)getPDSAppleKeyPairWithID:(NSString *)keyID error:(NSError **)error;
    */
    
    [self requireSecurityKeyGeneration];
    NSError *error = nil;
    PDSAppleKeyPair *keyPair = [self.subject generatePDSAppleKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error];
    XCTAssertNotNil(keyPair, @"Key generation failed: %@", error);

    PDSAppleKeyPair *fetched = [self.subject getPDSAppleKeyPairWithID:keyPair.keyID error:&error];
    XCTAssertNotNil(fetched);
    XCTAssertEqualObjects(fetched.keyID, keyPair.keyID);
}

- (void)testCharacterization_getActivePDSAppleKeyPair {
    /* Target Method:
     - (nullable PDSAppleKeyPair *)getActivePDSAppleKeyPair:(NSError **)error;
    */
    
    [self requireSecurityKeyGeneration];
    NSError *error = nil;
    PDSAppleKeyPair *keyPair = [self.subject generatePDSAppleKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error];
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
    
    [self requireSecurityKeyGeneration];
    NSError *error = nil;
    XCTAssertNotNil([self.subject generatePDSAppleKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error]);
    XCTAssertNotNil([self.subject generatePDSAppleKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error]);

    NSArray<PDSAppleKeyPair *> *pairs = [self.subject allPDSAppleKeyPairs:&error];
    XCTAssertNil(error);
    XCTAssertGreaterThanOrEqual(pairs.count, 2U);
}

- (void)testCharacterization_deletePDSAppleKeyPairWithID {
    /* Target Method:
     - (BOOL)deletePDSAppleKeyPairWithID:(NSString *)keyID error:(NSError **)error;
    */
    
    [self requireSecurityKeyGeneration];
    NSError *error = nil;
    PDSAppleKeyPair *keyPair = [self.subject generatePDSAppleKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error];
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
    
    [self requireSecurityKeyGeneration];
    NSError *error = nil;
    PDSAppleKeyPair *first = [self.subject generatePDSAppleKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error];
    PDSAppleKeyPair *second = [self.subject generatePDSAppleKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error];
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
    
    [self requireSecurityKeyGeneration];
    NSError *error = nil;
    PDSAppleKeyPair *keyPair = [self.subject generatePDSAppleKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error];
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
    
    [self requireSecurityKeyGeneration];
    NSError *error = nil;
    PDSAppleKeyPair *keyPair = [self.subject generatePDSAppleKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error];
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
    
    [self requireSecurityKeyGeneration];
    NSError *error = nil;
    PDSAppleKeyPair *keyPair = [self.subject generatePDSAppleKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error];
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
    
    [self requireSecurityKeyGeneration];
    NSError *error = nil;
    PDSAppleKeyPair *keyPair = [self.subject generatePDSAppleKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error];
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
    
    [self requireSecurityKeyGeneration];
    NSError *error = nil;
    XCTAssertNotNil([self.subject generatePDSAppleKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error]);
    NSDictionary *jwks = [self.subject toJWKS];
    XCTAssertTrue([jwks isKindOfClass:[NSDictionary class]]);
    XCTAssertGreaterThan(jwks.count, 0U);
}

- (void)testCharacterization_toJWKSArray {
    /* Target Method:
     - (NSArray<NSDictionary *> *)toJWKSArray;
    */
    
    [self requireSecurityKeyGeneration];
    NSError *error = nil;
    XCTAssertNotNil([self.subject generatePDSAppleKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error]);
    NSArray<NSDictionary *> *jwks = [self.subject toJWKSArray];
    XCTAssertTrue([jwks isKindOfClass:[NSArray class]]);
    XCTAssertGreaterThan(jwks.count, 0U);
}

@end
