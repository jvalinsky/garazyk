#import <Foundation/Foundation.h>

@class PDSDatabase;
@class MST;
@class Session;
@class BlobStorage;
@class CID;
@class SubscribeReposHandler;

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PDSController
 
 @abstract The main controller class for the ATProto Personal Data Server (PDS).
 
 @discussion PDSController coordinates all PDS operations including:
 <ul>
   <li>Session and account management</li>
   <li>Record CRUD operations on user repositories</li>
   <li>Repository state management and commits</li>
   <li>Blob storage and retrieval</li>
   <li>Integration with PLC directory for identity</li>
 </ul>
 
 This class serves as the primary entry point for PDS functionality and
 maintains references to the database, blob storage, and subscription handlers.
 */
@interface PDSController : NSObject

/*!
 @method initWithDatabase:
 
 @abstract Initializes the PDS controller with a database connection.
 
 @param database The PDSDatabase instance for data persistence.
 @return An initialized PDSController instance.
 */
- (instancetype)initWithDatabase:(PDSDatabase *)database;

/*!
 @method startServer
 
 @abstract Starts the HTTP server and begins listening for requests.
 
 @discussion This method starts the internal HTTP server on the configured port
 and begins processing incoming requests. The server runs on the current thread
 unless configured otherwise.
 */
- (void)startServer;

/*!
 @method stopServer
 
 @abstract Stops the HTTP server and cleans up resources.
 
 @discussion This method gracefully shuts down the server, closing all active
 connections and releasing associated resources.
 */
- (void)stopServer;

/*!
 @property database
 
 @abstract The PDSDatabase instance for data persistence.
 
 @discussion This read-only property provides access to the underlying database
 layer for data operations.
 */
@property (nonatomic, readonly) PDSDatabase *database;

/*!
 @property blobStorage
 
 @abstract The BlobStorage instance for blob operations.
 
 @discussion This read-only property provides access to blob storage functionality
 for uploading, retrieving, and managing large binary data.
 */
@property (nonatomic, readonly) BlobStorage *blobStorage;

/*!
 @property subscribeReposHandler
 
 @abstract The handler for repository subscription (firehose) connections.
 
 @discussion This property is nil if the firehose feature is not enabled.
 When set, it manages WebSocket connections for real-time event streaming.
 */
@property (nonatomic, readonly, nullable) SubscribeReposHandler *subscribeReposHandler;

/*!
 @property plcServerURL
 
 @abstract The URL of the PLC directory server for identity operations.
 
 @discussion Default value is "https://plc.directory". This URL is used for
 registering new identities and resolving existing DIDs.
 */
@property (nonatomic, copy) NSString *plcServerURL;

#pragma mark - Session Management

/*!
 @method createSessionForIdentifier:password:handle:did:error:
 
 @abstract Creates a new user session after validating credentials.
 
 @param identifier The user's handle or DID (e.g., "user.example.com" or "did:plc:...").
 @param password The user's password for authentication.
 @param handle The user's handle (e.g., "user.example.com").
 @param did The user's decentralized identifier.
 @param error On return, contains an error if session creation failed.
 @return A dictionary containing session tokens (accessToken, refreshToken, tokenType)
         or nil if authentication failed.
 */
- (nullable NSDictionary *)createSessionForIdentifier:(NSString *)identifier
                                             password:(NSString *)password
                                              handle:(NSString *)handle
                                                did:(NSString *)did
                                               error:(NSError **)error;

/*!
 @method refreshSessionWithRefreshToken:error:
 
 @abstract Refreshes an expired access token using a valid refresh token.
 
 @param refreshToken The refresh token from the original session.
 @param error On return, contains an error if refresh failed.
 @return A dictionary containing new session tokens, or nil if refresh failed.
 */
- (nullable NSDictionary *)refreshSessionWithRefreshToken:(NSString *)refreshToken
                                                    error:(NSError **)error;

#pragma mark - Account Management

/*!
 @method createAccountForEmail:password:handle:did:error:
 
 @abstract Creates a new user account and initializes their repository.
 
 @param email The user's email address for notifications and recovery.
 @param password The initial password for the account.
 @param handle The desired handle for the user (e.g., "user.example.com").
 @param did The pre-generated DID for the user (nil to auto-generate).
 @param error On return, contains an error if account creation failed.
 @return A dictionary with account details and session tokens, or nil on failure.
 */
