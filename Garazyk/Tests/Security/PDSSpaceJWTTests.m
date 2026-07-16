// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>

#import <CommonCrypto/CommonDigest.h>

#import "Auth/PDSActorKeyManagerProtocol.h"
#import "Auth/Secp256k1.h"
#import "Security/Space/PDSSpaceJWT.h"

@interface PDSSpaceJWTTestKeyManager : NSObject <PDSActorKeyManager>
@property(nonatomic, strong) Secp256k1KeyPair *keyPair;
@end

@implementation PDSSpaceJWTTestKeyManager
- (BOOL)generateSigningKeyWithError:(NSError **)error { self.keyPair = [Secp256k1KeyPair generateKeyPair:error]; return self.keyPair != nil; }
- (BOOL)importSigningKey:(NSData *)privateKey error:(NSError **)error { self.keyPair = [Secp256k1KeyPair keyPairWithPrivateKey:privateKey error:error]; return self.keyPair != nil; }
- (NSData *)signData:(NSData *)data error:(NSError **)error {
  unsigned char hash[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
  return [self.keyPair signHash:[NSData dataWithBytes:hash length:sizeof(hash)] error:error];
}
- (NSData *)publicSigningKeyWithError:(NSError **)error { return self.keyPair.compressedPublicKey; }
- (NSString *)didKeyStringWithError:(NSError **)error { return self.keyPair.didKeyString; }
- (NSData *)exportPrivateKeyWithError:(NSError **)error { return self.keyPair.privateKey; }
@end

@interface PDSSpaceJWTTests : XCTestCase
@property(nonatomic, strong) PDSSpaceJWTTestKeyManager *keyManager;
@property(nonatomic, strong) NSDate *now;
@end

@implementation PDSSpaceJWTTests

- (void)setUp {
  [super setUp];
  self.keyManager = [[PDSSpaceJWTTestKeyManager alloc] init];
  XCTAssertTrue([self.keyManager generateSigningKeyWithError:nil]);
  self.now = [NSDate dateWithTimeIntervalSince1970:1700000000];
}

- (void)testDelegationHasExactShapeAndVerifies {
  NSError *error = nil;
  NSString *token = [PDSSpaceJWT mintDelegationWithIssuer:@"did:example:user"
                                                  audience:@"did:example:authority#atproto_space_host"
                                                     space:[self space]
                                           actorKeyManager:self.keyManager
                                                       now:self.now
                                                expiration:nil
                                                     error:&error];
  XCTAssertNotNil(token);
  NSDictionary *payload = [PDSSpaceJWT verifyDelegation:token
                                               publicKey:self.keyManager.keyPair.compressedPublicKey
                                         expectedIssuer:@"did:example:user"
                                       expectedAudience:@"did:example:authority#atproto_space_host"
                                        expectedSubject:[self space]
                                                    now:self.now
                                                  error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(payload[@"iss"], @"did:example:user");
  XCTAssertNotNil(payload[@"jti"]);
}

- (void)testDelegationCannotBeUsedAsCredentialOrForOtherAudience {
  NSError *error = nil;
  NSString *token = [PDSSpaceJWT mintDelegationWithIssuer:@"did:example:user"
                                                  audience:@"did:example:authority#atproto_space_host"
                                                     space:[self space]
                                           actorKeyManager:self.keyManager now:self.now expiration:nil error:&error];
  XCTAssertNil([PDSSpaceJWT verifyCredential:token publicKey:self.keyManager.keyPair.compressedPublicKey
                                expectedIssuer:@"did:example:authority" expectedSubject:[self space]
                                        keyID:@"#atproto" now:self.now error:&error]);
  XCTAssertEqual(error.code, PDSSpaceJWTErrorMalformed);
  error = nil;
  XCTAssertNil([PDSSpaceJWT verifyDelegation:token publicKey:self.keyManager.keyPair.compressedPublicKey
                                         expectedIssuer:@"did:example:user" expectedAudience:@"did:example:other#atproto_space_host"
                                          expectedSubject:[self space] now:self.now error:&error]);
  XCTAssertEqual(error.code, PDSSpaceJWTErrorAudience);
}

- (void)testCredentialUsesDocumentedFallbackKeyAndEnforcesLifetime {
  NSError *error = nil;
  NSString *token = [PDSSpaceJWT mintCredentialWithAuthority:@"did:example:authority"
                                                        space:[self space]
                                                        keyID:@"#atproto"
                                              actorKeyManager:self.keyManager
                                                          now:self.now
                                                   expiration:nil
                                                        error:&error];
  NSDictionary *payload = [PDSSpaceJWT verifyCredential:token publicKey:self.keyManager.keyPair.compressedPublicKey
                                                   expectedIssuer:@"did:example:authority" expectedSubject:[self space]
                                                           keyID:@"#atproto" now:self.now error:&error];
  XCTAssertNotNil(payload);
  XCTAssertEqual([payload[@"exp"] integerValue] - [payload[@"iat"] integerValue], 7200);
  XCTAssertNil([PDSSpaceJWT mintCredentialWithAuthority:@"did:example:authority" space:[self space] keyID:@"#atproto"
                                         actorKeyManager:self.keyManager now:self.now
                                          expiration:[self.now dateByAddingTimeInterval:7201] error:&error]);
  XCTAssertEqual(error.code, PDSSpaceJWTErrorLifetime);
}

- (void)testCredentialSupportsPublishedDedicatedSpaceKey {
  NSError *error = nil;
  NSString *token = [PDSSpaceJWT mintCredentialWithAuthority:@"did:example:authority"
                                                        space:[self space]
                                                        keyID:@"#atproto_space"
                                              actorKeyManager:self.keyManager
                                                          now:self.now
                                                   expiration:nil
                                                        error:&error];
  XCTAssertNotNil(token);
  NSDictionary *payload = [PDSSpaceJWT verifyCredential:token
                                               publicKey:self.keyManager.keyPair.compressedPublicKey
                                         expectedIssuer:@"did:example:authority"
                                        expectedSubject:[self space]
                                                   keyID:@"#atproto_space"
                                                     now:self.now
                                                   error:&error];
  XCTAssertNotNil(payload);
  XCTAssertNil([PDSSpaceJWT verifyCredential:token
                                    publicKey:self.keyManager.keyPair.compressedPublicKey
                              expectedIssuer:@"did:example:authority"
                             expectedSubject:[self space]
                                        keyID:@"#atproto"
                                          now:self.now
                                        error:&error]);
  XCTAssertEqual(error.code, PDSSpaceJWTErrorMalformed);
}

- (NSString *)space {
  return @"at://did:example:authority/space/com.example.group/default";
}

@end
