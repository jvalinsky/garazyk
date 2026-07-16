// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Security/Space/PDSSpaceJWT.h"

#import <CommonCrypto/CommonDigest.h>

#import "Auth/JWT.h"
#import "Auth/PDSActorKeyManagerProtocol.h"
#import "Auth/Secp256k1.h"

NSString *const PDSSpaceJWTErrorDomain = @"com.garazyk.space.jwt";
NSString *const PDSSpaceDelegationJWTType = @"atproto-space-delegation+jwt";
NSString *const PDSSpaceCredentialJWTType = @"atproto-space-credential+jwt";

static const NSTimeInterval PDSSpaceDelegationLifetime = 60.0;
static const NSTimeInterval PDSSpaceCredentialLifetime = 7200.0;
static const NSTimeInterval PDSSpaceClockSkew = 30.0;

@implementation PDSSpaceJWT

+ (NSString *)mintDelegationWithIssuer:(NSString *)issuer
                              audience:(NSString *)audience
                                 space:(NSString *)space
                       actorKeyManager:(id<PDSActorKeyManager>)actorKeyManager
                                   now:(NSDate *)now
                            expiration:(NSDate *)expiration
                                 error:(NSError **)error {
  NSDate *issuedAt = now ?: [NSDate date];
  NSDate *expiresAt = expiration ?: [issuedAt dateByAddingTimeInterval:PDSSpaceDelegationLifetime];
  if (![self validRequiredStrings:@[issuer, audience, space]] ||
      [expiresAt timeIntervalSinceDate:issuedAt] <= 0 ||
      [expiresAt timeIntervalSinceDate:issuedAt] > PDSSpaceDelegationLifetime) {
    if (error) *error = [self error:PDSSpaceJWTErrorLifetime message:@"Delegation lifetime must be positive and at most 60 seconds"];
    return nil;
  }
  NSDictionary *payload = [self payloadWithIssuer:issuer audience:audience space:space
                                                now:issuedAt expiration:expiresAt];
  return [self signPayload:payload type:PDSSpaceDelegationJWTType keyID:@"#atproto"
             actorKeyManager:actorKeyManager error:error];
}

+ (NSString *)mintCredentialWithAuthority:(NSString *)authority
                                   space:(NSString *)space
                                   keyID:(NSString *)keyID
                         actorKeyManager:(id<PDSActorKeyManager>)actorKeyManager
                                     now:(NSDate *)now
                              expiration:(NSDate *)expiration
                                   error:(NSError **)error {
  NSDate *issuedAt = now ?: [NSDate date];
  NSDate *expiresAt = expiration ?: [issuedAt dateByAddingTimeInterval:PDSSpaceCredentialLifetime];
  if (![self validRequiredStrings:@[authority, space, keyID]] ||
      !([keyID isEqualToString:@"#atproto_space"] || [keyID isEqualToString:@"#atproto"]) ||
      [expiresAt timeIntervalSinceDate:issuedAt] <= 0 ||
      [expiresAt timeIntervalSinceDate:issuedAt] > PDSSpaceCredentialLifetime) {
    if (error) *error = [self error:PDSSpaceJWTErrorLifetime message:@"Credential must use an authority key and live at most two hours"];
    return nil;
  }
  NSDictionary *payload = [self payloadWithIssuer:authority audience:nil space:space
                                                now:issuedAt expiration:expiresAt];
  return [self signPayload:payload type:PDSSpaceCredentialJWTType keyID:keyID
             actorKeyManager:actorKeyManager error:error];
}

+ (NSDictionary<NSString *, id> *)verifyDelegation:(NSString *)token
                                           publicKey:(NSData *)publicKey
                                     expectedIssuer:(NSString *)issuer
                                   expectedAudience:(NSString *)audience
                                    expectedSubject:(NSString *)space
                                                now:(NSDate *)now
                                              error:(NSError **)error {
  NSDictionary *parsed = [self parseAndVerify:token publicKey:publicKey type:PDSSpaceDelegationJWTType
                                          keyID:@"#atproto" maxLifetime:PDSSpaceDelegationLifetime now:now error:error];
  if (!parsed) return nil;
  NSDictionary *payload = parsed[@"payload"];
  if (![payload[@"iss"] isEqualToString:issuer]) {
    if (error) *error = [self error:PDSSpaceJWTErrorIssuer message:@"Delegation issuer does not match caller DID"];
    return nil;
  }
  if (![payload[@"aud"] isEqualToString:audience]) {
    if (error) *error = [self error:PDSSpaceJWTErrorAudience message:@"Delegation audience does not match this space host"];
    return nil;
  }
  if (![payload[@"sub"] isEqualToString:space]) {
    if (error) *error = [self error:PDSSpaceJWTErrorSubject message:@"Delegation subject does not match requested space"];
    return nil;
  }
  return payload;
}