- (nullable NSDictionary *)createAccountForEmail:(NSString *)email
                                        password:(NSString *)password
                                         handle:(NSString *)handle
                                            did:(nullable NSString *)did
                                           error:(NSError **)error;

/*!
 @method createPlcAccountForEmail:password:handle:did:error:
 
 @abstract Creates a new account and registers it with the PLC directory.
 
 @param email The user's email address.
 @param password The initial password.
 @param handle The user's handle.
 @param did The pre-generated DID (nil to generate new).
 @param error On return, contains an error if registration failed.
 @return Account details including PLC registration confirmation, or nil on failure.
 
 @note This method performs both local account creation and PLC directory registration.
 */
- (nullable NSDictionary *)createPlcAccountForEmail:(NSString *)email
                                           password:(NSString *)password
                                            handle:(NSString *)handle
                                               did:(nullable NSString *)did
                                              error:(NSError **)error;

#pragma mark - Record Creation

/*!
 @method createRecordForDid:collection:record:error:
 
 @abstract Creates a new record in the user's repository.
 
 @param did The DID of the repository owner.
 @param collection The collection identifier (e.g., "app.bsky.feed.post").
 @param record The record data as a dictionary.
 @param error On return, contains an error if creation failed.
 @return A dictionary with the created record's URI and CID, or nil on failure.
 */
- (nullable NSDictionary *)createRecordForDid:(NSString *)did
                                     collection:(NSString *)collection
                                          record:(NSDictionary *)record
                                           error:(NSError **)error;

/*!
 @method createRecordForDid:collection:record:rkey:error:
 
 @abstract Creates a new record with a specific record key (rkey).
 
 @param did The DID of the repository owner.
 @param collection The collection identifier.
 @param record The record data as a dictionary.
 @param rkey The specific record key to use (instead of auto-generating).
 @param error On return, contains an error if creation failed.
 @return A dictionary with the created record's URI and CID, or nil on failure.
 */
- (nullable NSDictionary *)createRecordForDid:(NSString *)did
                                     collection:(NSString *)collection
                                          record:(NSDictionary *)record
                                            rkey:(nullable NSString *)rkey
                                           error:(NSError **)error;

/*!
 @method validateRecord:forCollection:error:
 
 @abstract Validates a record against its collection schema.
 
 @param record The record data to validate.
 @param collection The collection identifier.
 @param error On return, contains validation error details.
 @return YES if validation passes, NO otherwise.
 */
- (BOOL)validateRecord:(NSDictionary *)record
         forCollection:(NSString *)collection
                error:(NSError **)error;

#pragma mark - Record Update and Retrieval

/*!
 @method putRecordForDid:collection:rkey:record:error:
 
 @abstract Updates an existing record or creates it if it doesn't exist.
 
 @param did The DID of the repository owner.
 @param collection The collection identifier.
 @param rkey The record key.
 @param record The new record data.
 @param error On return, contains an error if the operation failed.
 @return A dictionary with the record's URI and CID, or nil on failure.
 */
- (nullable NSDictionary *)putRecordForDid:(NSString *)did
                                 collection:(NSString *)collection
                                      rkey:(NSString *)rkey
                                     record:(NSDictionary *)record
                                      error:(NSError **)error;

/*!
 @method getRecordForDid:collection:rkey:error:
 
 @abstract Retrieves a specific record from a repository.
 
 @param did The DID of the repository owner.
 @param collection The collection identifier.
 @param rkey The record key.
 @param error On return, contains an error if retrieval failed.
 @return The record data as a dictionary, or nil if not found.
 */
- (nullable NSDictionary *)getRecordForDid:(NSString *)did
                                 collection:(NSString *)collection
                                      rkey:(NSString *)rkey
                                     error:(NSError **)error;

/*!
 @method listRecordsForDid:collection:limit:cursor:error:
 
 @abstract Lists records in a collection with pagination.
 
 @param did The DID of the repository owner.
 @param collection The collection identifier (nil for all collections).
 @param limit Maximum number of records to return (1-100).
 @param cursor Pagination cursor from previous request.
 @param error On return, contains an error if the operation failed.
 @return An array of record dictionaries, or nil on failure.
 */
- (NSArray<NSDictionary *> *)listRecordsForDid:(NSString *)did
                                     collection:(NSString *)collection
                                         limit:(NSInteger)limit
                                        cursor:(nullable NSString *)cursor
                                         error:(NSError **)error;

