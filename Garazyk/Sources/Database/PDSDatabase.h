#import <Foundation/Foundation.h>
#import <sqlite3.h>
#import "PDSBlock.h"
#import "PDSQueryDatabase.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @header PDSDatabase.h
 @abstract Database layer for ATProto PDS persistence.
 @discussion This header defines the core database interface for persisting
 ATProto data including accounts, repositories, records, blocks, and blobs.
 Uses SQLite for local storage with transactions and migrations.
 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

extern NSString * const PDSDatabaseErrorDomain;

/*! Error codes for PDSDatabase. */
typedef NS_ENUM(NSInteger, PDSDatabaseError) {
    PDSDatabaseErrorNotOpen = 1000,
    PDSDatabaseErrorQueryFailed = 1001,
    PDSDatabaseErrorMigrationFailed = 1002,
    PDSDatabaseErrorConstraintViolation = 1003,
    PDSDatabaseErrorNotFound = 1004,
};

/*!
 @class PDSDatabase
 @abstract Manages the PDS SQLite database.
 */
@interface PDSDatabase : NSObject <PDSQueryDatabase>

/*! The URL path to the SQLite database file. */
@property (nonatomic, readonly) NSURL *databaseURL;

/*! YES if the database connection is currently open. */
@property (nonatomic, readonly) BOOL isOpen;

/*!
 @method databaseAtURL:
 
 @abstract Creates a database instance at the specified file path.
 
 @param url The file URL where the SQLite database should be located or created.
 @return An initialized PDSDatabase instance.
 */
+ (instancetype)databaseAtURL:(NSURL *)url;

/*!
 @method sharedDatabase
 
 @abstract Returns the shared singleton database instance.
 
 @return The shared PDSDatabase instance.
 */
+ (instancetype)sharedDatabase;


/*!
 @method openWithError:
 
 @abstract Opens the database connection and runs any pending migrations.
 
 @param error On return, contains an error if the operation failed.
 @return YES if the database opened successfully, NO otherwise.
 */
- (BOOL)openWithError:(NSError **)error;

/*!
 @method close
 
 @abstract Closes the database connection.
 */
- (void)close;

/*!
 @method executeRawSQL:error:
 
 @abstract Executes a raw SQL statement.
 
 @discussion Use this method for custom SQL operations that don't have
 dedicated methods. The statement should be a single command (not a query)
 if expecting no results.
 
 @param sql The SQL statement to execute.
 @param error On return, contains an error if the operation failed.
 @return YES if the statement executed successfully, NO otherwise.
 */
- (BOOL)executeRawSQL:(NSString *)sql error:(NSError **)error;

/*!
 @method executeQuery:error:
 
 @abstract Executes a SQL query and returns results.
 
 @param sql The SQL query to execute.
 @param error On return, contains an error if the query failed.
 @return An array of dictionaries representing query results, or nil on failure.
 */
- (NSArray<NSDictionary *> *)executeQuery:(NSString *)sql error:(NSError **)error;

/*!
 @method executeParameterizedQuery:params:error:
 
 @abstract Executes a SQL query with parameterized values.
 
 @discussion This is the RECOMMENDED method for executing queries with user-provided
 values. It uses SQLite parameter binding to prevent SQL injection attacks.
 
 @param sql The SQL query with ? placeholders for parameters.
 @param params An array of parameter values to bind to the query.
 @param error On return, contains an error if the query failed.
 @return An array of dictionaries representing query results, or nil on failure.
 */
- (NSArray<NSDictionary *> *)executeParameterizedQuery:(NSString *)sql
                                                params:(NSArray *)params
                                                 error:(NSError **)error;

/*!
 @method executeParameterizedUpdate:params:error:
 
 @abstract Executes a parameterized SQL statement (INSERT, UPDATE, DELETE).
 
 @param sql The SQL statement with ? placeholders for parameters.
 @param params An array of parameter values to bind to the statement.
 @param error On return, contains an error if the statement failed.
 @return YES if the statement executed successfully, NO otherwise.
 */
- (BOOL)executeParameterizedUpdate:(NSString *)sql
                            params:(NSArray *)params
                             error:(NSError **)error;

