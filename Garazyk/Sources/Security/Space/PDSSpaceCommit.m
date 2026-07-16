// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Security/Space/PDSSpaceCommit.h"

#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonHMAC.h>
#import <Security/SecRandom.h>

#import "Auth/PDSActorKeyManagerProtocol.h"
#import "Auth/Secp256k1.h"
#import "Security/PDSSecurityCompare.h"
#import "Security/Space/PDSSpaceLtHash.h"

NSString *const PDSSpaceCommitErrorDomain = @"com.garazyk.space.commit";

static NSString *const PDSSpaceCommitDomain = @"atproto-space-v1";

@interface PDSSpaceCommit ()
@property(nonatomic, readwrite) NSInteger version;
@property(nonatomic, readwrite, copy) NSData *commitHash;
@property(nonatomic, readwrite, copy) NSData *mac;
@property(nonatomic, readwrite, copy) NSData *ikm;
@property(nonatomic, readwrite, copy) NSData *signature;
@property(nonatomic, readwrite, copy) NSString *rev;
@end

@implementation PDSSpaceCommit

+ (instancetype)commitForSetHash:(PDSSpaceLtHash *)setHash
                            space:(NSString *)space
                           author:(NSString *)author
                              rev:(NSString *)rev
              actorKeyManager:(id<PDSActorKeyManager>)actorKeyManager
                           error:(NSError **)error {
  if (!setHash || !actorKeyManager) {
    if (error) *error = [self error:@"Set hash and actor signing key are required"];
    return nil;
  }
  NSMutableData *ikm = [NSMutableData dataWithLength:32];
  if (SecRandomCopyBytes(kSecRandomDefault, ikm.length, ikm.mutableBytes) != errSecSuccess) {
    if (error) *error = [self error:@"Unable to generate commit nonce"];
    return nil;
  }
  NSData *context = [self contextForSpace:space author:author rev:rev ikm:ikm error:error];
  if (!context) return nil;
  NSData *hash = setHash.digest;
  NSData *mac = [self macForIKM:ikm context:context hash:hash];
  NSData *signature = [actorKeyManager signData:context error:error];
  if (signature.length != 64) {
    if (signature && error) *error = [self error:@"Actor key returned an invalid commit signature"];
    return nil;
  }
  PDSSpaceCommit *commit = [[self alloc] init];
  commit.version = 1;
  commit.commitHash = hash;
  commit.mac = mac;
  commit.ikm = ikm;
  commit.signature = signature;
  commit.rev = rev;
  return commit;
}

+ (nullable instancetype)commitFromDictionary:(NSDictionary *)dict error:(NSError **)error {
  if (![dict isKindOfClass:[NSDictionary class]]) {
    if (error) *error = [self error:@"Commit is not a dictionary"];
    return nil;
  }
  id ver = dict[@"ver"];
  id hash = dict[@"hash"];
  id mac = dict[@"mac"];
  id ikm = dict[@"ikm"];
  id sig = dict[@"sig"];
  id rev = dict[@"rev"];
  if (![ver isKindOfClass:[NSNumber class]] || [ver integerValue] != 1 ||
      ![hash isKindOfClass:[NSData class]] || ((NSData *)hash).length != 32 ||
      ![mac isKindOfClass:[NSData class]] || ((NSData *)mac).length != 32 ||
      ![ikm isKindOfClass:[NSData class]] || ((NSData *)ikm).length != 32 ||
      ![sig isKindOfClass:[NSData class]] || ((NSData *)sig).length != 64 ||
      ![rev isKindOfClass:[NSString class]] || ((NSString *)rev).length == 0) {
    if (error) *error = [self error:@"Commit dictionary has missing or malformed fields"];
    return nil;
  }
  PDSSpaceCommit *commit = [[self alloc] init];
  commit.version = [ver integerValue];
  commit.commitHash = hash;
  commit.mac = mac;
  commit.ikm = ikm;
  commit.signature = sig;
  commit.rev = rev;
  return commit;
}

