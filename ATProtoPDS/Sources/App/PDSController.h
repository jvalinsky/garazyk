#import <Foundation/Foundation.h>

@class PDSDatabase;
@class MST;
@class Session;
@class BlobStorage;
@class CID;
@class SubscribeReposHandler;

NS_ASSUME_NONNULL_BEGIN

/**
 @file PDSController.h

 @brief The PDSController class serves as the primary coordinator for the AT Protocol Personal Data Server (PDS).
        It manages all high-level operations including account creation, session management, record storage,
        repository operations, and blob storage. This class acts as the central interface between the PDS
        infrastructure and the various subsystem components.
 */

@interface PDSController : NSObject

#pragma mark - Initialization and Server Lifecycle

/**
 @brief Initializes a new PDSController instance with the specified database.

 @param database The PDSDatabase instance to use for data persistence. Must not be nil.

 @return A newly initialized PDSController instance, or nil if initialization failed.

 @discussion This initializer establishes the connection between the controller and the underlying
             database layer. The controller will use this database for all persistence operations.
             After initialization, call \c startServer to begin accepting requests.
 */
- (instancetype)initWithDatabase:(PDSDatabase *)database;

/**
 @brief Starts the PDS server, enabling it to accept and process incoming requests.

 @discussion This method initializes all necessary server components and begins listening for
             incoming connections. The server will remain running until \c stopServer is called.
             Ensure that the controller has been properly initialized with a valid database
             before calling this method.
 */
- (void)startServer;

/**
 @brief Stops the PDS server, gracefully shutting down all active connections and resources.

 @discussion This method performs a graceful shutdown of the server, ensuring that all pending
             operations are completed or properly handled. After calling this method, the server
             will no longer accept new requests. Call \c startServer to restart the server.
 */
- (void)stopServer;

#pragma mark - Properties

/**
 @brief The PDSDatabase instance used for all data persistence operations.

 @discussion This read-only property provides access to the underlying database layer that handles
             all persistent storage for the PDS. The database is set during initialization and
             cannot be changed during the lifetime of the controller.
 */
@property (nonatomic, readonly) PDSDatabase *database;

/**
 @brief The BlobStorage instance used for binary large object storage and retrieval.

 @discussion This read-only property provides access to the blob storage subsystem that handles
             all binary data such as images, videos, and other large files. Blobs are referenced
             by CID (Content Identifier) and can be associated with any record.
 */
@property (nonatomic, readonly) BlobStorage *blobStorage;

/**
 @brief The optional SubscribeReposHandler for handling real-time repository updates via WebSocket.

 @discussion This property is nullable and contains the handler responsible for streaming
             repository changes to subscribed clients. It is lazily initialized when the first
             subscription request is received. When nil, repository subscription functionality
             is unavailable.
 */
@property (nonatomic, readonly, nullable) SubscribeReposHandler *subscribeReposHandler;

#pragma mark - Session Management

/**
 @brief Creates a new session for an existing user.

 @param identifier The user's account identifier (email, handle, or DID).
 @param password The user's password for authentication.
 @param handle The user's handle (e.g., "user.bsky.social").
 @param did The user's decentralized identifier (DID).
 @param error On return, contains an error if the session creation failed.

 @return A dictionary containing session details including access and refresh tokens, or nil if failed.

 @discussion This method authenticates an existing user and creates a new session. On success,
             the returned dictionary contains the OAuth tokens required for subsequent authenticated
             requests. The session tokens have a limited lifetime and should be refreshed using
             \c refreshSessionWithRefreshToken:error: before expiration.
 */
- (nullable NSDictionary *)createSessionForIdentifier:(NSString *)identifier
                                              password:(NSString *)password
                                               handle:(NSString *)handle
                                                 did:(NSString *)did
                                                error:(NSError **)error;