/*!
 @method preparedStatementForQuery:

 @abstract Returns a cached prepared statement for the given SQL query.

 @discussion
    This method is intended for internal diagnostics and tests that validate
    statement-cache behavior. The returned statement is reset before reuse.

 @param query SQL query text used as the statement cache key.
 @return A prepared SQLite statement, or NULL on prepare failure.
 */
- (sqlite3_stmt *)preparedStatementForQuery:(NSString *)query;

/*!
 @method getClientWithID:error:
 
 @abstract Retrieves an OAuth client by ID.
 
 @param clientID The client ID to search for.
 @param error On return, contains an error if the operation failed.
 @return The client dictionary, or nil if not found.
 */
- (NSDictionary *)getClientWithID:(NSString *)clientID error:(NSError **)error;

/*!
 @method createClient:error:
 
 @abstract Creates or updates an OAuth client.
 
 @param client The client details dictionary.
 @param error On return, contains an error if the operation failed.
 @return YES if the client was created successfully, NO otherwise.
 */
- (BOOL)createClient:(NSDictionary *)client error:(NSError **)error;

/*!
 @method seedTestClient:
  
 @abstract Creates a test client for development/testing.
  
 @param error On return, contains an error if the operation failed.
 @return YES if the test client was created successfully, NO otherwise.
 */
- (BOOL)seedTestClient:(NSError **)error;

/*!
 @method getAllOAuthClients:
  
 @abstract Retrieves all registered OAuth clients.
  
 @param error On return, contains an error if the operation failed.
 @return An array of client dictionaries, or nil on error.
 */
- (nullable NSArray<NSDictionary *> *)getAllOAuthClientsWithError:(NSError **)error;

/*!
 @method deleteOAuthClientWithID:error:
  
 @abstract Deletes an OAuth client by ID.
  
 @param clientID The client ID to delete.
 @param error On return, contains an error if the operation failed.
 @return YES if the client was deleted, NO otherwise.
 */
- (BOOL)deleteOAuthClientWithID:(NSString *)clientID error:(NSError **)error;

@end

/*!
 @class PDSDatabaseAccount
 
 @abstract Represents a PDS account record in the database.
 
 @discussion This class models account data stored in the database, including
 identity information (DID, handle, email), credentials (password hash, JWT tokens),
 and metadata (creation time, invite status).
 
 @see PDSDatabase (Accounts)
 */
@interface PDSDatabaseAccount : NSObject

/*! The decentralized identifier (DID) for this account. */
@property (nonatomic, copy) NSString *did;

/*! The handle (username) for this account. */
@property (nonatomic, copy) NSString *handle;

/*! Optional email address for password recovery and notifications. */
@property (nonatomic, copy, nullable) NSString *email;

/*! Bcrypt hash of the account password. */
@property (nonatomic, copy, nullable) NSData *passwordHash;

/*! Salt used for password hashing. */
@property (nonatomic, copy, nullable) NSData *passwordSalt;

/*! JWT access token for API authentication. */
@property (nonatomic, copy, nullable) NSData *accessJwt;

/*! JWT refresh token for obtaining new access tokens. */
@property (nonatomic, copy, nullable) NSData *refreshJwt;

/*! Unix timestamp when the account was created. */
@property (nonatomic, assign) NSTimeInterval createdAt;

/*! Unix timestamp when the account was last updated. */
@property (nonatomic, assign) NSTimeInterval updatedAt;

/*! Whether invite codes are enabled for this account. */
@property (nonatomic, assign) BOOL inviteEnabled;

/*! Whether 2FA (TOTP/Passkey) is enabled. */
@property (nonatomic, assign) BOOL tfaEnabled;

/*! Whether WebAuthn is enabled for this account. */
@property (nonatomic, assign) BOOL webauthnEnabled;

/*! Encrypted TOTP secret or other 2FA secret data. */
@property (nonatomic, copy, nullable) NSData *tfaSecret;

/*! JSON array of hashed recovery codes. */
@property (nonatomic, copy, nullable) NSData *recoveryCodes;

/*! Age assurance level. */
@property (nonatomic, copy, nullable) NSString *ageAssurance;

