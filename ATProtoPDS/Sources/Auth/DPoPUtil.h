/*!
 @file DPoPUtil.h

 @abstract DPoP (Demonstration of Proof-of-Possession) token utilities.

 @discussion Implements RFC 9449 DPoP for binding OAuth tokens to public keys.
 Prevents token theft by requiring proof of private key possession on each request.

 NOTE: This class uses SecKeyRef which is only available on macOS.
 For cross-platform DPoP support, use AuthCryptoDPoP directly with
 the protocol-based key interfaces (PDSPrivateKeyProtocol/PDSPublicKeyProtocol).

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Compat/PDSTypes.h"

#if defined(__APPLE__) && !defined(GNUSTEP)
#import <Security/Security.h>
#else
// On GNUstep, SecKeyRef is not available - use void* as placeholder
typedef void *SecKeyRef;
#endif

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

 @discussion NOTE: This class is only available on macOS. On GNUstep,
 use AuthCryptoDPoP directly with protocol-based key interfaces.
 */
@interface DPoPUtil : NSObject

/*!
 @brief Creates a DPoP proof for a request.

 @param htm HTTP method
 @param htu HTTP URI
 @param nonce Server nonce (optional)
 @param privateKey SecKeyRef private key (macOS only)
 @param error Error output
 @return DPoPToken or nil on error

 @discussion On GNUstep, this always returns nil. Use AuthCryptoDPoP instead.
 */
+ (nullable DPoPToken *)createDPoPForMethod:(NSString *)htm
                                         uri:(NSString *)htu
                                       nonce:(nullable NSString *)nonce
                                         key:(SecKeyRef)privateKey
                                       error:(NSError **)error;

/*!
 @brief Verifies a DPoP proof JWT.

 @param dpopJwt The proof JWT string
 @param publicKey Optional SecKeyRef to verify against (macOS only)
 @param htm HTTP method
 @param htu HTTP URI
 @param nonce Expected nonce
 @param error Error output
 @return YES if valid

 @discussion On GNUstep, this always returns NO. Use AuthCryptoDPoP instead.
 */
+ (BOOL)verifyDPoP:(NSString *)dpopJwt
      withPublicKey:(nullable SecKeyRef)publicKey
            method:(NSString *)htm
               uri:(NSString *)htu
             nonce:(nullable NSString *)nonce
              error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