/*!
 @method deleteRecordForDid:collection:rkey:error:
 
 @abstract Deletes a record from a repository.
 
 @param did The DID of the repository owner.
 @param collection The collection identifier.
 @param rkey The record key.
 @param error On return, contains an error if deletion failed.
 @return YES if deletion succeeded, NO otherwise.
 */
- (BOOL)deleteRecordForDid:(NSString *)did
                 collection:(NSString *)collection
                      rkey:(NSString *)rkey
                     error:(NSError **)error;

#pragma mark - Repository Operations

/*!
 @method applyWrites:repo:validate:swapCommit:error:
 
 @abstract Applies a batch of writes to a repository atomically.
 
 @param writes An array of write operations.
 @param repo The repository DID.
 @param validate Whether to validate records against schemas.
 @param swapCommit Optional commit CID for optimistic concurrency control.
 @param error On return, contains an error if the operation failed.
 @return A dictionary with the new repository commit details, or nil on failure.
 */
- (nullable NSDictionary *)applyWrites:(NSArray *)writes
                                 repo:(NSString *)repo
                             validate:(BOOL)validate
                           swapCommit:(nullable NSString *)swapCommit
                                error:(NSError **)error;

/*!
 @method describeRepo:error:
 
 @abstract Gets detailed information about a repository.
 
 @param repo The repository DID.
 @param error On return, contains an error if the operation failed.
 @return A dictionary with repository details (handle, did, collections, etc.),
         or nil on failure.
 */
- (nullable NSDictionary *)describeRepo:(NSString *)repo error:(NSError **)error;

/*!
 @method getRepoForDid:
 
 @abstract Retrieves the MST (Merkle Search Tree) for a repository.
 
 @param did The repository DID.
 @return The MST instance, or nil if not found.
 */
- (nullable MST *)getRepoForDid:(NSString *)did;

/*!
 @method getRepoDataForDid:error:
 
 @abstract Exports a repository as a CAR (Content Addressable Records) file.
 
 @param did The repository DID.
 @param error On return, contains an error if export failed.
 @return The CAR data, or nil on failure.
 */
- (nullable NSData *)getRepoDataForDid:(NSString *)did
                                 error:(NSError **)error;

/*!
 @method getRepoHeadForDid:error:
 
 @abstract Gets the current head CID of a repository.
 
 @param did The repository DID.
 @param error On return, contains an error if retrieval failed.
 @return The head CID as a string, or nil on failure.
 */
- (nullable NSString *)getRepoHeadForDid:(NSString *)did
                                   error:(NSError **)error;

#pragma mark - Blob Storage

/*!
 @method uploadBlob:mimeType:did:error:
 
 @abstract Uploads a blob to the server.
 
 @param data The blob data to upload.
 @param mimeType The MIME type of the blob (e.g., "image/png").
 @param did The DID of the uploader.
 @param error On return, contains an error if upload failed.
 @return A dictionary with the blob's CID and metadata, or nil on failure.
 
 @note The blob is validated against the configured allowed MIME types.
 */
- (nullable NSDictionary *)uploadBlob:(NSData *)data
                             mimeType:(NSString *)mimeType
                                  did:(NSString *)did
                               error:(NSError **)error;

/*!
 @method getBlobWithCID:did:error:
 
 @abstract Retrieves a blob by its CID.
 
 @param cidString The CID of the blob.
 @param did The DID of the blob owner (for access control).
 @param error On return, contains an error if retrieval failed.
 @return A dictionary with the blob data and metadata, or nil if not found.
 */
- (nullable NSDictionary *)getBlobWithCID:(NSString *)cidString
                                     did:(NSString *)did
                                  error:(NSError **)error;

/*!
 @method listBlobsForDID:limit:cursor:error:
 
 @abstract Lists blobs owned by a DID with pagination.
 
 @param did The DID of the blob owner.
 @param limit Maximum number of blobs to return.
 @param cursor Pagination cursor from previous request.
 @param error On return, contains an error if the operation failed.
 @return An array of blob metadata dictionaries, or nil on failure.
 */
- (nullable NSArray<NSDictionary *> *)listBlobsForDID:(NSString *)did
                                                limit:(NSInteger)limit
                                               cursor:(nullable NSString *)cursor
                                                error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
