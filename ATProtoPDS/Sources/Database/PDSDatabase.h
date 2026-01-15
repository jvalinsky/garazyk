#import <Foundation/Foundation.h>
#import <sqlite3.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Error domain for PDSDatabase errors.
 */
extern NSString * const PDSDatabaseErrorDomain;

/**
 * Error codes for PDSDatabase operations.
 *
 * @note All errors in the range 1000-1999 are reserved for database errors.
 */
typedef NS_ENUM(NSInteger, PDSDatabaseError) {
    /** The database connection is not open. */
    PDSDatabaseErrorNotOpen = 1000,
    /** A SQL query failed to execute. */
    PDSDatabaseErrorQueryFailed = 1001,
    /** Database schema migration failed. */
    PDSDatabaseErrorMigrationFailed = 1002,
    /** A database constraint was violated. */
    PDSDatabaseErrorConstraintViolation = 1003,
    /** The requested resource was not found in the database. */
    PDSDatabaseErrorNotFound = 1004,
};

/// @file PDSDatabase.h
/// @brief Core database interface for the ATProto Personal Data Server.
///
/// The PDSDatabase class provides a SQLite-based storage interface for managing
/// ATProto data including accounts, repositories, records, blocks, and blobs.
/// This class handles database connection management, raw SQL execution, and
/// transaction support.

@interface PDSDatabase : NSObject

/// The file URL pointing to the SQLite database file.
@property (nonatomic, readonly) NSURL *databaseURL;

/// A boolean indicating whether the database connection is currently open.
@property (nonatomic, readonly) BOOL isOpen;

/**
 * Creates and returns a new database instance at the specified file URL.
 *
 * @param url The file URL where the SQLite database is or should be located.
 * @return A newly initialized PDSDatabase instance.
 */
+ (instancetype)databaseAtURL:(NSURL *)url;

/**
 * Opens the database connection.
 *
 * @param error On return, contains an error object if the database failed to open.
 * @return YES if the database opened successfully, otherwise NO.
 */
- (BOOL)openWithError:(NSError **)error;

/// Closes the database connection.
- (void)close;

/**
 * Executes a raw SQL statement that does not return results.
 *
 * @param sql The SQL statement to execute.
 * @param error On return, contains an error object if the query failed.
 * @return YES if the SQL executed successfully, otherwise NO.
 */
- (BOOL)executeRawSQL:(NSString *)sql error:(NSError **)error;

/**
 * Executes a SQL query that returns results.
 *
 * @param sql The SQL query to execute.
 * @param error On return, contains an error object if the query failed.
 * @return An array of dictionaries representing the query results, or nil on failure.
 */
- (NSArray<NSDictionary *> *)executeQuery:(NSString *)sql error:(NSError **)error;

@end

/// @brief Represents an ATProto account stored in the database.
///
/// The PDSDatabaseAccount class models user account information including
/// authentication credentials and metadata.

@interface PDSDatabaseAccount : NSObject

/// The decentralized identifier (DID) for the account.
@property (nonatomic, copy) NSString *did;

/// The handle associated with the account.
@property (nonatomic, copy) NSString *handle;

/// The email address associated with the account, if available.
@property (nonatomic, copy, nullable) NSString *email;

/// The hashed password, if password authentication is enabled.
@property (nonatomic, copy, nullable) NSData *passwordHash;

/// The salt used for password hashing, if applicable.
@property (nonatomic, copy, nullable) NSData *passwordSalt;

/// The access JWT token for session authentication.
@property (nonatomic, copy, nullable) NSData *accessJwt;

/// The refresh JWT token for session renewal.
@property (nonatomic, copy, nullable) NSData *refreshJwt;

/// The timestamp when the account was created.
@property (nonatomic, assign) NSTimeInterval createdAt;

/// The timestamp when the account was last updated.
@property (nonatomic, assign) NSTimeInterval updatedAt;

@end

/// @brief Represents an ATProto repository stored in the database.
///
/// The PDSDatabaseRepo class models repository information including the root
/// CID and collection metadata.

@interface PDSDatabaseRepo : NSObject

/// The DID of the repository owner.
@property (nonatomic, copy) NSString *ownerDid;

/// The CID of the repository root block.
@property (nonatomic, copy) NSData *rootCid;

/// The serialized collection data, if available.
@property (nonatomic, copy, nullable) NSData *collectionData;

/// The date when the repository was created.
@property (nonatomic, strong) NSDate *createdAt;