+ (NSDictionary<NSString *, id> *)verifyCredential:(NSString *)token
                                           publicKey:(NSData *)publicKey
                                     expectedIssuer:(NSString *)authority
                                    expectedSubject:(NSString *)space
                                               keyID:(NSString *)keyID
                                                 now:(NSDate *)now
                                               error:(NSError **)error {
  NSDictionary *parsed = [self parseAndVerify:token publicKey:publicKey type:PDSSpaceCredentialJWTType
                                          keyID:keyID maxLifetime:PDSSpaceCredentialLifetime now:now error:error];
  if (!parsed) return nil;
  NSDictionary *payload = parsed[@"payload"];
  if (![payload[@"iss"] isEqualToString:authority]) {
    if (error) *error = [self error:PDSSpaceJWTErrorIssuer message:@"Credential issuer does not match space authority"];
    return nil;
  }
  if (![payload[@"sub"] isEqualToString:space]) {
    if (error) *error = [self error:PDSSpaceJWTErrorSubject message:@"Credential subject does not match requested space"];
    return nil;
  }
  return payload;
}

+ (NSDictionary *)payloadWithIssuer:(NSString *)issuer audience:(NSString *)audience space:(NSString *)space
                                  now:(NSDate *)now expiration:(NSDate *)expiration {
  NSMutableDictionary *payload = [@{
    @"iss" : issuer,
    @"sub" : space,
    @"iat" : @((NSInteger)floor(now.timeIntervalSince1970)),
    @"exp" : @((NSInteger)floor(expiration.timeIntervalSince1970)),
    @"jti" : NSUUID.UUID.UUIDString,
  } mutableCopy];
  if (audience) payload[@"aud"] = audience;
  return payload;
}

+ (NSString *)signPayload:(NSDictionary *)payload type:(NSString *)type keyID:(NSString *)keyID
           actorKeyManager:(id<PDSActorKeyManager>)actorKeyManager error:(NSError **)error {
  if (!actorKeyManager) {
    if (error) *error = [self error:PDSSpaceJWTErrorSignature message:@"No actor signing key is available"];
    return nil;
  }
  NSDictionary *header = @{ @"alg" : @"ES256K", @"typ" : type, @"kid" : keyID };
  NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:error];
  NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:error];
  if (!headerData || !payloadData) return nil;
  NSString *encodedHeader = [JWT base64URLEncodeData:headerData error:error];
  NSString *encodedPayload = [JWT base64URLEncodeData:payloadData error:error];
  if (!encodedHeader || !encodedPayload) return nil;
  NSString *input = [NSString stringWithFormat:@"%@.%@", encodedHeader, encodedPayload];
  NSData *signature = [actorKeyManager signData:[input dataUsingEncoding:NSUTF8StringEncoding] error:error];
  if (signature.length != 64) {
    if (signature && error) *error = [self error:PDSSpaceJWTErrorSignature message:@"Actor key returned an invalid ES256K signature"];
    return nil;
  }
  NSString *encodedSignature = [JWT base64URLEncodeData:signature error:error];
  return encodedSignature ? [NSString stringWithFormat:@"%@.%@", input, encodedSignature] : nil;
}

