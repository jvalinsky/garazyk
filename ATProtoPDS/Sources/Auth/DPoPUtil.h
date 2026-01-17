/*!
 @file DPoPUtil.h

 @abstract DPoP (Demonstration of Proof-of-Possession) token utilities.

 @discussion Implements RFC 9449 DPoP for binding OAuth tokens to public keys.
 Prevents token theft by requiring proof of private key possession on each request.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import <Security/Security.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class DPoPToken

 @abstract Represents a DPoP proof JWT.

 @discussion Contains the proof components for binding a request to a key pair.
 */
@interface DPoPToken : NSObject

/*! The signed DPoP proof JWT. */
@property (nonatomic, copy) NSString *jwt;

/*! HTTP method the proof is for (GET, POST, etc.). */
@property (nonatomic, copy) NSString *htm;

/*! HTTP URI the proof is for. */
@property (nonatomic, copy) NSString *htu;

/*! Unique identifier for this proof. */
@property (nonatomic, copy) NSString *jti;

/*! Server-provided nonce for freshness. */
@property (nonatomic, copy, nullable) NSString *nonce;

/*! Timestamp when the proof was created. */
@property (nonatomic, strong) NSDate *iat;

/*! Expiration time for the proof. */
@property (nonatomic, strong, nullable) NSDate *exp;

/*! Access token hash for token binding. */
@property (nonatomic, copy, nullable) NSString *ath;

/*! Creates a new DPoP proof for a request. */
+ (nullable instancetype)createWithMethod:(NSString *)htm
                                      uri:(NSString *)htu
                                  nonce:(nullable NSString *)nonce
                                  error:(NSError **)error;

/*! Returns the JWT header claims. */
- (NSDictionary *)header;

/*! Returns the JWT payload claims. */
- (NSDictionary *)payload;

@end

/*!
 @class DPoPUtil

 @abstract Utility class for DPoP proof creation and verification.
 */
@interface DPoPUtil : NSObject

/*! Creates a DPoP proof for a request. */
+ (nullable DPoPToken *)createDPoPForMethod:(NSString *)htm
                                         uri:(NSString *)htu
                                       nonce:(nullable NSString *)nonce
                                         key:(SecKeyRef)privateKey
                                       error:(NSError **)error;

/*! Verifies a DPoP proof JWT. */
+ (BOOL)verifyDPoP:(NSString *)dpopJwt
          withPublicKey:(nullable SecKeyRef)publicKey
               method:(NSString *)htm
                  uri:(NSString *)htu
               nonce:(nullable NSString *)nonce
                error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