/**
 @brief Refreshes an existing session using a refresh token.

 @param refreshToken The refresh token from a previous session.
 @param error On return, contains an error if the refresh failed.

 @return A dictionary containing new session tokens, or nil if the refresh failed.

 @discussion This method takes a valid refresh token and issues a new set of access and refresh
             tokens. The old refresh token becomes invalid after this operation. This allows
             long-lived sessions without requiring the user to re-authenticate.
 */
- (nullable NSDictionary *)refreshSessionWithRefreshToken:(NSString *)refreshToken
                                                      error:(NSError **)error;

#pragma mark - Account Management

/**
 @brief Creates a new account on the PDS.

 @param email The email address for the new account.
 @param password The initial password for the account.
 @param handle The desired handle for the account.
 @param did An optional pre-specified DID. If nil, one will be generated.
 @param error On return, contains an error if account creation failed.

 @return A dictionary containing the created account details and initial session tokens, or nil if failed.

 @discussion This method registers a new user on the PDS. If the \c did parameter is provided,
             it must be a valid DID format; otherwise, a new DID will be automatically generated.
             On success, the returned dictionary includes both account information and initial
             session tokens for immediate use.
 */
- (nullable NSDictionary *)createAccountForEmail:(NSString *)email
                                          password:(NSString *)password
                                           handle:(NSString *)handle
                                              did:(nullable NSString *)did
                                             error:(NSError **)error;

#pragma mark - Record Creation

/**
 @brief Creates a new record in the specified collection.

 @param did The DID of the repository (user) owning this record.
 @param collection The collection identifier (e.g., "app.bsky.feed.post").
 @param record The record data as a dictionary.
 @param error On return, contains an error if the operation failed.

 @return A dictionary containing the created record's URI and CID, or nil if failed.

 @discussion This method creates a new record with an auto-generated record key (rkey).
             The record is validated against the collection schema before insertion.
             Returns the AT-URI (e.g., "at://did:plc:z72.../app.bsky.feed.post/3k5... ")
             and the content hash (CID) of the created record.
 */
- (nullable NSDictionary *)createRecordForDid:(NSString *)did
                                    collection:(NSString *)collection
                                         record:(NSDictionary *)record
                                          error:(NSError **)error;

/**
 @brief Creates a new record with an optional specified record key.

 @param did The DID of the repository (user) owning this record.
 @param collection The collection identifier.
 @param record The record data as a dictionary.
 @param rkey An optional custom record key. If nil, one is auto-generated.
 @param error On return, contains an error if the operation failed.

 @return A dictionary containing the created record's URI and CID, or nil if failed.

 @discussion This variant allows specification of a custom record key (rkey) for the new record.
             If \c rkey is provided, it must be unique within the collection for this repository.
             Custom rkeys are useful for creating records with human-readable or meaningful identifiers.
 */
- (nullable NSDictionary *)createRecordForDid:(NSString *)did
                                    collection:(NSString *)collection
                                         record:(NSDictionary *)record
                                           rkey:(nullable NSString *)rkey
                                         error:(NSError **)error;

/**
 @brief Validates a record against the schema for the specified collection.

 @param record The record data to validate.
 @param collection The collection identifier whose schema should be used.
 @param error On return, contains a validation error if validation failed.

 @return YES if the record is valid, NO if validation failed.

 @discussion This method performs schema validation without creating the record. It checks
             that all required fields are present and that field types match the schema definition.
             Use this method before attempting to create a record to provide better error feedback.
 */
- (BOOL)validateRecord:(NSDictionary *)record
         forCollection:(NSString *)collection
                error:(NSError **)error;

/**
 @brief Creates a new record with an optional specified record key (variant 2).

 @param did The DID of the repository (user) owning this record.
 @param collection The collection identifier.
 @param record The record data as a dictionary.
 @param rkey An optional custom record key.
 @param error On return, contains an error if the operation failed.

 @return A dictionary containing the created record's URI and CID, or nil if failed.

 @discussion Alternative signature for record creation with custom rkey support.
             This method is functionally identical to the previous overload.
 */