/// The date when the repository was last updated.
@property (nonatomic, strong) NSDate *updatedAt;

@end

/// @brief Represents an ATProto record stored in the database.
///
/// The PDSDatabaseRecord class models individual records within repositories.

@interface PDSDatabaseRecord : NSObject

/// The URI identifying the record.
@property (nonatomic, copy) NSString *uri;

/// The DID of the record owner.
@property (nonatomic, copy) NSString *did;

/// The collection namespace for the record.
@property (nonatomic, copy) NSString *collection;

/// The record key within the collection.
@property (nonatomic, copy) NSString *rkey;

/// The CID of the record content.
@property (nonatomic, copy) NSString *cid;

/// The date when the record was created.
@property (nonatomic, strong) NSDate *createdAt;

@end

/// @brief Represents a data block stored in the database.
///
/// The PDSDatabaseBlock class models IPFS blocks stored locally for repository
/// operations and content-addressed storage.

@interface PDSDatabaseBlock : NSObject

/// The content identifier (CID) of the block.
@property (nonatomic, copy) NSData *cid;

/// The DID of the repository owning this block.
@property (nonatomic, copy) NSString *repoDid;

/// The actual block data content.
@property (nonatomic, copy, nullable) NSData *blockData;

/// The content type of the block data.
@property (nonatomic, copy, nullable) NSString *contentType;

/// The size of the block in bytes.
@property (nonatomic, assign) NSInteger size;

/// The date when the block was created.
@property (nonatomic, strong) NSDate *createdAt;

@end

/// @brief Represents a blob stored in the database.
///
/// The PDSDatabaseBlob class models blob metadata for user-uploaded content
/// such as images and other binary files.

@interface PDSDatabaseBlob : NSObject

/// The content identifier (CID) of the blob.
@property (nonatomic, copy) NSData *cid;

/// The DID of the blob owner.
@property (nonatomic, copy) NSString *did;

/// The MIME type of the blob content.
@property (nonatomic, copy, nullable) NSString *mimeType;

/// The size of the blob in bytes.
@property (nonatomic, assign) NSInteger size;

/// The date when the blob was created.
@property (nonatomic, strong) NSDate *createdAt;

@end

/// @brief Account management category for PDSDatabase.
///
/// Provides methods for creating, retrieving, updating, and deleting accounts
/// in the database.

@interface PDSDatabase (Accounts)

/**
 * Creates a new account in the database.
 *
 * @param account The account object to create.
 * @param error On return, contains an error object if the operation failed.
 * @return YES if the account was created successfully, otherwise NO.
 */
- (BOOL)createAccount:(PDSDatabaseAccount *)account error:(NSError **)error;

/**
 * Updates an existing account in the database.
 *
 * @param account The account object with updated values.
 * @param error On return, contains an error object if the operation failed.
 * @return YES if the account was updated successfully, otherwise NO.
 */
- (BOOL)updateAccount:(PDSDatabaseAccount *)account error:(NSError **)error;

/**
 * Retrieves an account by its DID.
 *
 * @param did The DID to search for.
 * @param error On return, contains an error object if the operation failed.
 * @return The matching account, or nil if not found or an error occurred.
 */
- (nullable PDSDatabaseAccount *)getAccountByDid:(NSString *)did error:(NSError **)error;

/**
 * Retrieves an account by its handle.
 *
 * @param handle The handle to search for.
 * @param error On return, contains an error object if the operation failed.
 * @return The matching account, or nil if not found or an error occurred.
 */
- (nullable PDSDatabaseAccount *)getAccountByHandle:(NSString *)handle error:(NSError **)error;

/**
 * Retrieves an account by its email address.
 *
 * @param email The email address to search for.
 * @param error On return, contains an error object if the operation failed.
 * @return The matching account, or nil if not found or an error occurred.
 */
- (nullable PDSDatabaseAccount *)getAccountByEmail:(NSString *)email error:(NSError **)error;

/**
 * Retrieves an account by its refresh token.
 *
 * @param refreshToken The refresh token string to search for.
 * @param error On return, contains an error object if the operation failed.
 * @return The matching account, or nil if not found or an error occurred.
 */
- (nullable PDSDatabaseAccount *)getAccountByRefreshToken:(NSString *)refreshToken error:(NSError **)error;

/**
 * Updates an existing account in the database.
 *
 * @param account The account object with updated values.
 * @param error On return, contains an error object if the operation failed.
 * @return YES if the account was updated successfully, otherwise NO.
 * @deprecated Use updateAccount:error: instead.
 */