/*! Timestamp when age was verified. */
@property (nonatomic, copy, nullable) NSString *ageVerifiedAt;

@end

/*!
 @class PDSDatabaseRepo
 
 @abstract Represents a repository in the database.
 
 @discussion A repository contains a user's collection of records and blocks.
 Each repository is identified by its owner's DID and has a current root CID
 representing the state of the Merkle Search Tree.
 
 @see PDSDatabase (Repos)
 */
@interface PDSDatabaseRepo : NSObject

/*! The DID of the repository owner. */
@property (nonatomic, copy) NSString *ownerDid;

/*! The current root CID of the repository's Merkle Search Tree. */
@property (nonatomic, copy) NSData *rootCid;

/*! Optional serialized collection index data. */
@property (nonatomic, copy, nullable) NSData *collectionData;

/*! Date when the repository was created. */
@property (nonatomic, strong) NSDate *createdAt;

/*! Date when the repository was last updated. */
@property (nonatomic, strong) NSDate *updatedAt;

@end

/*!
 @class PDSDatabaseRecord
 
 @abstract Represents a single record in a repository.
 
 @discussion Records are the fundamental data units in ATProto repositories.
 Each record is identified by a URI (repo DID + collection + rkey) and has
 an associated CID for content-addressable retrieval.
 
 @see PDSDatabase (Records)
 */
@interface PDSDatabaseRecord : NSObject

/*! The AT-URI identifying this record (e.g., at://did:plc:z.../app.bsky.actor.profile/self). */
@property (nonatomic, copy) NSString *uri;

/*! The DID of the repository that contains this record. */
@property (nonatomic, copy) NSString *did;

/*! The collection namespace for this record (e.g., app.bsky.actor.profile). */
@property (nonatomic, copy) NSString *collection;

/*! The record key within the collection. */
@property (nonatomic, copy) NSString *rkey;

/*! The CID of the record content. */
@property (nonatomic, copy) NSString *cid;

/*! Date when the record was created. */
@property (nonatomic, strong) NSDate *createdAt;

/*! The raw value of the record (JSON string). */
@property (nonatomic, copy, nullable) NSString *value;

/*! Revision TID when this record was last written. */
@property (nonatomic, copy, nullable) NSString *rev;

/*! The subject DID for relationship records (e.g. follow target). */
@property (nonatomic, copy, nullable) NSString *subjectDid;

@end

/*!
 @class PDSDatabaseBlob
 
 @abstract Represents a blob reference stored in the database.
 
 @discussion Blobs are large binary data attachments stored separately from
 repository blocks. This class tracks blob metadata for retrieval and quota
 management.
 
 @see PDSDatabase (Blobs)
 */
@interface PDSDatabaseBlob : NSObject

/*! The CID of the blob. */
@property (nonatomic, copy) NSData *cid;

/*! The DID of the account that uploaded this blob. */
@property (nonatomic, copy) NSString *did;

/*! The MIME type of the blob content. */
@property (nonatomic, copy, nullable) NSString *mimeType;

/*! The size of the blob in bytes. */
@property (nonatomic, assign) NSInteger size;

/*! Date when the blob was uploaded. */
@property (nonatomic, strong) NSDate *createdAt;

@end

/*!
 @category PDSDatabase (Accounts)
 
 @abstract Account management methods for PDSDatabase.
 
 @discussion These methods provide CRUD operations for PDS accounts.
 Accounts represent user identities on the PDS and contain authentication
 credentials and metadata.
 */
@interface PDSDatabase (Accounts)

/*!
 @method createAccount:error:
 
 @abstract Creates a new account in the database.
 
 @param account The account object containing account details.
 @param error On return, contains an error if the operation failed.
 @return YES if the account was created successfully, NO otherwise.
 */
- (BOOL)createAccount:(PDSDatabaseAccount *)account error:(NSError **)error;

/*!
 @method updateAccount:error:
 
 @abstract Updates an existing account in the database.
 
 @param account The account object with updated values.
 @param error On return, contains an error if the operation failed.
 @return YES if the account was updated successfully, NO otherwise.
 */
