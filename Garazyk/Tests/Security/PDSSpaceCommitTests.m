// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>

#import <CommonCrypto/CommonDigest.h>

#import "Auth/PDSActorKeyManagerProtocol.h"
#import "Auth/Secp256k1.h"
#import "Security/Space/PDSSpaceCommit.h"
#import "Security/Space/PDSSpaceLtHash.h"

@interface PDSSpaceCommitTestKeyManager : NSObject <PDSActorKeyManager>
@property(nonatomic, strong) Secp256k1KeyPair *keyPair;
@end

@implementation PDSSpaceCommitTestKeyManager
- (BOOL)generateSigningKeyWithError:(NSError **)error { self.keyPair = [Secp256k1KeyPair generateKeyPair:error]; return self.keyPair != nil; }
- (BOOL)importSigningKey:(NSData *)privateKey error:(NSError **)error { self.keyPair = [Secp256k1KeyPair keyPairWithPrivateKey:privateKey error:error]; return self.keyPair != nil; }
- (NSData *)signData:(NSData *)data error:(NSError **)error { unsigned char hash[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(data.bytes, (CC_LONG)data.length, hash); return [self.keyPair signHash:[NSData dataWithBytes:hash length:sizeof(hash)] error:error]; }
- (NSData *)publicSigningKeyWithError:(NSError **)error { return self.keyPair.compressedPublicKey; }
- (NSString *)didKeyStringWithError:(NSError **)error { return self.keyPair.didKeyString; }
- (NSData *)exportPrivateKeyWithError:(NSError **)error { return self.keyPair.privateKey; }
@end

@interface PDSSpaceCommitTests : XCTestCase
@end

@implementation PDSSpaceCommitTests

- (void)testSignedCommitBindsSpaceAuthorAndRevision {
  PDSSpaceCommitTestKeyManager *manager = [[PDSSpaceCommitTestKeyManager alloc] init];
  XCTAssertTrue([manager generateSigningKeyWithError:nil]);
  PDSSpaceLtHash *hash = [[PDSSpaceLtHash alloc] init];
  [hash addElement:@"com.example.note/one/bafyrecord"];
  NSError *error = nil;
  PDSSpaceCommit *commit = [PDSSpaceCommit commitForSetHash:hash space:[self space]
                                                      author:@"did:example:alice" rev:@"3jzfcijpj2z2a"
                                             actorKeyManager:manager error:&error];
  XCTAssertNotNil(commit);
  XCTAssertEqual(commit.version, 1);
  XCTAssertTrue([commit verifyIntegrityForSpace:[self space] author:@"did:example:alice" error:&error]);
  XCTAssertTrue([commit verifySignatureForSpace:[self space] author:@"did:example:alice"
                                       publicKey:manager.keyPair.compressedPublicKey error:&error]);
  XCTAssertFalse([commit verifyIntegrityForSpace:[self space] author:@"did:example:bob" error:&error]);
  XCTAssertFalse([commit verifySignatureForSpace:@"at://did:example:other/space/com.example.group/default"
                                          author:@"did:example:alice" publicKey:manager.keyPair.compressedPublicKey error:&error]);
}

- (void)testContextHasPinnedBigEndianLengthEncoding {
  NSData *context = [PDSSpaceCommit contextForSpace:@"s" author:@"a" rev:@"r"
                                                  ikm:[NSMutableData dataWithLength:32] error:nil];
  const uint8_t *bytes = context.bytes;
  NSData *domain = [@"atproto-space-v1" dataUsingEncoding:NSUTF8StringEncoding];
  XCTAssertEqual(context.length, domain.length + 2 + 1 + 2 + 1 + 2 + 1 + 2 + 32);
  XCTAssertEqual(bytes[domain.length], 0);
  XCTAssertEqual(bytes[domain.length + 1], 1);
  XCTAssertEqual(bytes[domain.length + 2], 's');
}

- (NSString *)space {
  return @"at://did:example:authority/space/com.example.group/default";
}

@end
