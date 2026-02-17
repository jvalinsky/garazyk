/*!
 @file ActorStore.h

 @abstract Per-user SQLite database store for ATProto actors.

 @discussion Provides transactional access to user-specific data including
 accounts, repositories, records, blocks, and blobs. Uses SQLite with
 reader/writer protocols for safe concurrent access.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import <sqlite3.h>
#import <Security/Security.h>

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
- (nullable PDSDatabaseRecord *)getRecord:(NSString *)uri forDid:(NSString *)did error:(NSError **)error;
- (NSArray<NSDictionary<NSString *, id> *> *)listRecordTombstonesSinceRev:(nullable NSString *)rev
                                                                     limit:(NSUInteger)limit
                                                                     error:(NSError **)error;
- (NSArray<PDSDatabaseRecord *> *)listRecordsForDid:(NSString *)did 
                                         collection:(nullable NSString *)collection 
                                               limit:(NSUInteger)limit
                                              offset:(NSUInteger)offset
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

/*! Raw SQLite handle (internal use). */
@property (nonatomic, assign, readonly) sqlite3 *db;

/*! Creates a store for a DID at the given path. */
+ (instancetype)storeWithDid:(NSString *)did 
                    dbPath:(NSString *)dbPath
                      error:(NSError **)error;

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

/*! Gets the signing key from Keychain. Caller must CFRelease the returned key. */
- (nullable SecKeyRef)signingKeyWithError:(NSError **)error;

/*! Returns raw signing key private bytes from Keychain. */
- (nullable NSData *)signingKeyPrivateBytesWithError:(NSError **)error;



/*! Generates a new signing key. */
- (BOOL)generateSigningKeyWithError:(NSError **)error;

/*! Imports an existing signing key (raw private bytes). */
- (BOOL)importSigningKey:(NSData *)privateKey error:(NSError **)error;

/*! Whether signing keys should be persisted via the Keychain. Defaults to YES. */
@property (nonatomic, assign) BOOL useKeychainSigningKey;

/*! When YES (default), signing keys are protected with biometric authentication. */
@property (nonatomic, assign) BOOL useBiometricProtection;

/*! When YES, use Secure Enclave for key generation (macOS with T2/Apple Silicon). */
@property (nonatomic, assign) BOOL useSecureEnclave;

/*! Whether the Keychain needs upgrade to biometric protection. */
@property (nonatomic, assign, readonly) BOOL keychainNeedsUpgrade;

/*! Upgrades existing keys to use biometric protection. */
- (BOOL)upgradeKeychainToBiometricWithError:(NSError **)error;

- (void)setUseKeychainSigningKey:(BOOL)useKeychain;

// Internal methods for ServiceDatabases
- (sqlite3_stmt *)prepareStatement:(NSString *)sql error:(NSError **)error;
- (void)finalizeStatement:(sqlite3_stmt *)stmt;
- (PDSDatabaseAccount *)accountFromStatement:(sqlite3_stmt *)stmt;

@end

NS_ASSUME_NONNULL_END
