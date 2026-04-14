/*!
 @file PLCRotationKeyManager.h

 @abstract Management of rotation keys for PLC operations.

 @discussion
    Handles generation, storage, and retrieval of secp256k1 key pairs used
    for signing PLC operations. Keys can be stored on disk for persistence
    or held in memory for ephemeral use.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class Secp256k1KeyPair;

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for rotation key manager operations. */
extern NSString * const PLCRotationKeyManagerErrorDomain;

/*!
 @enum PLCRotationKeyManagerError

 @abstract Error codes for rotation key manager operations.

 @constant PLCRotationKeyManagerErrorKeyGenerationFailed Failed to generate a new key pair.
 @constant PLCRotationKeyManagerErrorKeyStorageFailed Failed to store the key pair to disk.
 @constant PLCRotationKeyManagerErrorKeyNotFound The requested key was not found.
 @constant PLCRotationKeyManagerErrorInvalidKey The key is invalid or corrupted.
 */
typedef NS_ENUM(NSInteger, PLCRotationKeyManagerError) {
    PLCRotationKeyManagerErrorKeyGenerationFailed = 1,
    PLCRotationKeyManagerErrorKeyStorageFailed = 2,
    PLCRotationKeyManagerErrorKeyNotFound = 3,
    PLCRotationKeyManagerErrorInvalidKey = 4,
};

/*!
 @class PLCRotationKeyManager

 @abstract Manages rotation keys for signing PLC operations.

 @discussion
    Provides a centralized manager for the secp256k1 key pair used to sign
    PLC operations. Supports both persistent (file-based) and ephemeral
    (in-memory) key storage.

    Thread Safety: This class is thread-safe for read operations. Key
    generation and loading should be performed during initialization.

 @code
    PLCRotationKeyManager *manager = [[PLCRotationKeyManager alloc] initWithStoragePath:@"/path/to/keys"];
    [manager loadOrGenerateKeyWithError:&error];
    NSString *didKey = manager.rotationKeyDidKey;
 @endcode
 */
@interface PLCRotationKeyManager : NSObject

/*! Path where the key pair is stored on disk (nil for in-memory only). */
@property (nonatomic, copy, readonly, nullable) NSString *keyStoragePath;

/*! The current rotation key pair. */
@property (nonatomic, strong, readonly, nullable) Secp256k1KeyPair *rotationKeyPair;

/*! The did:key representation of the rotation public key. */
@property (nonatomic, copy, readonly, nullable) NSString *rotationKeyDidKey;

/*!
 @method initWithStoragePath:

 @abstract Initializes the manager with an optional storage path.

 @param path Path to store the key pair on disk, or nil for in-memory only.

 @return A new rotation key manager instance.
 */
- (instancetype)initWithStoragePath:(nullable NSString *)path;

/*!
 @method sharedManager

 @abstract Returns the shared singleton manager.

 @return The shared PLCRotationKeyManager instance.
 */
+ (instancetype)sharedManager;

/*!
 @method loadOrGenerateKeyWithError:

 @abstract Loads an existing key or generates a new one if not present.

 @param error On failure, set to an error describing the failure.
 @return YES on success, NO on failure.
 */
- (BOOL)loadOrGenerateKeyWithError:(NSError **)error;

/*!
 @method signHash:result:error:

 @abstract Signs a hash using the rotation key.

 @param hash The 32-byte hash to sign.
 @param result On success, receives the DER-encoded signature.
 @param error On failure, set to an error describing the failure.
 @return YES on success, NO on failure.
 */
- (BOOL)signHash:(NSData *)hash result:(NSData * _Nullable * _Nullable)result error:(NSError **)error;

/*!
 @method clearKey

 @abstract Clears the current key from memory (and disk if persistent).

 @discussion
    Warning: This permanently deletes the key. Operations signed with this
    key will no longer be verifiable.
 */
- (void)clearKey;

@end

NS_ASSUME_NONNULL_END
