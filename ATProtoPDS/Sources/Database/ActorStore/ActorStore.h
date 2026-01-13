#import <Foundation/Foundation.h>
#if defined(__linux__) || defined(__GNUstep__)
#import <Security/Security.h>
#endif
#import <sqlite3.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSActorStore;
@class PDSDatabaseAccount;
@class PDSDatabaseRepo;
@class PDSDatabaseRecord;
@class PDSDatabaseBlock;
@class PDSDatabaseBlob;

extern NSString * const PDSActorStoreErrorDomain;

typedef NS_ENUM(NSInteger, PDSActorStoreError) {
    PDSActorStoreErrorNotFound = 1000,
    PDSActorStoreErrorAlreadyExists,
    PDSActorStoreErrorTransactionRequired,
    PDSActorStoreErrorDatabaseClosed,
    PDSActorStoreErrorSigningKeyNotFound,
    PDSActorStoreErrorSigningKeyInvalid,
};

@protocol PDSActorStoreReader <NSObject>

- (nullable PDSDatabaseAccount *)getAccountForDid:(NSString *)did error:(NSError **)error;
- (nullable NSArray<PDSDatabaseAccount *> *)getAllAccountsWithError:(NSError **)error;
- (nullable PDSDatabaseRepo *)getRepoForDid:(NSString *)did error:(NSError **)error;
- (nullable NSData *)getRepoRootForDid:(NSString *)did error:(NSError **)error;
- (nullable PDSDatabaseRecord *)getRecord:(NSString *)uri forDid:(NSString *)did error:(NSError **)error;
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

@protocol PDSActorStoreTransactor <NSObject>

- (BOOL)createAccount:(PDSDatabaseAccount *)account error:(NSError **)error;
- (BOOL)updateAccount:(PDSDatabaseAccount *)account error:(NSError **)error;
- (BOOL)deleteAccount:(NSString *)did error:(NSError **)error;

- (BOOL)createRepo:(PDSDatabaseRepo *)repo error:(NSError **)error;
- (BOOL)updateRepoRoot:(NSString *)did rootCid:(NSData *)rootCid error:(NSError **)error;
- (BOOL)deleteRepo:(NSString *)did error:(NSError **)error;

- (BOOL)putRecord:(PDSDatabaseRecord *)record forDid:(NSString *)did error:(NSError **)error;
- (BOOL)deleteRecord:(NSString *)uri forDid:(NSString *)did error:(NSError **)error;
- (BOOL)putRecords:(NSArray<PDSDatabaseRecord *> *)records forDid:(NSString *)did error:(NSError **)error;

- (BOOL)putBlock:(PDSDatabaseBlock *)block forDid:(NSString *)did error:(NSError **)error;
- (BOOL)putBlocks:(NSArray<PDSDatabaseBlock *> *)blocks forDid:(NSString *)did error:(NSError **)error;
- (BOOL)deleteBlock:(NSData *)cid forDid:(NSString *)did error:(NSError **)error;

@end

@interface PDSActorStore : NSObject <PDSActorStoreReader, PDSActorStoreTransactor>

@property (nonatomic, copy, readonly) NSString *did;
@property (nonatomic, copy, readonly) NSString *dbPath;
@property (nonatomic, assign, readonly, getter=isOpen) BOOL open;
@property (nonatomic, assign, readonly) sqlite3 *db;

+ (instancetype)storeWithDid:(NSString *)did 
                    dbPath:(NSString *)dbPath
                      error:(NSError **)error;

- (BOOL)openWithError:(NSError **)error;
- (void)close;

- (void)transactWithBlock:(void (^)(id<PDSActorStoreTransactor> transactor))block 
                    error:(NSError **)error;

- (void)readWithBlock:(void (^)(id<PDSActorStoreReader> reader))block 
                error:(NSError **)error;

- (nullable SecKeyRef)signingKeyWithError:(NSError **)error;
- (BOOL)storeSigningKey:(SecKeyRef)key error:(NSError **)error;
- (BOOL)generateSigningKeyWithError:(NSError **)error;

#pragma mark - Rotation Key Management (for did:plc)

/**
 * Store a rotation key encrypted with the given password.
 * @param privateKey The 32-byte secp256k1 private key
 * @param compressedPublicKey The 33-byte compressed public key
 * @param password The password to derive encryption key from
 * @param error Error output
 * @return YES on success
 */
- (BOOL)storeRotationKeyPrivate:(NSData *)privateKey
                     publicKey:(NSData *)compressedPublicKey
              encryptedWithPassword:(NSString *)password
                          error:(NSError **)error;

/**
 * Retrieve the rotation key decrypted with the given password.
 * @param password The password to derive decryption key from
 * @param error Error output
 * @return The 32-byte private key, or nil on error
 */
- (nullable NSData *)rotationKeyDecryptedWithPassword:(NSString *)password
                                               error:(NSError **)error;

/**
 * Get the compressed public key for the rotation key (no password needed).
 * @param error Error output
 * @return The 33-byte compressed public key, or nil if not stored
 */
- (nullable NSData *)rotationKeyCompressedPublicKeyWithError:(NSError **)error;

/**
 * Check if a rotation key is stored.
 */
- (BOOL)hasRotationKey;

// Internal methods for ServiceDatabases
- (sqlite3_stmt *)prepareStatement:(NSString *)sql error:(NSError **)error;
- (void)finalizeStatement:(sqlite3_stmt *)stmt;
- (PDSDatabaseAccount *)accountFromStatement:(sqlite3_stmt *)stmt;

@end

NS_ASSUME_NONNULL_END
