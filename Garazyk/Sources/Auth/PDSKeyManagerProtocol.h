// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSKeyManagerProtocol.h

 @abstract Protocol definitions for cryptographic key management.

 @discussion
    Defines protocols for key pair management and signing operations.
    Implementations provide platform-specific storage backends:
    - Security.framework (macOS/iOS)
    - OpenSSL with file-based storage (Linux)

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @protocol PDSKeyPair

 @abstract Abstract representation of a cryptographic key pair.

 @discussion
    Provides a common interface for key pair metadata and JWK export.
    Used for JWT signing and verification in OAuth 2.0 flows.
 */
@protocol PDSKeyPair <NSObject>

/*! Unique identifier for this key pair. */
@property (nonatomic, copy, readonly) NSString *keyID;

/*! Algorithm identifier (e.g., "ES256", "RS256"). */
@property (nonatomic, copy, readonly) NSString *algorithm;

/*! Timestamp when this key was created. */
@property (nonatomic, strong, readonly) NSDate *createdAt;

/*! Whether this key is currently active for signing. */
@property (nonatomic, assign) BOOL isActive;

/*!
 @method publicKeyJWK

 @abstract Export public key as JSON Web Key (JWK).

 @return A dictionary containing the JWK representation, or nil on error.
 */
- (nullable NSDictionary *)publicKeyJWK;

/*!
 @method publicKeyThumbprint

 @abstract Calculate JWK thumbprint (RFC 7638).

 @return The base64url-encoded thumbprint string, or nil on error.
 */
- (nullable NSString *)publicKeyThumbprint;

@end

/*!
 @protocol PDSKeyManager

 @abstract Protocol for key management operations.

 @discussion
    Provides key pair generation, storage, retrieval, and signing operations.
    Implementations handle platform-specific secure storage.

    Thread Safety: All methods should be thread-safe. Implementations must
    handle concurrent access to the key store.
 */
@protocol PDSKeyManager <NSObject>

/*!
 @method generateKeyPairWithAlgorithm:keySize:error:

 @abstract Generate a new key pair.

 @param algorithm The algorithm identifier (e.g., "ES256" for ECDSA P-256).
 @param keySize The key size in bits (e.g., 256 for ES256).
 @param error On failure, set to an error describing the failure.
 @return The newly generated key pair, or nil on failure.
 */
- (nullable id<PDSKeyPair>)generateKeyPairWithAlgorithm:(NSString *)algorithm
                                                keySize:(NSUInteger)keySize
                                                  error:(NSError **)error;

/*!
 @method getKeyPairWithID:error:

 @abstract Retrieve a specific key pair by ID.

 @param keyID The unique identifier of the key pair.
 @param error On failure, set to an error describing the failure.
 @return The key pair, or nil if not found.
 */
- (nullable id<PDSKeyPair>)getKeyPairWithID:(NSString *)keyID error:(NSError **)error;

/*!
 @method getActiveKeyPair:

 @abstract Retrieve the currently active key pair.

 @param error On failure, set to an error describing the failure.
 @return The active key pair, or nil if none exists.
 */
- (nullable id<PDSKeyPair>)getActiveKeyPair:(NSError **)error;

/*!
 @method allKeyPairs:

 @abstract Retrieve all stored key pairs.

 @param error On failure, set to an error describing the failure.
 @return An array of all key pairs (may be empty).
 */
- (NSArray<id<PDSKeyPair>> *)allKeyPairs:(NSError **)error;

/*!
 @method deleteKeyPairWithID:error:

 @abstract Delete a key pair.

 @param keyID The unique identifier of the key pair to delete.
 @param error On failure, set to an error describing the failure.
 @return YES on success, NO on failure.
 */
- (BOOL)deleteKeyPairWithID:(NSString *)keyID error:(NSError **)error;

/*!
 @method setKeyPairActive:error:

 @abstract Mark a key pair as active.

 @param keyID The unique identifier of the key pair to activate.
 @param error On failure, set to an error describing the failure.
 @return YES on success, NO on failure.
 */
- (BOOL)setKeyPairActive:(NSString *)keyID error:(NSError **)error;

/*!
 @method signData:withKeyID:error:

 @abstract Sign raw data with a specific key.

 @param data The raw data to sign.
 @param keyID The unique identifier of the signing key.
 @param error On failure, set to an error describing the failure.
 @return The DER-encoded signature, or nil on failure.
 */
- (nullable NSData *)signData:(NSData *)data
                     withKeyID:(NSString *)keyID
                         error:(NSError **)error;

/*!
 @method signPayload:withKeyID:error:

 @abstract Sign a JSON payload (creates a JWT).

 @param payload The JSON payload to sign.
 @param keyID The unique identifier of the signing key.
 @param error On failure, set to an error describing the failure.
 @return The signed JWT as a dictionary, or nil on failure.
 */
- (nullable NSDictionary *)signPayload:(NSDictionary *)payload
                              withKeyID:(NSString *)keyID
                                  error:(NSError **)error;

/*!
 @method signString:withKeyID:error:

 @abstract Sign a string (creates a base64-encoded signature).

 @param string The string to sign.
 @param keyID The unique identifier of the signing key.
 @param error On failure, set to an error describing the failure.
 @return The base64-encoded signature, or nil on failure.
 */
- (nullable NSString *)signString:(NSString *)string
                         withKeyID:(NSString *)keyID
                             error:(NSError **)error;

/*!
 @method verifySignature:forData:withKeyID:error:

 @abstract Verify a signature for raw data.

 @param signature The DER-encoded signature to verify.
 @param data The original data that was signed.
 @param keyID The unique identifier of the verification key.
 @param error On failure, set to an error describing the failure.
 @return YES if the signature is valid, NO otherwise.
 */
/**
 * @abstract Performs the verifySignature operation.
 */
- (BOOL)verifySignature:(NSData *)signature
                forData:(NSData *)data
              withKeyID:(NSString *)keyID
                  error:(NSError **)error;

/*!
 @method toJWKS

 @abstract Export all public keys as JSON Web Key Set (JWKS).

 @return A dictionary containing the JWKS with "keys" array.
 */
- (NSDictionary *)toJWKS;

/*!
 @method toJWKSArray

 @abstract Export all public keys as array of JWK dictionaries.

 @return An array of JWK dictionaries.
 */
- (NSArray<NSDictionary *> *)toJWKSArray;

@end

NS_ASSUME_NONNULL_END
