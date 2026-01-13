/**
 * @file KeyManager.h
 * @brief Cryptographic key pair management for JWT signing and verification
 *
 * KeyManager handles the lifecycle of RSA/ECDSA key pairs used for signing
 * JWTs in the ATProto authentication flow. Supports key rotation, secure
 * keychain storage, and JWKS generation for federation.
 *
 * Thread-safe through internal dispatch queue synchronization.
 *
 * @warning Keys are stored in the system keychain. Requires Security.framework.
 * @see JWT, KeyRotationManager
 */

#import <Foundation/Foundation.h>
#import <Security/Security.h>

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
 * @class KeyPair
 * @brief Represents a cryptographic key pair (private and public keys)
 *
 * KeyPair encapsulates an RSA or ECDSA key pair with metadata for tracking
 * key lifecycle. Used by KeyManager for signing operations and JWKS export.
 *
 * @note SecKeyRef properties are not retained by default. Caller must manage lifetime.
 */
@interface KeyPair : NSObject

/*! Unique identifier for this key pair (e.g., UUID or thumbprint) */
@property (nonatomic, copy) NSString *keyID;

/*! Algorithm identifier (e.g., "RS256", "ES256") */
@property (nonatomic, copy) NSString *algorithm;

/*! Private key reference for signing operations */
@property (nonatomic, assign) SecKeyRef privateKey;

/*! Public key reference for verification and JWKS export */
@property (nonatomic, assign) SecKeyRef publicKey;

/*! Timestamp when this key pair was created */
@property (nonatomic, strong) NSDate *createdAt;

/*! Whether this key pair is currently active for signing */
@property (nonatomic, assign) BOOL isActive;

/**
 * @brief Create a KeyPair from existing SecKeyRef objects
 *
 * @param privateKey Private key reference from keychain or generation
 * @param publicKey Public key reference
 * @param keyID Unique identifier for this key pair
 * @param algorithm Algorithm identifier (RS256, ES256, etc.)
 * @return KeyPair instance or nil if keys are invalid
 */
+ (nullable instancetype)keyPairFromPrivateKey:(SecKeyRef)privateKey
                                      publicKey:(SecKeyRef)publicKey
                                        keyID:(NSString *)keyID
                                     algorithm:(NSString *)algorithm;

/**
 * @brief Export public key as JSON Web Key (JWK)
 *
 * @return Dictionary containing JWK representation (kty, kid, alg, n, e/x, y)
 */
- (nullable NSDictionary *)publicKeyJWK;

/**
 * @brief Calculate JWK thumbprint (RFC 7638) for this key pair
 *
 * @return Base64url-encoded SHA-256 hash of JWK canonical form
 */
- (nullable NSString *)publicKeyThumbprint;

@end

/**
 * @class KeyManager
 * @brief Manages cryptographic key pairs for JWT signing and verification
 *
 * KeyManager provides a centralized interface for generating, storing, and using
 * cryptographic keys for JWT authentication. Keys can be stored in either the
 * system keychain or a PDSDatabase for persistence across launches.
 *
 * Responsibilities:
 * - Generate RSA/ECDSA key pairs
 * - Store keys securely (keychain or database)
 * - Sign data and payloads with active key
 * - Export public keys as JWKS for federation
 * - Support key rotation through active flag
 *
 * Usage:
 * @code
 * KeyManager *km = [[KeyManager alloc] initWithServiceIdentifier:@"com.example.pds"];
 * KeyPair *kp = [km generateKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&err];
 * NSData *sig = [km signData:dataToSign withKeyID:kp.keyID error:&err];
 * NSDictionary *jwks = [km toJWKS];
 * @endcode
 *
 * @note Thread-safe for concurrent read operations. Write operations are serialized.
 */
@interface KeyManager : NSObject

/*! Service identifier for keychain access (e.g., bundle ID) */
@property (nonatomic, copy) NSString *serviceIdentifier;

/*! Default signing algorithm for this manager (e.g., kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256) */
@property (nonatomic, assign) SecKeyAlgorithm signingAlgorithm;

/*! Key ID of the currently active key pair, or nil if none set */
@property (nonatomic, copy, nullable) NSString *currentKeyID;

/*! Optional database for persistent key storage. If nil, uses keychain only */
@property (nonatomic, strong, nullable) PDSDatabase *database;

/**
 * @brief Initialize with keychain-only storage
 *
 * @param serviceIdentifier Service identifier for keychain (typically bundle ID)
 * @return KeyManager instance or nil on failure
 */
- (nullable instancetype)initWithServiceIdentifier:(NSString *)serviceIdentifier;

/**
 * @brief Initialize with database-backed storage
 *
 * @param database Database instance for persistent key storage
 * @param serviceIdentifier Service identifier for keychain fallback
 * @return KeyManager instance or nil on failure
 */
