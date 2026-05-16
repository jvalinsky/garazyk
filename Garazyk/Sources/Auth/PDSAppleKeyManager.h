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

/*! Error domain for KeyManager operations */
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

@property (nonatomic, copy) NSString *keyID;
@property (nonatomic, copy) NSString *algorithm;
@property (nonatomic, assign, nullable) SecKeyRef privateKey;
@property (nonatomic, assign, nullable) SecKeyRef publicKey;
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, assign) BOOL isActive;
@property (nonatomic, assign) BOOL isSecureEnclaveKey;
@property (nonatomic, copy, nullable) NSData *secp256k1PrivateKeyData;  // Raw secp256k1 private key for ES256K signing

+ (nullable instancetype)keyPairFromPrivateKey:(SecKeyRef)privateKey
                                      publicKey:(SecKeyRef)publicKey
                                        keyID:(NSString *)keyID
                                     algorithm:(NSString *)algorithm;

+ (nullable instancetype)keyPairWithSecp256k1PrivateKey:(NSData *)privateKeyData
                                              publicKey:(NSData *)publicKeyData
                                                 keyID:(NSString *)keyID;

@end

/**
 * @class PDSAppleKeyManager
 * @brief Apple Security.framework implementation of key management
 */
@interface PDSAppleKeyManager : NSObject <PDSKeyManager, NSSecureCoding>

@property (nonatomic, copy) NSString *serviceIdentifier;
@property (nonatomic, assign) SecKeyAlgorithm signingAlgorithm;
@property (nonatomic, copy, nullable) NSString *currentKeyID;
@property (nonatomic, strong, nullable) PDSDatabase *database;

- (nullable instancetype)initWithServiceIdentifier:(NSString *)serviceIdentifier;
- (nullable instancetype)initWithDatabase:(PDSDatabase *)database serviceIdentifier:(NSString *)serviceIdentifier;

// Backward-compatible test/helper API.
- (nullable PDSAppleKeyPair *)generatePDSAppleKeyPairWithAlgorithm:(NSString *)algorithm
                                                            keySize:(NSUInteger)keySize
                                                              error:(NSError **)error;
- (nullable PDSAppleKeyPair *)getPDSAppleKeyPairWithID:(NSString *)keyID
                                                  error:(NSError **)error;
- (nullable PDSAppleKeyPair *)getActivePDSAppleKeyPair:(NSError **)error;
- (NSArray<PDSAppleKeyPair *> *)allPDSAppleKeyPairs:(NSError **)error;
- (BOOL)deletePDSAppleKeyPairWithID:(NSString *)keyID error:(NSError **)error;
- (BOOL)setPDSAppleKeyPairActive:(NSString *)keyID error:(NSError **)error;

// Additional methods specific to Apple implementation if needed
- (BOOL)verifySignature:(NSData *)signature
               forData:(NSData *)data
               withKey:(SecKeyRef)publicKey
                 error:(NSError **)error;

- (BOOL)verifySignature:(NSData *)signature
                forData:(NSData *)data
              withKeyID:(NSString *)keyID
                  error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
