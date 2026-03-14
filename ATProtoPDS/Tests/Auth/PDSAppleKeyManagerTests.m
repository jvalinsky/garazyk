// Tests for PDSAppleKeyManager: Apple Security.framework-backed JWT signing key management.
// All tests are Apple-platform-only (uses Security.framework / SecKey APIs).

#ifdef __APPLE__
#import <XCTest/XCTest.h>
#import "Auth/PDSAppleKeyManager.h"
#import "Auth/CryptoUtils.h"
#import "Database/PDSDatabase.h"

@interface PDSAppleKeyManagerTests : XCTestCase
@property (nonatomic, strong) PDSAppleKeyManager *manager;
@property (nonatomic, strong) NSString *tempDir;
@property (nonatomic, strong) PDSDatabase *database;
@end

@implementation PDSAppleKeyManagerTests

- (void)setUp {
    [super setUp];
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"PDSAppleKeyManagerTests-%@", [[NSUUID UUID] UUIDString]]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir
                                withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *dbPath = [self.tempDir stringByAppendingPathComponent:@"keys.db"];
    self.database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    NSError *dbError = nil;
    [self.database openWithError:&dbError];

    NSString *serviceID = [NSString stringWithFormat:@"com.test.keymgr.%@", [[NSUUID UUID] UUIDString]];
    self.manager = [[PDSAppleKeyManager alloc] initWithDatabase:self.database
                                             serviceIdentifier:serviceID];
}

- (void)tearDown {
    [self.database close];
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    [super tearDown];
}

#pragma mark - Key Generation

- (void)testGenerateKeyPairCreatesEntry {
    NSError *error = nil;
    PDSAppleKeyPair *pair = [self.manager generatePDSAppleKeyPairWithAlgorithm:@"ES256"
                                                                        keySize:256
                                                                          error:&error];
    XCTAssertNotNil(pair, @"generatePDSAppleKeyPairWithAlgorithm:keySize:error: must succeed: %@", error);
    XCTAssertNil(error);
    XCTAssertNotNil(pair.keyID);
    XCTAssertEqualObjects(pair.algorithm, @"ES256");
    XCTAssertNotNil(pair.privateKey);
    XCTAssertNotNil(pair.publicKey);
}

- (void)testCurrentKeyIDSetAfterGeneration {
    NSError *error = nil;
    PDSAppleKeyPair *pair = [self.manager generatePDSAppleKeyPairWithAlgorithm:@"ES256"
                                                                        keySize:256
                                                                          error:&error];
    XCTAssertNotNil(pair);
    XCTAssertNotNil(self.manager.currentKeyID,
                    @"currentKeyID must be set after generating first active key");
}

- (void)testGetKeyPairByID {
    NSError *error = nil;
    PDSAppleKeyPair *generated = [self.manager generatePDSAppleKeyPairWithAlgorithm:@"ES256"
                                                                             keySize:256
                                                                               error:&error];
    XCTAssertNotNil(generated);
    PDSAppleKeyPair *fetched = [self.manager getPDSAppleKeyPairWithID:generated.keyID error:&error];
    XCTAssertNotNil(fetched, @"getPDSAppleKeyPairWithID: must return the generated key");
    XCTAssertEqualObjects(fetched.keyID, generated.keyID);
}

- (void)testGetNonExistentKeyPairReturnsNil {
    NSError *error = nil;
    PDSAppleKeyPair *result = [self.manager getPDSAppleKeyPairWithID:@"non-existent-key-id"
                                                               error:&error];
    XCTAssertNil(result);
}

#pragma mark - Signing

- (void)testSignPayloadProducesNonEmptySignature {
    NSError *error = nil;
    [self.manager generatePDSAppleKeyPairWithAlgorithm:@"ES256" keySize:256 error:&error];
    XCTAssertNotNil(self.manager.currentKeyID);

    NSString *headerB64  = [CryptoUtils base64URLEncode:
                             [@"{\"alg\":\"ES256\",\"typ\":\"JWT\"}" dataUsingEncoding:NSUTF8StringEncoding]];
    NSString *payloadB64 = [CryptoUtils base64URLEncode:
                             [@"{\"sub\":\"did:plc:abc\"}" dataUsingEncoding:NSUTF8StringEncoding]];
    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerB64, payloadB64];

    NSData *signature = [self.manager signPayload:[signingInput dataUsingEncoding:NSUTF8StringEncoding]
                                        withKeyID:self.manager.currentKeyID
                                            error:&error];
    XCTAssertNotNil(signature, @"signPayload:withKeyID:error: must produce a signature: %@", error);
    XCTAssertGreaterThan(signature.length, (NSUInteger)0);
}

#pragma mark - Public Key JWK

- (void)testPublicKeyJWKContainsRequiredECFields {
    NSError *error = nil;
    [self.manager generatePDSAppleKeyPairWithAlgorithm:@"ES256" keySize:256 error:&error];
    XCTAssertNotNil(self.manager.currentKeyID);

    NSDictionary *jwk = [self.manager publicKeyJWK];
    XCTAssertNotNil(jwk, @"publicKeyJWK must not be nil after key generation");
    XCTAssertEqualObjects(jwk[@"kty"], @"EC", @"JWK kty must be 'EC'");
    XCTAssertNotNil(jwk[@"crv"], @"JWK must contain 'crv'");
    XCTAssertNotNil(jwk[@"x"],   @"JWK must contain 'x'");
    XCTAssertNotNil(jwk[@"y"],   @"JWK must contain 'y'");
}

#pragma mark - Key Thumbprint

- (void)testPublicKeyThumbprintIsNonEmpty {
    NSError *error = nil;
    [self.manager generatePDSAppleKeyPairWithAlgorithm:@"ES256" keySize:256 error:&error];
    NSString *thumbprint = [self.manager publicKeyThumbprint];
    XCTAssertNotNil(thumbprint);
    XCTAssertGreaterThan(thumbprint.length, (NSUInteger)0);
}

#pragma mark - Persistence

- (void)testLoadKeysFromDatabaseRestoresKeyCount {
    NSError *error = nil;
    PDSAppleKeyPair *pair = [self.manager generatePDSAppleKeyPairWithAlgorithm:@"ES256"
                                                                        keySize:256
                                                                          error:&error];
    XCTAssertNotNil(pair);

    // Create a fresh manager on the same database
    PDSAppleKeyManager *second = [[PDSAppleKeyManager alloc] initWithDatabase:self.database
                                                            serviceIdentifier:self.manager.serviceIdentifier];
    NSArray *pairs = [second allPDSAppleKeyPairs:&error];
    XCTAssertGreaterThanOrEqual(pairs.count, (NSUInteger)1,
                                @"Reloaded manager must have at least one key pair");
}

@end
#endif // __APPLE__