- (nullable instancetype)initWithDatabase:(PDSDatabase *)database serviceIdentifier:(NSString *)serviceIdentifier;

/**
 * @brief Generate a new key pair
 *
 * Creates a new RSA or ECDSA key pair and stores it in keychain/database.
 * The key is marked as active if no other active key exists.
 *
 * @param algorithm Algorithm identifier: "RS256", "RS384", "RS512", "ES256", "ES384", "ES512"
 * @param keySize Key size in bits (2048/4096 for RSA, 256/384/521 for ECDSA)
 * @param error Error pointer for failure details
 * @return New KeyPair or nil on failure
 */
- (nullable KeyPair *)generateKeyPairWithAlgorithm:(NSString *)algorithm
                                          keySize:(NSUInteger)keySize
                                             error:(NSError **)error;

/**
 * @brief Retrieve a specific key pair by ID
 *
 * @param keyID Unique identifier of the key pair
 * @param error Error pointer (KeyManagerErrorKeyNotFound if not found)
 * @return KeyPair or nil if not found
 */
- (nullable KeyPair *)getKeyPairWithID:(NSString *)keyID error:(NSError **)error;

/**
 * @brief Retrieve the currently active key pair
 *
 * @param error Error pointer (KeyManagerErrorKeyNotFound if no active key)
 * @return Active KeyPair or nil
 */
- (nullable KeyPair *)getActiveKeyPair:(NSError **)error;

/**
 * @brief Retrieve all stored key pairs
 *
 * @param error Error pointer for storage access failures
 * @return Array of KeyPair objects (may be empty)
 */
- (NSArray<KeyPair *> *)allKeyPairs:(NSError **)error;

/**
 * @brief Delete a key pair from storage
 *
 * Removes the key pair from keychain and database. If this is the active key,
 * currentKeyID is set to nil.
 *
 * @param keyID Identifier of key pair to delete
 * @param error Error pointer for deletion failures
 * @return YES if deleted successfully, NO on failure
 */
- (BOOL)deleteKeyPairWithID:(NSString *)keyID error:(NSError **)error;

/**
 * @brief Mark a key pair as active for signing
 *
 * Only one key can be active at a time. Previous active key is deactivated.
 *
 * @param keyID Identifier of key pair to activate
 * @param error Error pointer (KeyManagerErrorKeyNotFound if key doesn't exist)
 * @return YES if activated successfully, NO on failure
 */
- (BOOL)setKeyPairActive:(NSString *)keyID error:(NSError **)error;

/**
 * @brief Sign raw data with a specific key
 *
 * @param data Data to sign
 * @param keyID Key ID to use for signing
 * @param error Error pointer (KeyManagerErrorSigningFailed on failure)
 * @return Signature bytes or nil on failure
 */
- (nullable NSData *)signData:(NSData *)data
                     withKeyID:(NSString *)keyID
                         error:(NSError **)error;

/**
 * @brief Sign a JSON payload (dictionary) with a specific key
 *
 * Serializes dictionary to canonical JSON before signing.
 *
 * @param payload Dictionary to sign (must be JSON-serializable)
 * @param keyID Key ID to use for signing
 * @param error Error pointer for serialization or signing failures
 * @return Signature bytes or nil on failure
 */
- (nullable NSDictionary *)signPayload:(NSDictionary *)payload
                              withKeyID:(NSString *)keyID
                                  error:(NSError **)error;

/**
 * @brief Sign a string with a specific key
 *
 * Encodes string as UTF-8 before signing.
 *
 * @param string String to sign
 * @param keyID Key ID to use for signing
 * @param error Error pointer for signing failures
 * @return Base64-encoded signature or nil on failure
 */
- (nullable NSString *)signString:(NSString *)string
                         withKeyID:(NSString *)keyID
                             error:(NSError **)error;

/**
 * @brief Verify a signature against data with a public key
 *
 * @param signature Signature bytes to verify
 * @param data Original data that was signed
 * @param publicKey Public key reference for verification
 * @param error Error pointer for verification failures
 * @return YES if signature is valid, NO otherwise
 */
- (BOOL)verifySignature:(NSData *)signature
               forData:(NSData *)data
               withKey:(SecKeyRef)publicKey
                  error:(NSError **)error;

/**
 * @brief Export all public keys as a JSON Web Key Set (JWKS)
 *
 * @return Dictionary containing "keys" array of JWK objects
 */
- (NSDictionary *)toJWKS;

/**
 * @brief Export all public keys as an array of JWK dictionaries
 *
 * @return Array of JWK dictionaries for all stored key pairs
 */
- (NSArray<NSDictionary *> *)toJWKSArray;

@end

NS_ASSUME_NONNULL_END