- (nullable NSDictionary *)createRecordForDid:(NSString *)did
                                    collection:(NSString *)collection
                                         record:(NSDictionary *)record
                                          rkey:(nullable NSString *)rkey
                                          error:(NSError **)error;

#pragma mark - Record Update and Retrieval

/**
 @brief Updates or creates a record with a specific record key.

 @param did The DID of the repository (user) owning the record.
 @param collection The collection identifier.
 @param rkey The record key identifying the specific record.
 @param record The record data to store.
 @param error On return, contains an error if the operation failed.

 @return A dictionary containing the record's URI and CID after the operation, or nil if failed.

 @discussion This method performs a "put" operation, which creates a new record if it doesn't
             exist or updates an existing record if it does. The record is fully replaced with
             the provided data. This operation affects the repository's commit history.
 */
- (nullable NSDictionary *)putRecordForDid:(NSString *)did
                                 collection:(NSString *)collection
                                      rkey:(NSString *)rkey
                                     record:(NSDictionary *)record
                                      error:(NSError **)error;

/**
 @brief Retrieves a specific record from the repository.

 @param did The DID of the repository (user) owning the record.
 @param collection The collection identifier.
 @param rkey The record key identifying the specific record.
 @param error On return, contains an error if the operation failed.

 @return A dictionary containing the record data, or nil if not found or error occurred.

 @discussion This method retrieves a single record by its full AT-URI components.
             The returned dictionary contains the record's key, collection, value, and CID.
             Returns nil if the record does not exist.
 */
- (nullable NSDictionary *)getRecordForDid:(NSString *)did
                                 collection:(NSString *)collection
                                      rkey:(NSString *)rkey
                                     error:(NSError **)error;

/**
 @brief Lists records in a collection with pagination support.

 @param did The DID of the repository (user) whose records are being listed.
 @param collection The collection identifier.
 @param limit The maximum number of records to return (1-100).
 @param cursor A pagination cursor from a previous request.
 @param error On return, contains an error if the operation failed.

 @return An array of record dictionaries, or nil if an error occurred.

 @discussion This method returns a paginated list of records in the specified collection.
             The \c limit parameter controls the maximum results per page (1-100).
             For subsequent pages, use the \c cursor value returned with the results.
             Each item in the returned array is a record with its URI, CID, and value.
 */
- (NSArray<NSDictionary *> *)listRecordsForDid:(NSString *)did
                                     collection:(NSString *)collection
                                         limit:(NSInteger)limit
                                        cursor:(nullable NSString *)cursor
                                         error:(NSError **)error;

/**
 @brief Deletes a record from the repository.

 @param did The DID of the repository (user) owning the record.
 @param collection The collection identifier.
 @param rkey The record key identifying the record to delete.
 @param error On return, contains an error if the deletion failed.

 @return YES if the record was deleted, NO if the operation failed.

 @discussion This method permanently removes a record from the repository.
             Once deleted, the record cannot be recovered. This operation creates
             a new commit in the repository history. Returns NO if the record
             doesn't exist (except in cases of concurrent deletion).
 */
- (BOOL)deleteRecordForDid:(NSString *)did
                 collection:(NSString *)collection
                      rkey:(NSString *)rkey
                     error:(NSError **)error;

#pragma mark - Repository Operations

/**
 @brief Applies a batch of write operations to a repository atomically.

 @param writes An array of write operation dictionaries.
 @param repo The DID of the repository to modify.
 @param validate If YES, validates records against schemas before applying.
 @param swapCommit Optional commit CID for conditional updates (optimistic locking).
 @param error On return, contains an error if the operation failed.

 @return A dictionary containing the resulting commit information, or nil if failed.

 @discussion This method applies multiple write operations (creates, updates, deletes)
             as a single atomic transaction. All operations succeed or fail together.
             If \c swapCommit is provided, the update only proceeds if the repository's
             current head matches the specified CID, enabling optimistic locking.
 */
- (nullable NSDictionary *)applyWrites:(NSArray *)writes
                                 repo:(NSString *)repo
                             validate:(BOOL)validate
                           swapCommit:(nullable NSString *)swapCommit
                                error:(NSError **)error;

