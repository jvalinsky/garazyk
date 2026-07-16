// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>

@protocol PDSActorKeyManager;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const PDSSpaceJWTErrorDomain;
extern NSString *const PDSSpaceDelegationJWTType;
extern NSString *const PDSSpaceCredentialJWTType;

typedef NS_ENUM(NSInteger, PDSSpaceJWTError) {
  PDSSpaceJWTErrorMalformed = 1,
  PDSSpaceJWTErrorClaims,
  PDSSpaceJWTErrorSignature,
  PDSSpaceJWTErrorExpired,
  PDSSpaceJWTErrorLifetime,
  PDSSpaceJWTErrorAudience,
  PDSSpaceJWTErrorIssuer,
  PDSSpaceJWTErrorSubject,
  PDSSpaceJWTErrorReplay,
};

/** Strict minting and verification for proposal-0016 JWT artifacts. */
@interface PDSSpaceJWT : NSObject

+ (nullable NSString *)mintDelegationWithIssuer:(NSString *)issuer
                                        audience:(NSString *)audience
                                           space:(NSString *)space
                                 actorKeyManager:(id<PDSActorKeyManager>)actorKeyManager
                                             now:(nullable NSDate *)now
                                      expiration:(nullable NSDate *)expiration
                                           error:(NSError **)error;

/**
 * `keyID` must identify the key actually used: `#atproto_space` for a
 * dedicated authority key or `#atproto` for the documented fallback.
 */
+ (nullable NSString *)mintCredentialWithAuthority:(NSString *)authority
                                             space:(NSString *)space
                                             keyID:(NSString *)keyID
                                   actorKeyManager:(id<PDSActorKeyManager>)actorKeyManager
                                               now:(nullable NSDate *)now
                                        expiration:(nullable NSDate *)expiration
                                             error:(NSError **)error;

+ (nullable NSDictionary<NSString *, id> *)verifyDelegation:(NSString *)token
                                                 publicKey:(NSData *)publicKey
                                           expectedIssuer:(NSString *)issuer
                                         expectedAudience:(NSString *)audience
                                          expectedSubject:(NSString *)space
                                                      now:(nullable NSDate *)now
                                                    error:(NSError **)error;

+ (nullable NSDictionary<NSString *, id> *)verifyCredential:(NSString *)token
                                                   publicKey:(NSData *)publicKey
                                             expectedIssuer:(NSString *)authority
                                            expectedSubject:(NSString *)space
                                                       keyID:(NSString *)keyID
                                                         now:(nullable NSDate *)now
                                                       error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
