// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>

@class Secp256k1KeyPair;

NS_ASSUME_NONNULL_BEGIN

/** @abstract Error domain for label-signing key generation, storage, and signing failures. */
extern NSString * const PDSLabelSigningKeyManagerErrorDomain;

/** @abstract Error codes reported by PDSLabelSigningKeyManager. */
typedef NS_ENUM(NSInteger, PDSLabelSigningKeyManagerError) {
    /** The secp256k1 key pair could not be generated or reconstructed. */
    PDSLabelSigningKeyManagerErrorKeyGenerationFailed = 1,
    /** Key persistence, decryption, or encryption-key derivation failed. */
    PDSLabelSigningKeyManagerErrorKeyStorageFailed = 2,
    /** Input validation or cryptographic signing failed. */
    PDSLabelSigningKeyManagerErrorSigningFailed = 3,
};

/**
 * @abstract Owns the PDS label-signing secp256k1 key pair.
 * @discussion A manager lazily loads an encrypted persisted key or generates a replacement.
 */
@interface PDSLabelSigningKeyManager : NSObject

/** @abstract Directory containing the persisted key, or nil when persistence is disabled. */
@property (nonatomic, copy, readonly, nullable) NSString *keyStoragePath;
/** @abstract Loaded or generated key pair, or nil until key initialization succeeds. */
@property (nonatomic, strong, readonly, nullable) Secp256k1KeyPair *signingKeyPair;
/** @abstract did:key representation of the current public key, or nil when unloaded. */
@property (nonatomic, copy, readonly, nullable) NSString *signingKeyDidKey;

/** @abstract Returns the process-wide manager configured from PDS data paths. */
+ (instancetype)sharedManager;
/** @abstract Creates a manager with an optional directory for persisted key material. */
- (instancetype)initWithStoragePath:(nullable NSString *)path;
/**
 * @abstract Loads a persisted key or generates a new in-memory key pair.
 * @discussion Legacy plaintext keys are migrated when an encryption key is available. A generated
 * key remains usable if its persistence write fails.
 * @return YES when an in-memory signing key is available.
 */
- (BOOL)loadOrGenerateKeyWithError:(NSError **)error;
/**
 * @abstract Signs nonempty data after lazy key initialization.
 * @discussion Hashes the data with SHA-256 and signs the digest with the current secp256k1 key.
 * @return A signature, or nil on initialization, input, or signing failure.
 */
- (nullable NSData *)signData:(NSData *)data error:(NSError **)error;
/**
 * @abstract Verifies a signature over the SHA-256 digest of data using the current public key.
 * @return YES only when verification succeeds.
 */
- (BOOL)verifySignature:(NSData *)signature forData:(NSData *)data error:(NSError **)error;
/** @abstract Clears the in-memory key and deletes its persisted file, ignoring removal failures. */
- (void)clearKey;

@end

NS_ASSUME_NONNULL_END
