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
 * @enum KeyManagerError
 * @brief Error codes for key management operations
 *
 * @constant KeyManagerErrorKeyGenerationFailed Key generation failed (e.g., insufficient entropy)
 * @constant KeyManagerErrorKeyNotFound Requested key ID not found in storage
 * @constant KeyManagerErrorSigningFailed Signing operation failed (e.g., key corruption)
 * @constant KeyManagerErrorInvalidKeyData Key data format is invalid or corrupted
 * @constant KeyManagerErrorExportFailed Key export to JWK format failed
 * @constant KeyManagerErrorImportFailed Importing external key failed validation
 */
typedef NS_ENUM(NSInteger, KeyManagerError) {
    KeyManagerErrorKeyGenerationFailed = 1000,
    KeyManagerErrorKeyNotFound,
    KeyManagerErrorSigningFailed,
    KeyManagerErrorInvalidKeyData,
    KeyManagerErrorExportFailed,
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