- (BOOL)updateAccount:(PDSDatabaseAccount *)account error:(NSError **)error;

/*!
 @method getAccountByDid:error:
 
 @abstract Retrieves an account by its DID.
 
 @param did The DID to search for.
 @param error On return, contains an error if the operation failed.
 @return The account object, or nil if not found.
 */
- (nullable PDSDatabaseAccount *)getAccountByDid:(NSString *)did error:(NSError **)error;

/*!
 @method getAccountByHandle:error:
 
 @abstract Retrieves an account by its handle.
 
 @param handle The handle to search for (e.g., "alice.test").
 @param error On return, contains an error if the operation failed.
 @return The account object, or nil if not found.
 */
- (nullable PDSDatabaseAccount *)getAccountByHandle:(NSString *)handle error:(NSError **)error;

/*!
 @method getAccountByEmail:error:
 
 @abstract Retrieves an account by its email address.
 
 @param email The email address to search for.
 @param error On return, contains an error if the operation failed.
 @return The account object, or nil if not found.
 */
- (nullable PDSDatabaseAccount *)getAccountByEmail:(NSString *)email error:(NSError **)error;

/*!
 @method getAccountByRefreshToken:error:
 
 @abstract Retrieves an account by its refresh token.
 
 @param refreshToken The refresh token string to search for.
 @param error On return, contains an error if the operation failed.
 @return The account object, or nil if not found.
 */
- (nullable PDSDatabaseAccount *)getAccountByRefreshToken:(NSString *)refreshToken error:(NSError **)error;

/*!
 @method getAllAccountsWithError:
 
 @abstract Retrieves all accounts in the database.
 
 @param error On return, contains an error if the operation failed.
 @return An array of all account objects.
 */
- (NSArray<PDSDatabaseAccount *> *)getAllAccountsWithError:(NSError **)error;

/*!
 @method getAccountsWithLimit:afterDid:error:

 @abstract Retrieves a page of accounts ordered by DID ascending (keyset pagination).

 @param limit Maximum number of accounts to return.
 @param afterDid Exclusive lower bound on DID for the next page, or nil for the first page.
 @param error On return, contains an error if the operation failed.
 @return An array of account objects.
 */
- (NSArray<PDSDatabaseAccount *> *)getAccountsWithLimit:(NSInteger)limit afterDid:(nullable NSString *)afterDid error:(NSError **)error;

/*!
 @method deleteAccount:error:

 @abstract Deletes an account and all associated data.

 @param did The DID of the account to delete.
 @param error On return, contains an error if the operation failed.
 @return YES if the account was deleted successfully, NO otherwise.
 */
- (BOOL)deleteAccount:(NSString *)did error:(NSError **)error;

@end

/*!
 @category PDSDatabase (Repos)
 
 @abstract Repository management methods for PDSDatabase.
 
 @discussion These methods provide CRUD operations for user repositories.
 Repositories contain collections of records organized in a Merkle Search Tree.
 */
@interface PDSDatabase (Repos)

/*!
 @method createRepo:error:
 
 @abstract Creates a new repository.
 
 @param repo The repository object containing owner and initial state.
 @param error On return, contains an error if the operation failed.
 @return YES if the repository was created successfully, NO otherwise.
 */
- (BOOL)createRepo:(PDSDatabaseRepo *)repo error:(NSError **)error;

/*!
 @method updateRepoRoot:rootCid:error:
 
 @abstract Updates the root CID of a repository.
 
 @discussion This method updates the repository's Merkle Search Tree root
 after a commit operation.
 
 @param ownerDid The DID of the repository owner.
 @param rootCid The new root CID.
 @param error On return, contains an error if the operation failed.
 @return YES if the root was updated successfully, NO otherwise.
 */
- (BOOL)updateRepoRoot:(NSString *)ownerDid rootCid:(NSData *)rootCid error:(NSError **)error;

/*!
 @method getRepoForDid:error:
 
 @abstract Retrieves a repository by owner DID.
 
 @param did The DID of the repository owner.
 @param error On return, contains an error if the operation failed.
 @return The repository object, or nil if not found.
 */