/**
 @brief Describes the contents and metadata of a repository.

 @param repo The DID of the repository to describe.
 @param error On return, contains an error if the operation failed.

 @return A dictionary containing repository details including collections and head CID, or nil if failed.

 @discussion This method returns metadata about a repository including the list of collections
             it contains, the current head commit CID, and other administrative information.
             It provides a high-level overview of the repository's contents.
 */
- (nullable NSDictionary *)describeRepo:(NSString *)repo error:(NSError **)error;

/**
 @brief Retrieves the MST (Merkle Search Tree) structure for a repository.

 @param did The DID of the repository.

 @return The MST object representing the repository's data structure, or nil if not found.

 @discussion This method provides low-level access to the repository's Merkle Search Tree,
             which is the data structure used to organize and verify repository contents.
             The returned MST object can be used for advanced operations and verifications.
 */
- (nullable MST *)getRepoForDid:(NSString *)did;

/**
 @brief Retrieves the serialized data of a repository as NSData.

 @param did The DID of the repository.
 @param error On return, contains an error if the operation failed.

 @return NSData containing the serialized repository, or nil if not found or error occurred.

 @discussion This method returns the complete serialized form of a repository,
             useful for backup, export, or synchronization purposes.
             The data is in a format suitable for storage or transmission.
 */
- (nullable NSData *)getRepoDataForDid:(NSString *)did
                                error:(NSError **)error;

/**
 @brief Retrieves the current head CID of a repository.

 @param did The DID of the repository.
 @param error On return, contains an error if the operation failed.

 @return A string containing the head CID, or nil if not found or error occurred.

 @discussion This method returns the current HEAD commit CID of the repository,
             which represents the latest state of all records in the repository.
             This CID can be used to detect changes or verify synchronization.
 */
- (nullable NSString *)getRepoHeadForDid:(NSString *)did
                                    error:(NSError **)error;

#pragma mark - Blob Storage

/**
 @brief Uploads binary data as a blob.

 @param data The binary data to upload.
 @param mimeType The MIME type of the data (e.g., "image/png").
 @param did The DID of the repository uploading the blob.
 @param error On return, contains an error if the upload failed.

 @return A dictionary containing the blob's CID and metadata, or nil if failed.

 @discussion This method stores arbitrary binary data and returns a CID that can be
             used to reference the blob in records. The blob is associated with
             the specified repository for access control purposes.
 */
- (nullable NSDictionary *)uploadBlob:(NSData *)data
                             mimeType:(NSString *)mimeType
                                  did:(NSString *)did
                               error:(NSError **)error;

/**
 @brief Retrieves a blob by its CID.

 @param cidString The CID string identifying the blob.
 @param did The DID of the repository that owns the blob.
 @param error On return, contains an error if the retrieval failed.

 @return A dictionary containing the blob data and metadata, or nil if not found or error occurred.

 @discussion This method retrieves a blob that has been previously uploaded.
             The blob must exist and be accessible by the requesting repository.
             The returned dictionary includes the blob data, MIME type, and size.
 */
- (nullable NSDictionary *)getBlobWithCID:(NSString *)cidString
                                     did:(NSString *)did
                                  error:(NSError **)error;

/**
 @brief Lists all blobs in a repository with pagination.

 @param did The DID of the repository to list blobs from.
 @param limit The maximum number of blob references to return (1-100).
 @param cursor A pagination cursor from a previous request.
 @param error On return, contains an error if the operation failed.

 @return An array of blob reference dictionaries, or nil if an error occurred.

 @discussion This method returns a paginated list of blob references (CIDs) stored
             in the specified repository. The \c limit parameter controls results per page.
             Use the \c cursor for pagination through large numbers of blobs.
 */
- (nullable NSArray<NSDictionary *> *)listBlobsForDID:(NSString *)did
                                                limit:(NSInteger)limit
                                               cursor:(nullable NSString *)cursor
                                                error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