- (BOOL)updateAccount:(PDSDatabaseAccount *)account error:(NSError **)error;

/**
 * Retrieves all accounts from the database.
 *
 * @param error On return, contains an error object if the operation failed.
 * @return An array of all accounts, or nil on failure.
 */
- (NSArray<PDSDatabaseAccount *> *)getAllAccountsWithError:(NSError **)error;

/**
 * Deletes an account by its DID.
 *
 * @param did The DID of the account to delete.
 * @param error On return, contains an error object if the operation failed.
 * @return YES if the account was deleted successfully, otherwise NO.
 */
- (BOOL)deleteAccount:(NSString *)did error:(NSError **)error;

@end

/// @brief Repository management category for PDSDatabase.
///
/// Provides methods for creating, retrieving, updating, and deleting repositories
/// in the database.

@interface PDSDatabase (Repos)

/**
 * Creates a new repository in the database.
 *
 * @param repo The repository object to create.
 * @param error On return, contains an error object if the operation failed.
 * @return YES if the repository was created successfully, otherwise NO.
 */
- (BOOL)createRepo:(PDSDatabaseRepo *)repo error:(NSError **)error;

/**
 * Updates the root CID of an existing repository.
 *
 * @param ownerDid The DID of the repository owner.
 * @param rootCid The new root CID.
 * @param error On return, contains an error object if the operation failed.
 * @return YES if the root was updated successfully, otherwise NO.
 */
- (BOOL)updateRepoRoot:(NSString *)ownerDid rootCid:(NSData *)rootCid error:(NSError **)error;

/**
 * Retrieves a repository by owner DID.
 *
 * @param did The DID of the repository owner.
 * @param error On return, contains an error object if the operation failed.
 * @return The matching repository, or nil if not found or an error occurred.
 */
- (nullable PDSDatabaseRepo *)getRepoForDid:(NSString *)did error:(NSError **)error;

/**
 * Retrieves all repositories from the database.
 *
 * @param error On return, contains an error object if the operation failed.
 * @return An array of all repositories, or nil on failure.
 */
- (NSArray<PDSDatabaseRepo *> *)getAllReposWithError:(NSError **)error;

/**
 * Deletes a repository by owner DID.
 *
 * @param ownerDid The DID of the repository owner.
 * @param error On return, contains an error object if the operation failed.
 * @return YES if the repository was deleted successfully, otherwise NO.
 */
- (BOOL)deleteRepo:(NSString *)ownerDid error:(NSError **)error;

@end

/// @brief Record management category for PDSDatabase.
///
/// Provides methods for saving and retrieving records from repositories.

@interface PDSDatabase (Records)

/**
 * Saves a record to the database.
 *
 * @param record The record object to save.
 * @param error On return, contains an error object if the operation failed.
 * @return YES if the record was saved successfully, otherwise NO.
 */
- (BOOL)saveRecord:(PDSDatabaseRecord *)record error:(NSError **)error;

/**
 * Retrieves a record by its URI.
 *
 * @param uri The URI of the record to retrieve.
 * @param error On return, contains an error object if the operation failed.
 * @return The matching record, or nil if not found or an error occurred.
 */
- (nullable PDSDatabaseRecord *)getRecord:(NSString *)uri error:(NSError **)error;

/**
 * Retrieves all records for a given DID and optional collection.
 *
 * @param did The DID of the record owner.
 * @param collection The optional collection filter. Pass nil for all collections.
 * @param error On return, contains an error object if the operation failed.
 * @return An array of matching records, or nil on failure.
 */
- (NSArray<PDSDatabaseRecord *> *)getRecordsForDid:(NSString *)did collection:(nullable NSString *)collection error:(NSError **)error;

@end

/// @brief Block storage category for PDSDatabase.
///
/// Provides methods for saving and retrieving content blocks including
/// batch operations and counting.

@interface PDSDatabase (Blocks)

/**
 * Saves a single block to the database.
 *
 * @param block The block object to save.
 * @param error On return, contains an error object if the operation failed.
 * @return YES if the block was saved successfully, otherwise NO.
 */
- (BOOL)saveBlock:(PDSDatabaseBlock *)block error:(NSError **)error;

/**
 * Saves multiple blocks to the database in a single operation.
 *
 * @param blocks An array of block objects to save.
 * @param error On return, contains an error object if the operation failed.
 * @return YES if all blocks were saved successfully, otherwise NO.
 */
- (BOOL)saveBlocks:(NSArray<PDSDatabaseBlock *> *)blocks error:(NSError **)error;

