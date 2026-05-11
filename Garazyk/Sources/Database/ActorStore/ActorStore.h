// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ActorStore.h

 @abstract Per-user SQLite database store for ATProto actors.

 @discussion Provides transactional access to user-specific data including
 accounts, repositories, records, blocks, and blobs. Uses SQLite with
 reader/writer protocols for safe concurrent access.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Auth/PDSActorKeyManagerProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSActorStore;
@class PDSDatabaseAccount;
@class PDSDatabaseRepo;
@class PDSDatabaseRecord;
@class PDSDatabaseBlock;
@class PDSDatabaseBlob;
/*! Error domain for actor store operations. */
extern NSString * const PDSActorStoreErrorDomain;

/*!
 @enum PDSActorStoreError

 @abstract Error codes for actor store operations.

 @constant PDSActorStoreErrorNotFound Item not found.
 @constant PDSActorStoreErrorAlreadyExists Item already exists.
 @constant PDSActorStoreErrorTransactionRequired Operation requires transaction.
 @constant PDSActorStoreErrorDatabaseClosed Database is closed.
 @constant PDSActorStoreErrorSigningKeyNotFound Signing key not found.
 @constant PDSActorStoreErrorSigningKeyInvalid Signing key is invalid.
 @constant PDSActorStoreErrorBiometricAuthFailed Biometric authentication failed.
 @constant PDSActorStoreErrorBiometryNotAvailable Biometric hardware not available.
 @constant PDSActorStoreErrorBiometryNotEnrolled No biometric enrolled.
 @constant PDSActorStoreErrorAccessControlCreationFailed Failed to create access control.
 @constant PDSActorStoreErrorKeychainUpgradeRequired Keychain upgrade required.
 */
typedef NS_ENUM(NSInteger, PDSActorStoreError) {
    PDSActorStoreErrorNotFound = 1000,
    PDSActorStoreErrorAlreadyExists,
    PDSActorStoreErrorTransactionRequired,
    PDSActorStoreErrorDatabaseClosed,
    PDSActorStoreErrorSigningKeyNotFound,
    PDSActorStoreErrorSigningKeyInvalid,
    PDSActorStoreErrorBiometricAuthFailed,
    PDSActorStoreErrorBiometryNotAvailable,
    PDSActorStoreErrorBiometryNotEnrolled,
    PDSActorStoreErrorAccessControlCreationFailed,
    PDSActorStoreErrorKeychainUpgradeRequired,
};

/*!
 @protocol PDSActorStoreReader

 @abstract Read-only operations on an actor store.
 */
@protocol PDSActorStoreReader <NSObject>

- (nullable PDSDatabaseAccount *)getAccountForDid:(NSString *)did error:(NSError **)error;
- (nullable PDSDatabaseRepo *)getRepoForDid:(NSString *)did error:(NSError **)error;
- (nullable NSData *)getRepoRootForDid:(NSString *)did error:(NSError **)error;
- (nullable NSString *)getRepoRevisionForDid:(NSString *)did error:(NSError **)error;
- (nullable NSString *)latestMutationRevisionWithError:(NSError **)error;
- (BOOL)repoRevisionExists:(NSString *)rev error:(NSError **)error;
- (BOOL)mutationRevisionExists:(NSString *)rev error:(NSError **)error;
- (BOOL)blockRevisionExists:(NSString *)rev error:(NSError **)error;
- (nullable PDSDatabaseRecord *)getRecord:(NSString *)uri forDid:(NSString *)did error:(NSError **)error;
- (NSArray<NSDictionary<NSString *, id> *> *)listRecordTombstonesSinceRev:(nullable NSString *)rev
                                                                     limit:(NSUInteger)limit
                                                                     error:(NSError **)error;
- (NSArray<PDSDatabaseRecord *> *)listRecordsForDid:(NSString *)did 
                                         collection:(nullable NSString *)collection 
                                               limit:(NSUInteger)limit
                                              offset:(NSUInteger)offset
                                               error:(NSError **)error;
