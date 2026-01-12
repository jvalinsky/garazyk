#import <XCTest/XCTest.h>
#import "Auth/KeyRotationManager.h"
#import "Auth/KeyManager.h"
#import "Auth/JWT.h"

@interface KeyRotationTests : XCTestCase

@property (nonatomic, strong) KeyManager *keyManager;
@property (nonatomic, strong) KeyRotationManager *keyRotationManager;

@end

@implementation KeyRotationTests

- (void)setUp {
    [super setUp];
#if !defined(__APPLE__)
    SecTestResetKeychain();
#endif
    
    self.keyManager = [[KeyManager alloc] init];
    self.keyRotationManager = [[KeyRotationManager alloc] initWithKeyStore:self.keyManager];
}

- (void)tearDown {
    self.keyManager = nil;
    self.keyRotationManager = nil;
#if !defined(__APPLE__)
    SecTestResetKeychain();
#endif
    [super tearDown];
}

- (void)testKeyRotationManagerInitialization {
    XCTAssertNotNil(self.keyRotationManager);
    XCTAssertEqualObjects(self.keyManager, [self.keyRotationManager valueForKey:@"keyManager"]);
}

- (void)testCurrentSigningKey {
    // Initially, no keys should exist
    SecKeyRef key = [self.keyRotationManager currentSigningKey];
    XCTAssertTrue(key == NULL);
    
    // Generate a key
    NSError *error = nil;
    KeyPair *keyPair = [self.keyManager generateKeyPairWithAlgorithm:@"ES256" keySize:256 error:&error];
    XCTAssertNotNil(keyPair);
    XCTAssertNil(error);
    
    // Now current signing key should be available
    key = [self.keyRotationManager currentSigningKey];
    XCTAssertTrue(key != NULL);
    // if (key) CFRelease(key); // Not needed with ARC managed ShimSecKey
}

- (void)testAllValidPublicKeys {
    // Initially empty
    NSArray *keys = [self.keyRotationManager allValidPublicKeys];
    XCTAssertEqual(keys.count, 0);
    
    // Generate a key
    NSError *error = nil;
    KeyPair *keyPair = [self.keyManager generateKeyPairWithAlgorithm:@"ES256" keySize:256 error:&error];
    XCTAssertNotNil(keyPair);
    
    // Should have one valid key
    keys = [self.keyRotationManager allValidPublicKeys];
    XCTAssertEqual(keys.count, 1);
}

- (void)testRotateKeys {
    NSError *error = nil;
    BOOL success = [self.keyRotationManager rotateKeys];
    XCTAssertTrue(success);
    XCTAssertNil(error);
    
    // Should have generated a new key
    NSArray *keys = [self.keyRotationManager allValidPublicKeys];
    XCTAssertEqual(keys.count, 1);
    
    // Rotate again
    success = [self.keyRotationManager rotateKeys];
    XCTAssertTrue(success);
    
    // Should still have only one active key (the latest)
    keys = [self.keyRotationManager allValidPublicKeys];
    XCTAssertEqual(keys.count, 1);
}

- (void)testJWTSigningWithKeyRotation {
    // Generate initial key
    NSError *error = nil;
    [self.keyManager generateKeyPairWithAlgorithm:@"ES256" keySize:256 error:&error];
    XCTAssertNil(error);
    
    // Create JWT minter with key rotation manager
    JWTMinter *minter = [[JWTMinter alloc] init];
    minter.keyRotationManager = self.keyRotationManager;
    minter.issuer = @"test.issuer";
    
    // Mint a token
    JWT *token = [minter mintAccessTokenForDID:@"did:plc:test" handle:@"test.handle" scopes:@[@"read"] error:&error];
    XCTAssertNotNil(token);
    XCTAssertNil(error);
    
    // Create verifier with key rotation manager
    JWTVerifier *verifier = [[JWTVerifier alloc] init];
    verifier.keyRotationManager = self.keyRotationManager;
    verifier.expectedIssuer = @"test.issuer";
    
    // Verify the token
    BOOL valid = [verifier verifyJWT:token error:&error];
    XCTAssertTrue(valid);
    XCTAssertNil(error);
}

- (void)testJWTVerificationAfterKeyRotation {
    // Generate initial key
    NSError *error = nil;
    [self.keyManager generateKeyPairWithAlgorithm:@"ES256" keySize:256 error:&error];
    XCTAssertNil(error);
    
    // Create JWT minter with key rotation manager
    JWTMinter *minter = [[JWTMinter alloc] init];
    minter.keyRotationManager = self.keyRotationManager;
    minter.issuer = @"test.issuer";
    
    // Mint a token with old key
    JWT *token = [minter mintAccessTokenForDID:@"did:plc:test" handle:@"test.handle" scopes:@[@"read"] error:&error];
    XCTAssertNotNil(token);
    XCTAssertNil(error);
    
    // Rotate keys
    BOOL rotated = [self.keyRotationManager rotateKeys];
    XCTAssertTrue(rotated);
    
    // Create verifier with key rotation manager
    JWTVerifier *verifier = [[JWTVerifier alloc] init];
    verifier.keyRotationManager = self.keyRotationManager;
    verifier.expectedIssuer = @"test.issuer";
    
    // Token should still be valid (old key should still be valid during transition)
    BOOL valid = [verifier verifyJWT:token error:&error];
    XCTAssertTrue(valid, @"Token should be valid after key rotation during transition period");
    XCTAssertNil(error);
}

@end