- (nullable PDSDatabaseRepo *)getRepoForDid:(NSString *)did error:(NSError **)error;

/*!
 @method getAllReposWithError:
 
 @abstract Retrieves all repositories.
 
 @param error On return, contains an error if the operation failed.
 @return An array of all repository objects.
 */
- (NSArray<PDSDatabaseRepo *> *)getAllReposWithError:(NSError **)error;

/*!
 @method deleteRepo:error:
 
 @abstract Deletes a repository and all its records and blocks.
 
 @param ownerDid The DID of the repository owner.
 @param error On return, contains an error if the operation failed.
 @return YES if the repository was deleted successfully, NO otherwise.
 */
- (BOOL)deleteRepo:(NSString *)ownerDid error:(NSError **)error;

@end

/*!
 @category PDSDatabase (Records)
 
 @abstract Record CRUD methods for PDSDatabase.
 
 @discussion These methods provide operations for managing individual records
 within repositories. Records are identified by AT-URIs and contain typed content.
 */
@interface PDSDatabase (Records)

/*!
 @method saveRecord:error:
 
 @abstract Saves or updates a record in the database.
 
 @param record The record object to save.
 @param error On return, contains an error if the operation failed.
 @return YES if the record was saved successfully, NO otherwise.
 */
- (BOOL)saveRecord:(PDSDatabaseRecord *)record error:(NSError **)error;

/*!
 @method getRecord:error:
 
 @abstract Retrieves a record by its URI.
 
 @param uri The AT-URI of the record.
 @param error On return, contains an error if the operation failed.
 @return The record object, or nil if not found.
 */
- (nullable PDSDatabaseRecord *)getRecord:(NSString *)uri error:(NSError **)error;

/*!
 @method getRecordsForDid:collection:error:
 
 @abstract Retrieves records from a repository.
 
 @param did The DID of the repository owner.
 @param collection Optional collection filter (e.g., app.bsky.actor.profile).
 @param error On return, contains an error if the operation failed.
 @return An array of matching record objects.
 */
- (NSArray<PDSDatabaseRecord *> *)getRecordsForDid:(NSString *)did collection:(nullable NSString *)collection error:(NSError **)error;

@end

/*!
 @category PDSDatabase (Blocks)
 
 @abstract Block storage methods for PDSDatabase.
 
 @discussion These methods manage CAR blocks stored in the repository.
 Blocks contain serialized content indexed by their CID.
 */
@interface PDSDatabase (Blocks)

/*!
 @method saveBlock:error:
 
 @abstract Saves a single block to the database.
 
 @param block The block object to save.
 @param error On return, contains an error if the operation failed.
 @return YES if the block was saved successfully, NO otherwise.
 */
- (BOOL)saveBlock:(PDSDatabaseBlock *)block error:(NSError **)error;

/*!
 @method saveBlocks:error:
 
 @abstract Saves multiple blocks in a batch operation.
 
 @param blocks An array of blocks to save.
 @param error On return, contains an error if the operation failed.
 @return YES if all blocks were saved successfully, NO otherwise.
 */
- (BOOL)saveBlocks:(NSArray<PDSDatabaseBlock *> *)blocks error:(NSError **)error;

/*!
 @method getBlockWithCid:repoDid:error:
 
 @abstract Retrieves a block by CID.
 
 @param cid The CID of the block.
 @param repoDid The DID of the repository that owns the block.
 @param error On return, contains an error if the operation failed.
 @return The block object, or nil if not found.
 */
- (nullable PDSDatabaseBlock *)getBlockWithCid:(NSData *)cid repoDid:(NSString *)repoDid error:(NSError **)error;

/*!
 @method getBlocksForRepo:limit:offset:error:
 
 @abstract Retrieves blocks from a repository with pagination.
 
 @param repoDid The DID of the repository.
 @param limit Maximum number of blocks to return.
 @param offset Number of blocks to skip.
 @param error On return, contains an error if the operation failed.
 @return An array of block objects.
 */
- (NSArray<PDSDatabaseBlock *> *)getBlocksForRepo:(NSString *)repoDid limit:(NSInteger)limit offset:(NSInteger)offset error:(NSError **)error;