- (NSArray<NSData *> *)listBlockCIDsSinceRev:(nullable NSString *)rev
                                        limit:(NSUInteger)limit
                                        error:(NSError **)error;
- (NSArray<NSData *> *)listBlockCIDsForRevision:(NSString *)rev
                                           limit:(NSUInteger)limit
                                           error:(NSError **)error;
- (nullable NSData *)getBlockForCID:(NSData *)cid forDid:(NSString *)did error:(NSError **)error;
- (NSArray<PDSDatabaseBlock *> *)listBlocksForDid:(NSString *)did 
                                            limit:(NSUInteger)limit 
                                           offset:(NSUInteger)offset
                                            error:(NSError **)error;
- (NSInteger)getRecordCountForDid:(NSString *)did collection:(nullable NSString *)collection error:(NSError **)error;
- (NSInteger)getBlockCountForDid:(NSString *)did error:(NSError **)error;

#pragma mark - Blob Operations

- (BOOL)saveBlob:(PDSDatabaseBlob *)blob error:(NSError **)error;
- (nullable PDSDatabaseBlob *)getBlobForCID:(NSData *)cid error:(NSError **)error;
- (NSArray<PDSDatabaseBlob *> *)listBlobsForDid:(NSString *)did
                                          limit:(NSUInteger)limit
                                         cursor:(nullable NSString *)cursor
                                          error:(NSError **)error;
- (BOOL)deleteBlobForCID:(NSData *)cid forDid:(NSString *)did error:(NSError **)error;

@end

/*!
 @protocol PDSActorStoreTransactor

 @abstract Write operations on an actor store.
 */
@protocol PDSActorStoreTransactor <NSObject>

- (BOOL)createAccount:(PDSDatabaseAccount *)account error:(NSError **)error;
- (BOOL)updateAccount:(PDSDatabaseAccount *)account error:(NSError **)error;
- (BOOL)deleteAccount:(NSString *)did error:(NSError **)error;

- (BOOL)createRepo:(PDSDatabaseRepo *)repo error:(NSError **)error;
- (BOOL)updateRepoRoot:(NSString *)did rootCid:(NSData *)rootCid error:(NSError **)error;
- (BOOL)updateRepoRoot:(NSString *)did rootCid:(NSData *)rootCid rev:(nullable NSString *)rev error:(NSError **)error;
- (BOOL)deleteRepo:(NSString *)did error:(NSError **)error;

- (BOOL)putRecord:(PDSDatabaseRecord *)record forDid:(NSString *)did error:(NSError **)error;
- (BOOL)createRecord:(PDSDatabaseRecord *)record forDid:(NSString *)did error:(NSError **)error;
- (BOOL)updateRecord:(PDSDatabaseRecord *)record forDid:(NSString *)did error:(NSError **)error;
- (BOOL)deleteRecord:(NSString *)uri forDid:(NSString *)did error:(NSError **)error;
- (BOOL)addRecordTombstoneURI:(NSString *)uri
                          did:(NSString *)did
                    collection:(NSString *)collection
                         rkey:(NSString *)rkey
                           rev:(NSString *)rev
                         error:(NSError **)error;
- (BOOL)putRecords:(NSArray<PDSDatabaseRecord *> *)records forDid:(NSString *)did error:(NSError **)error;

- (BOOL)putBlock:(PDSDatabaseBlock *)block forDid:(NSString *)did error:(NSError **)error;
- (BOOL)putBlocks:(NSArray<PDSDatabaseBlock *> *)blocks forDid:(NSString *)did error:(NSError **)error;
- (BOOL)deleteBlock:(NSData *)cid forDid:(NSString *)did error:(NSError **)error;

@end

/*!
 @class PDSActorStore

 @abstract Per-user database store.

 @discussion Manages a SQLite database for a single actor. Implements both
 reader and transactor protocols.
 */
@interface PDSActorStore : NSObject <PDSActorStoreReader, PDSActorStoreTransactor>

/*! The DID this store belongs to. */
@property (nonatomic, copy, readonly) NSString *did;