/**
 * Retrieves a block by its CID and repository DID.
 *
 * @param cid The CID of the block to retrieve.
 * @param repoDid The DID of the repository owning the block.
 * @param error On return, contains an error object if the operation failed.
 * @return The matching block, or nil if not found or an error occurred.
 */
- (nullable PDSDatabaseBlock *)getBlockWithCid:(NSData *)cid repoDid:(NSString *)repoDid error:(NSError **)error;

/**
 * Retrieves blocks for a repository with pagination.
 *
 * @param repoDid The DID of the repository.
 * @param limit The maximum number of blocks to return.
 * @param offset The number of blocks to skip.
 * @param error On return, contains an error object if the operation failed.
 * @return An array of matching blocks, or nil on failure.
 */
- (NSArray<PDSDatabaseBlock *> *)getBlocksForRepo:(NSString *)repoDid limit:(NSInteger)limit offset:(NSInteger)offset error:(NSError **)error;

/**
 * Counts the total number of blocks in a repository.
 *
 * @param repoDid The DID of the repository.
 * @param error On return, contains an error object if the operation failed.
 * @return The block count, or -1 on failure.
 */
- (NSInteger)getBlockCountForRepo:(NSString *)repoDid error:(NSError **)error;

/**
 * Deletes a block by its CID and repository DID.
 *
 * @param cid The CID of the block to delete.
 * @param repoDid The DID of the repository owning the block.
 * @param error On return, contains an error object if the operation failed.
 * @return YES if the block was deleted successfully, otherwise NO.
 */
- (BOOL)deleteBlock:(NSData *)cid repoDid:(NSString *)repoDid error:(NSError **)error;

@end

/// @brief Blob storage category for PDSDatabase.
///
/// Provides methods for managing blob metadata and content references.

@interface PDSDatabase (Blobs)

/**
 * Saves a blob to the database.
 *
 * @param blob The blob object to save.
 * @param error On return, contains an error object if the operation failed.
 * @return YES if the blob was saved successfully, otherwise NO.
 */
- (BOOL)saveBlob:(PDSDatabaseBlob *)blob error:(NSError **)error;

/**
 * Retrieves a blob by its CID.
 *
 * @param cid The CID of the blob to retrieve.
 * @param error On return, contains an error object if the operation failed.
 * @return The matching blob, or nil if not found or an error occurred.
 */
- (nullable PDSDatabaseBlob *)getBlobWithCid:(NSData *)cid error:(NSError **)error;

/**
 * Retrieves blobs for a given DID with pagination.
 *
 * @param did The DID of the blob owner.
 * @param limit The maximum number of blobs to return.
 * @param offset The number of blobs to skip.
 * @param error On return, contains an error object if the operation failed.
 * @return An array of matching blobs, or nil on failure.
 */
- (NSArray<PDSDatabaseBlob *> *)getBlobsForDid:(NSString *)did limit:(NSInteger)limit offset:(NSInteger)offset error:(NSError **)error;

/**
 * Counts the total number of blobs for a given DID.
 *
 * @param did The DID of the blob owner.
 * @param error On return, contains an error object if the operation failed.
 * @return The blob count, or -1 on failure.
 */
- (NSInteger)getBlobCountForDid:(NSString *)did error:(NSError **)error;

/**
 * Deletes a blob by its CID.
 *
 * @param cid The CID of the blob to delete.
 * @param error On return, contains an error object if the operation failed.
 * @return YES if the blob was deleted successfully, otherwise NO.
 */
- (BOOL)deleteBlob:(NSData *)cid error:(NSError **)error;

@end

/// @brief Transaction management category for PDSDatabase.
///
/// Provides methods for managing database transactions for atomic operations.

@interface PDSDatabase (Transactions)

/**
 * Begins a database transaction.
 *
 * @param error On return, contains an error object if the transaction could not begin.
 * @return YES if the transaction began successfully, otherwise NO.
 */
- (BOOL)beginTransactionWithError:(NSError **)error;

/**
 * Commits the current transaction.
 *
 * @param error On return, contains an error object if the transaction could not commit.
 * @return YES if the transaction committed successfully, otherwise NO.
 */
- (BOOL)commitTransactionWithError:(NSError **)error;

/**
 * Rolls back the current transaction.
 *
 * @param error On return, contains an error object if the transaction could not roll back.
 * @return YES if the transaction rolled back successfully, otherwise NO.
 */
- (BOOL)rollbackTransactionWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