- (BOOL)verifyIntegrityForSpace:(NSString *)space author:(NSString *)author error:(NSError **)error {
  if (self.version != 1 || self.commitHash.length != 32 || self.mac.length != 32 || self.ikm.length != 32 ||
      self.signature.length != 64) {
    if (error) *error = [[self class] error:@"Malformed signed space commit"];
    return NO;
  }
  NSData *context = [[self class] contextForSpace:space author:author rev:self.rev ikm:self.ikm error:error];
  if (!context) return NO;
  NSData *expected = [[self class] macForIKM:self.ikm context:context hash:self.commitHash];
  if (![PDSSecurityCompare constantTimeEqualData:self.mac data:expected]) {
    if (error) *error = [[self class] error:@"Space commit MAC does not match its context and hash"];
    return NO;
  }
  return YES;
}

- (BOOL)verifySignatureForSpace:(NSString *)space author:(NSString *)author publicKey:(NSData *)publicKey error:(NSError **)error {
  if (![self verifyIntegrityForSpace:space author:author error:error]) return NO;
  NSData *context = [[self class] contextForSpace:space author:author rev:self.rev ikm:self.ikm error:error];
  if (!context) return NO;
  unsigned char digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(context.bytes, (CC_LONG)context.length, digest);
  if (![[Secp256k1 shared] verifySignature:self.signature
                                   forHash:[NSData dataWithBytes:digest length:sizeof(digest)]
                             withPublicKey:publicKey
                                    error:nil]) {
    if (error) *error = [[self class] error:@"Space commit signature does not verify"];
    return NO;
  }
  return YES;
}

+ (NSData *)contextForSpace:(NSString *)space author:(NSString *)author rev:(NSString *)rev ikm:(NSData *)ikm error:(NSError **)error {
  if (space.length == 0 || author.length == 0 || rev.length == 0 || ikm.length != 32) {
    if (error) *error = [self error:@"Commit context requires space, author, revision, and a 32-byte nonce"];
    return nil;
  }
  NSMutableData *context = [[PDSSpaceCommitDomain dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
  for (NSData *field in @[[space dataUsingEncoding:NSUTF8StringEncoding],
                         [author dataUsingEncoding:NSUTF8StringEncoding],
                         [rev dataUsingEncoding:NSUTF8StringEncoding], ikm]) {
    if (!field || field.length > UINT16_MAX) {
      if (error) *error = [self error:@"Commit context field exceeds uint16 length"];
      return nil;
    }
    uint16_t length = CFSwapInt16HostToBig((uint16_t)field.length);
    [context appendBytes:&length length:sizeof(length)];
    [context appendData:field];
  }
  return context;
}

+ (NSData *)macForIKM:(NSData *)ikm context:(NSData *)context hash:(NSData *)hash {
  // @atproto/crypto's hkdfSha256() uses the IKM as a 32-byte HKDF PRK and
  // expands it with `ctx` as info. For a 32-byte result this is HMAC(PRK,
  // info || 0x01), followed by HMAC(derivedKey, commitHash).
  NSMutableData *expandInput = [context mutableCopy];
  const uint8_t blockIndex = 1;
  [expandInput appendBytes:&blockIndex length:1];
  unsigned char derivedKey[CC_SHA256_DIGEST_LENGTH];
  CCHmac(kCCHmacAlgSHA256, ikm.bytes, ikm.length,
         expandInput.bytes, expandInput.length, derivedKey);
  unsigned char output[CC_SHA256_DIGEST_LENGTH];
  CCHmac(kCCHmacAlgSHA256, derivedKey, sizeof(derivedKey), hash.bytes, hash.length, output);
  return [NSData dataWithBytes:output length:sizeof(output)];
}

+ (NSError *)error:(NSString *)message {
  return [NSError errorWithDomain:PDSSpaceCommitErrorDomain
                             code:1
                         userInfo:@{NSLocalizedDescriptionKey : message}];
}

@end