+ (NSDictionary *)parseAndVerify:(NSString *)token publicKey:(NSData *)publicKey type:(NSString *)type
                             keyID:(NSString *)keyID maxLifetime:(NSTimeInterval)maxLifetime
                               now:(NSDate *)now error:(NSError **)error {
  if (![token isKindOfClass:[NSString class]] || publicKey.length == 0) {
    if (error) *error = [self error:PDSSpaceJWTErrorMalformed message:@"JWT and public key are required"];
    return nil;
  }
  NSArray<NSString *> *parts = [token componentsSeparatedByString:@"."];
  if (parts.count != 3 || parts[0].length == 0 || parts[1].length == 0 || parts[2].length == 0 ||
      ![self isBase64URLPart:parts[0]] || ![self isBase64URLPart:parts[1]] || ![self isBase64URLPart:parts[2]]) {
    if (error) *error = [self error:PDSSpaceJWTErrorMalformed message:@"Malformed compact JWT"];
    return nil;
  }
  NSData *headerData = [JWT base64URLDecode:parts[0] error:nil];
  NSData *payloadData = [JWT base64URLDecode:parts[1] error:nil];
  NSData *signature = [JWT base64URLDecode:parts[2] error:nil];
  NSDictionary *header = headerData ? [NSJSONSerialization JSONObjectWithData:headerData options:0 error:nil] : nil;
  NSDictionary *payload = payloadData ? [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:nil] : nil;
  if (![header isKindOfClass:[NSDictionary class]] || ![payload isKindOfClass:[NSDictionary class]] ||
      signature.length != 64 || ![header[@"alg"] isEqualToString:@"ES256K"] ||
      ![header[@"typ"] isEqualToString:type] || ![header[@"kid"] isEqualToString:keyID]) {
    if (error) *error = [self error:PDSSpaceJWTErrorMalformed message:@"JWT header or payload shape is invalid"];
    return nil;
  }
  if (![self validRequiredStrings:@[payload[@"iss"], payload[@"sub"], payload[@"jti"]]] ||
      ![payload[@"iat"] isKindOfClass:[NSNumber class]] || ![payload[@"exp"] isKindOfClass:[NSNumber class]]) {
    if (error) *error = [self error:PDSSpaceJWTErrorClaims message:@"JWT is missing required typed claims"];
    return nil;
  }
  if ([type isEqualToString:PDSSpaceDelegationJWTType] && ![payload[@"aud"] isKindOfClass:[NSString class]]) {
    if (error) *error = [self error:PDSSpaceJWTErrorClaims message:@"Delegation JWT is missing audience"];
    return nil;
  }
  NSDate *issuedAt = [NSDate dateWithTimeIntervalSince1970:[payload[@"iat"] doubleValue]];
  NSDate *expiresAt = [NSDate dateWithTimeIntervalSince1970:[payload[@"exp"] doubleValue]];
  NSDate *current = now ?: [NSDate date];
  if (![self integralUnixTime:payload[@"iat"]] || ![self integralUnixTime:payload[@"exp"]] ||
      [expiresAt timeIntervalSinceDate:issuedAt] <= 0 ||
      [expiresAt timeIntervalSinceDate:issuedAt] > maxLifetime ||
      [issuedAt timeIntervalSinceDate:current] > PDSSpaceClockSkew) {
    if (error) *error = [self error:PDSSpaceJWTErrorLifetime message:@"JWT timestamps are outside the permitted lifetime window"];
    return nil;
  }
  if ([expiresAt timeIntervalSinceDate:current] < -PDSSpaceClockSkew) {
    if (error) *error = [self error:PDSSpaceJWTErrorExpired message:@"JWT has expired"];
    return nil;
  }
  NSString *input = [NSString stringWithFormat:@"%@.%@", parts[0], parts[1]];
  NSData *inputData = [input dataUsingEncoding:NSUTF8StringEncoding];
  unsigned char digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(inputData.bytes, (CC_LONG)inputData.length, digest);
  if (![[Secp256k1 shared] verifySignature:signature
                                   forHash:[NSData dataWithBytes:digest length:sizeof(digest)]
                             withPublicKey:publicKey
                                    error:nil]) {
    if (error) *error = [self error:PDSSpaceJWTErrorSignature message:@"JWT signature does not verify"];
    return nil;
  }
  return @{ @"header" : header, @"payload" : payload };
}

+ (BOOL)isBase64URLPart:(NSString *)part {
  NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:
      @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"] invertedSet];
  return [part rangeOfCharacterFromSet:invalid].location == NSNotFound;
}

+ (BOOL)integralUnixTime:(NSNumber *)value {
  double number = value.doubleValue;
  return isfinite(number) && floor(number) == number && number >= 0 && number <= 9007199254740991.0;
}

+ (BOOL)validRequiredStrings:(NSArray *)values {
  for (id value in values) if (![value isKindOfClass:[NSString class]] || ((NSString *)value).length == 0) return NO;
  return YES;
}

+ (NSError *)error:(PDSSpaceJWTError)code message:(NSString *)message {
  return [NSError errorWithDomain:PDSSpaceJWTErrorDomain
                             code:code
                         userInfo:@{NSLocalizedDescriptionKey : message}];
}

@end