/*!
 @method getBlockCountForRepo:error:
 
 @abstract Counts the total blocks in a repository.
 
 @param repoDid The DID of the repository.
 @param error On return, contains an error if the operation failed.
 @return The number of blocks in the repository.
 */
- (NSInteger)getBlockCountForRepo:(NSString *)repoDid error:(NSError **)error;

/*!
 @method deleteBlock:repoDid:error:
 
 @abstract Deletes a block from the database.
 
 @param cid The CID of the block to delete.
 @param repoDid The DID of the repository that owns the block.
 @param error On return, contains an error if the operation failed.
 @return YES if the block was deleted successfully, NO otherwise.
 */
- (BOOL)deleteBlock:(NSData *)cid repoDid:(NSString *)repoDid error:(NSError **)error;

@end

/*!
 @category PDSDatabase (Blobs)
 
 @abstract Blob metadata methods for PDSDatabase.
 
 @discussion These methods manage blob references and metadata. Blobs are
 large binary attachments stored separately from the repository data.
 */
@interface PDSDatabase (Blobs)

/*!
 @method saveBlob:error:
 
 @abstract Saves blob metadata to the database.
 
 @param blob The blob object to save.
 @param error On return, contains an error if the operation failed.
 @return YES if the blob was saved successfully, NO otherwise.
 */
- (BOOL)saveBlob:(PDSDatabaseBlob *)blob error:(NSError **)error;

/*!
 @method getBlobWithCid:error:
 
 @abstract Retrieves blob metadata by CID.
 
 @param cid The CID of the blob.
 @param error On return, contains an error if the operation failed.
 @return The blob object, or nil if not found.
 */
- (nullable PDSDatabaseBlob *)getBlobWithCid:(NSData *)cid error:(NSError **)error;

/*!
 @method getBlobsForDid:limit:offset:error:
 
 @abstract Retrieves blobs uploaded by an account.
 
 @param did The DID of the account.
 @param limit Maximum number of blobs to return.
 @param offset Number of blobs to skip.
 @param error On return, contains an error if the operation failed.
 @return An array of blob objects.
 */
- (NSArray<PDSDatabaseBlob *> *)getBlobsForDid:(NSString *)did limit:(NSInteger)limit offset:(NSInteger)offset error:(NSError **)error;

/*!
 @method getBlobCountForDid:error:
 
 @abstract Counts blobs uploaded by an account.
 
 @param did The DID of the account.
 @param error On return, contains an error if the operation failed.
 @return The number of blobs uploaded by the account.
 */
- (NSInteger)getBlobCountForDid:(NSString *)did error:(NSError **)error;

/*!
 @method deleteBlob:error:
 
 @abstract Deletes a blob from the database.
 
 @param cid The CID of the blob to delete.
 @param error On return, contains an error if the operation failed.
 @return YES if the blob was deleted successfully, NO otherwise.
 */
- (BOOL)deleteBlob:(NSData *)cid error:(NSError **)error;

@end

/*!
 @category PDSDatabase (Transactions)
 
 @abstract Transaction methods for PDSDatabase.
 
 @discussion These methods support SQLite transactions for atomic operations.
 Use transactions to group multiple operations into a single atomic unit.
 */
@interface PDSDatabase (Transactions)

/*!
 @method beginTransactionWithError:
 
 @abstract Begins a database transaction.
 
 @discussion All subsequent operations will be part of this transaction
 until commit or rollback is called.
 
 @param error On return, contains an error if the operation failed.
 @return YES if the transaction began successfully, NO otherwise.
 */
- (BOOL)beginTransactionWithError:(NSError **)error;

/*!
 @method commitTransactionWithError:
 
 @abstract Commits the current transaction.
 
 @discussion All operations since the last beginTransaction are made permanent.
 
 @param error On return, contains an error if the operation failed.
 @return YES if the transaction committed successfully, NO otherwise.
 */
- (BOOL)commitTransactionWithError:(NSError **)error;

/*!
 @method rollbackTransactionWithError:
 
 @abstract Rolls back the current transaction.
 
 @discussion All operations since the last beginTransaction are discarded.
 
 @param error On return, contains an error if the operation failed.
 @return YES if the transaction rolled back successfully, NO otherwise.
 */
