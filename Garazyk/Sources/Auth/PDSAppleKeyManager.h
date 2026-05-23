// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file PDSAppleKeyManager.h
 * @brief Apple Security.framework implementation of PDSKeyManager
 */

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import "PDSKeyManagerProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;

/** Error domain for Apple-backed key manager operations. */
extern NSString * const KeyManagerErrorDomain;

/**
 * @abstract Error codes reported by Apple-backed key management operations.
 */
typedef NS_ENUM(NSInteger, KeyManagerError) {
    /** Key generation failed because Security.framework could not create key material. */
    KeyManagerErrorKeyGenerationFailed = 1000,
    /** The requested key identifier was not found in storage. */
    KeyManagerErrorKeyNotFound,
    /** Signing failed because the key or requested algorithm could not complete the operation. */
    KeyManagerErrorSigningFailed,
    /** Stored or imported key data was malformed or unsupported. */
    KeyManagerErrorInvalidKeyData,
    /** Exporting a key to JWK or related interchange data failed. */
    KeyManagerErrorExportFailed,
    /** Imported key material failed validation. */
    KeyManagerErrorImportFailed
};

/**
 * @class PDSAppleKeyPair
 * @brief Apple Security.framework implementation of a key pair
 */
@interface PDSAppleKeyPair : NSObject <PDSKeyPair>

/** Stable key identifier used by session and signing code. */
@property (nonatomic, copy) NSString *keyID;
/** Signing algorithm associated with this key pair. */
@property (nonatomic, copy) NSString *algorithm;
/** Security.framework private key reference, when backed by SecKey. */
@property (nonatomic, assign, nullable) SecKeyRef privateKey;
/** Security.framework public key reference, when backed by SecKey. */
@property (nonatomic, assign, nullable) SecKeyRef publicKey;
/** Creation timestamp for key rotation and audit decisions. */
@property (nonatomic, strong) NSDate *createdAt;
/** Whether this key pair is the active signing key. */
@property (nonatomic, assign) BOOL isActive;
/** Whether the key pair is stored in Secure Enclave where supported. */
@property (nonatomic, assign) BOOL isSecureEnclaveKey;
/** Raw secp256k1 private key bytes used for ES256K signing. */
@property (nonatomic, copy, nullable) NSData *secp256k1PrivateKeyData;  // Raw secp256k1 private key for ES256K signing

/**
 * @abstract Wraps Security.framework key references in a PDS key-pair object.
 */
+ (nullable instancetype)keyPairFromPrivateKey:(SecKeyRef)privateKey
                                      publicKey:(SecKeyRef)publicKey
                                        keyID:(NSString *)keyID
                                     algorithm:(NSString *)algorithm;

/**
 * @abstract Creates an ES256K key pair from raw secp256k1 key material.
 */
+ (nullable instancetype)keyPairWithSecp256k1PrivateKey:(NSData *)privateKeyData
                                              publicKey:(NSData *)publicKeyData
                                                 keyID:(NSString *)keyID;

@end

/**
 * @class PDSAppleKeyManager
 * @brief Apple Security.framework implementation of key management
 */
@interface PDSAppleKeyManager : NSObject <PDSKeyManager, NSSecureCoding>

/** Keychain service identifier used for persisted keys. */
@property (nonatomic, copy) NSString *serviceIdentifier;
/** Security.framework signing algorithm used for SecKey-backed signatures. */
@property (nonatomic, assign) SecKeyAlgorithm signingAlgorithm;
/** Identifier for the active signing key. */
@property (nonatomic, copy, nullable) NSString *currentKeyID;
/** Database used to persist and load key metadata, when configured. */
@property (nonatomic, strong, nullable) PDSDatabase *database;

/** Initializes a key manager scoped to a keychain service identifier. */
- (nullable instancetype)initWithServiceIdentifier:(NSString *)serviceIdentifier;
/** Initializes a key manager backed by the supplied database and service identifier. */
- (nullable instancetype)initWithDatabase:(PDSDatabase *)database serviceIdentifier:(NSString *)serviceIdentifier;

// Backward-compatible test/helper API.
/** Generates and stores a key pair using the requested algorithm and key size. */
- (nullable PDSAppleKeyPair *)generatePDSAppleKeyPairWithAlgorithm:(NSString *)algorithm
                                                            keySize:(NSUInteger)keySize
                                                              error:(NSError **)error;
/** Loads a key pair by identifier. */
- (nullable PDSAppleKeyPair *)getPDSAppleKeyPairWithID:(NSString *)keyID
                                                  error:(NSError **)error;
/** Loads the active key pair. */
- (nullable PDSAppleKeyPair *)getActivePDSAppleKeyPair:(NSError **)error;
/** Lists all stored key pairs. */
- (NSArray<PDSAppleKeyPair *> *)allPDSAppleKeyPairs:(NSError **)error;
/** Deletes the key pair with the supplied identifier. */
- (BOOL)deletePDSAppleKeyPairWithID:(NSString *)keyID error:(NSError **)error;
/** Marks the key pair with the supplied identifier as active. */
- (BOOL)setPDSAppleKeyPairActive:(NSString *)keyID error:(NSError **)error;

// Additional methods specific to Apple implementation if needed
/** Verifies a signature with an explicit public key reference. */
- (BOOL)verifySignature:(NSData *)signature
               forData:(NSData *)data
         withPublicKey:(SecKeyRef)publicKey
                 error:(NSError **)error;

/** Verifies a signature using the public key associated with a stored key identifier. */
- (BOOL)verifySignature:(NSData *)signature
                forData:(NSData *)data
              withKeyID:(NSString *)keyID
                  error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