/*! Path to the SQLite database file. */
@property (nonatomic, copy, readonly) NSString *dbPath;

/*! Whether the database is currently open. */
@property (nonatomic, assign, readonly, getter=isOpen) BOOL open;

/*! Key manager for cryptographic operations. */
@property (nonatomic, strong) id<PDSActorKeyManager> keyManager;

/*! Master secret for database encryption/decryption. */
@property (nonatomic, copy, nullable) NSString *masterSecret;

/*! Sign data using the active key. */
- (nullable NSData *)signData:(NSData *)data error:(NSError **)error;

/*! Get the active public key (compressed secp256k1). */
- (nullable NSData *)publicSigningKeyWithError:(NSError **)error;

/*! Get the DID key string (did:key:z...) for the active key. */
- (nullable NSString *)didKeyStringWithError:(NSError **)error;

/*! Creates a store for a DID at the given path. */
+ (instancetype)storeWithDid:(NSString *)did 
                    dbPath:(NSString *)dbPath
                      error:(NSError **)error;

/*! Designated initializer. Creates a store for a DID at the given path without opening. */
- (instancetype)initWithDid:(NSString *)did dbPath:(NSString *)dbPath NS_DESIGNATED_INITIALIZER;

/*! Unavailable — use initWithDid:dbPath: or storeWithDid:dbPath:error:. */
- (instancetype)init NS_UNAVAILABLE;

/*! Opens the database. */
- (BOOL)openWithError:(NSError **)error;

/*! Closes the database. */
- (void)close;

/*! Executes a write transaction. */
- (void)transactWithBlock:(void (^)(id<PDSActorStoreTransactor> transactor, NSError **error))block 
                    error:(NSError **)error;

/*! Executes a read-only transaction. */
- (void)readWithBlock:(void (^)(id<PDSActorStoreReader> reader, NSError **error))block 
                error:(NSError **)error;

/*! Generates a new signing key. */
- (BOOL)generateSigningKeyWithError:(NSError **)error;

/*! Imports an existing signing key (raw private bytes). */
- (BOOL)importSigningKey:(NSData *)privateKey error:(NSError **)error;

/*! Exports the raw private key bytes to be used in migration operations */
- (nullable NSData *)exportSigningKeyWithError:(NSError **)error;

/*! Persists the signing key to the database (used when Keychain is disabled). */
- (BOOL)storeSigningKey:(NSData *)privateKey
              publicKey:(NSData *)publicKey
                  error:(NSError **)error;

/*! Loads the signing key from the database (used when Keychain is disabled). */
- (nullable NSData *)loadSigningKeyWithError:(NSError **)error;


#pragma mark - Rotation Key Management

/*! Stores the rotation key encrypted with the given password. */
- (BOOL)storeRotationKeyPrivate:(NSData *)privateKey
                      publicKey:(NSData *)compressedPublicKey
           encryptedWithPassword:(NSString *)password
                           error:(NSError **)error;

/*! Retrieves the decrypted rotation key. */
- (nullable NSData *)rotationKeyDecryptedWithPassword:(NSString *)password
                                                error:(NSError **)error;

/*! Stores the rotation key encrypted with the PDS master secret. */
- (BOOL)storeRotationKeyPrivate:(NSData *)privateKey
                      publicKey:(NSData *)compressedPublicKey
                            error:(NSError **)error;

/*! Retrieves the decrypted rotation key using the PDS master secret. */
- (nullable NSData *)rotationKeyDecryptedWithError:(NSError **)error;

/*! Clears the repo_root table for re-initialization. */
- (BOOL)clearRepoRootWithError:(NSError **)error;

/*! Derives an encryption key from a password and salt. */
- (nullable NSData *)deriveKeyFromPassword:(NSString *)password salt:(NSData *)salt;

/*! Encrypts data using the crypto utility. */
- (nullable NSData *)encryptData:(NSData *)data withKey:(NSData *)key;

/*! Decrypts data using the crypto utility. */
- (nullable NSData *)decryptData:(NSData *)data withKey:(NSData *)key;

@end

NS_ASSUME_NONNULL_END