- (BOOL)rollbackTransactionWithError:(NSError **)error;

@end

/*!
 @category PDSDatabase (Moderation)
 
 @abstract Moderation and labeling methods.
 */
@interface PDSDatabase (Moderation)

- (BOOL)takeDownAccount:(NSString *)did reason:(nullable NSString *)reason takedownRef:(nullable NSString *)ref error:(NSError **)error;
- (BOOL)reinstateAccount:(NSString *)did error:(NSError **)error;
- (BOOL)isAccountTakedownActive:(NSString *)did error:(NSError **)error;
- (BOOL)createLabel:(NSDictionary *)label error:(NSError **)error;
- (NSArray<NSDictionary *> *)getLabelsWithPatterns:(nullable NSArray<NSString *> *)uriPatterns sources:(nullable NSArray<NSString *> *)sources limit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error;

@end

/*!
 @category PDSDatabase (AdminAudit)
 
 @abstract Admin audit logging methods.
 */
@interface PDSDatabase (AdminAudit)

- (BOOL)insertAuditLogEntry:(NSDictionary *)entry error:(NSError **)error;
- (NSArray<NSDictionary *> *)queryAuditLog:(NSDictionary *)filters limit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error;
- (BOOL)deleteAuditLogsOlderThanDays:(NSInteger)days error:(NSError **)error;

@end

/*!
 @category PDSDatabase (Reports)
 
 @abstract Moderation reports methods.
 */
@interface PDSDatabase (Reports)

- (NSString *)createReport:(NSDictionary *)report error:(NSError **)error;
- (NSArray<NSDictionary *> *)queryReports:(NSDictionary *)filters limit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error;
- (nullable NSDictionary *)getReportById:(NSString *)reportId error:(NSError **)error;
- (BOOL)updateReportStatus:(NSString *)reportId status:(NSString *)status resolvedBy:(nullable NSString *)adminDid notes:(nullable NSString *)notes error:(NSError **)error;

@end

/*!
 @category PDSDatabase (AdminConfig)
 
 @abstract Admin configuration methods.
 */
@interface PDSDatabase (AdminConfig)

- (nullable NSString *)getAdminConfigValue:(NSString *)key error:(NSError **)error;
- (BOOL)setAdminConfigValue:(NSString *)value forKey:(NSString *)key error:(NSError **)error;

@end

/*!
 @category PDSDatabase (VideoJobs)
 
 @abstract Video processing job methods.
 */
@interface PDSDatabase (VideoJobs)

- (nullable NSDictionary *)getVideoJobById:(NSString *)jobId error:(NSError **)error;
- (BOOL)createVideoJobWithId:(NSString *)jobId
                         did:(NSString *)did
                      blobCid:(NSString *)blobCid
                    mimeType:(nullable NSString *)mimeType
                     fileSize:(NSNumber *)fileSize
                        error:(NSError **)error;
- (BOOL)updateVideoJobState:(NSString *)jobId
                       state:(NSString *)state
                    progress:(NSNumber *)progress
                     message:(nullable NSString *)message
                       error:(NSError **)error;

- (BOOL)setAgeAssurance:(nullable NSString *)assurance
              verifiedAt:(nullable NSString *)verifiedAt
                 forDid:(NSString *)did
                 error:(NSError **)error;

+ (void)parseLimit:(nullable NSString *)limit outLimit:(NSUInteger *)outLimit;

#pragma mark - WebAuthn Credentials

- (BOOL)storeWebAuthnCredential:(NSDictionary *)credential
                       forDid:(NSString *)did
                        error:(NSError **)error;

- (NSArray<NSDictionary *> *)getWebAuthnCredentialsForDid:(NSString *)did error:(NSError **)error;

- (BOOL)deleteWebAuthnCredential:(NSData *)credentialId
                      forDid:(NSString *)did
                       error:(NSError **)error;

- (BOOL)updateWebAuthnCredentialSignCount:(NSData *)credentialId
                             forDid:(NSString *)did
                          signCount:(uint32_t)signCount
                             error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
