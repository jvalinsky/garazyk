/*!
 @file PDSController.h

 @abstract Main application controller for the ATProto PDS.

 @discussion PDSController is the central coordinator for all PDS operations.
 It manages database connections, service instances, and provides high-level
 APIs for account, repository, record, and blob operations.

 @note This class is being refactored. New code should use the service classes
 directly (PDSAccountService, PDSRecordService, PDSBlobService,
 PDSRepositoryService) or the PDSAdminController for administrative operations.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "Compat/PDSTypes.h"
#import "Core/ATProtoError.h"
#import "Services/PDSRecordService.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSApplication;
@class PDSServiceDatabases;
@class PDSDatabase;
@class PDSDatabasePool;
@class PDSActorStore;
@class MST;
@class BlobStorage;
@class SubscribeReposHandler;
@class PDSDatabaseAccount;
@class PDSDatabaseRepo;
@class PDSDatabaseRecord;
@class PDSDatabaseBlob;
@class PDSAccountService;
@class PDSBlobService;
@class PDSRepositoryService;
@class PDSRelayService;
@class JWTMinter;
@class PDSAdminController;

/*!
 @class PDSController

 @abstract Central controller for PDS operations.

 @discussion Provides high-level APIs for managing accounts, repositories,
 records, and blobs. Coordinates between database pools, service layers,
 and JWT minting.

 For new code, prefer using the service classes directly:
 - PDSAccountService for account operations
 - PDSRecordService for record operations
 - PDSBlobService for blob operations
 - PDSRepositoryService for repository operations
 - PDSAdminController for admin/moderation/labeling operations
 */
@interface PDSController : NSObject

#pragma mark - Properties

/*! Path to the data directory. */
@property(nonatomic, copy, readonly) NSString *dataDirectory;

/*! URL of the PLC directory server. */
@property(nonatomic, copy) NSString *plcServerURL;

/*! Whether the HTTP server is running. */
@property(nonatomic, assign, readonly, getter=isRunning) BOOL running;

/*! Service-level database connections. */
@property(nonatomic, strong, readonly) PDSServiceDatabases *serviceDatabases;

/*! Pool for user-specific databases. */
@property(nonatomic, strong, readonly) PDSDatabasePool *userDatabasePool;

/*! Account management service. */
@property(nonatomic, strong, readonly) PDSAccountService *accountService;

/*! Record management service. */
@property(nonatomic, strong, readonly) PDSRecordService *recordService;

/*! Blob management service. */
@property(nonatomic, strong, readonly) PDSBlobService *blobService;

/*! Repository management service. */
@property(nonatomic, strong, readonly) PDSRepositoryService *repositoryService;

/*! Service for notifying external relays of updates. */
@property(nonatomic, strong, readonly) PDSRelayService *relayService;

/*! Administrative operations controller. */
@property(nonatomic, strong, readonly) PDSAdminController *adminController;

/*! JWT minting for access tokens. */
@property(nonatomic, strong, readonly) JWTMinter *jwtMinter;

/*! Port for the HTTP XRPC server (default 2583). */
@property(nonatomic, assign) NSUInteger httpPort;

/*! Compatibility property for subscribeRepos streaming; mirrors HTTP port when
 * running. */
@property(nonatomic, assign, readonly)
    NSUInteger wsPort DEPRECATED_MSG_ATTRIBUTE(
        "subscribeRepos uses HTTP port upgrades; use httpPort");

#pragma mark - Initialization & Lifecycle

/*! Returns the shared controller instance. */
+ (instancetype)sharedController;

/*! Initializes the controller with configuration. */
- (instancetype)initWithDirectory:(NSString *)directory
                   serviceMaxSize:(NSUInteger)serviceMaxSize
                 userDatabaseSize:(NSUInteger)userDatabaseSize;

/*!
 @method initWithApplication:

 @abstract Initializes the controller backed by a PDSApplication.

 @discussion This initializer creates a thin facade over the provided
 PDSApplication, delegating all operations to its services.

 @param application The PDSApplication to delegate to.
 @return An initialized PDSController instance.
 */
- (instancetype)initWithApplication:(PDSApplication *)application;

/*! Starts the HTTP server (including subscribeRepos WebSocket upgrades). */
- (BOOL)startServerWithError:(NSError **)error;

/*! Stops all servers and closes connections. */
- (void)stopServer;

/*! Returns a service database connection. */
- (nullable PDSDatabase *)serviceDatabaseWithError:(NSError **)error;

#pragma mark - Account Operations

/*! Creates a new account with email, password, and handle. */
- (nullable NSDictionary *)createAccountForEmail:(NSString *)email
                                        password:(NSString *)password
                                          handle:(NSString *)handle
                                             did:(nullable NSString *)did
                                           error:(NSError **)error;

/*! Gets account information by DID. */
- (nullable NSDictionary *)getAccountForDid:(NSString *)did
                                      error:(NSError **)error;

/*! Authenticates a user by handle and password. */
- (nullable NSDictionary *)loginWithHandle:(NSString *)handle
                                  password:(NSString *)password
                                     error:(NSError **)error;

/*! Refreshes an access token using a refresh token. */
- (nullable NSDictionary *)refreshAccessToken:(NSString *)refreshToken
                                        error:(NSError **)error;

/*! Deletes an account after password verification. */
- (BOOL)deleteAccount:(NSString *)did
             password:(NSString *)password
                error:(NSError **)error;

#pragma mark - Repository Operations

/*! Gets the root CID of a repository. */
- (nullable NSData *)getRepoRoot:(NSString *)did error:(NSError **)error;

/*! Gets repository contents, optionally since a specific commit. */
- (nullable NSData *)getRepoContents:(NSString *)did
                               since:(nullable NSString *)sinceRev
                               error:(NSError **)error;

/*! Updates a repository with a new commit. */
- (BOOL)updateRepo:(NSString *)did
            commit:(NSData *)commitData
             error:(NSError **)error;

#pragma mark - Record Operations

/*! Gets a record by AT URI. */
- (nullable NSDictionary *)getRecord:(NSString *)uri
                              forDid:(NSString *)did
                               error:(NSError **)error;

/*! Lists records in a collection with pagination. */
- (nullable NSArray *)listRecords:(NSString *)collection
                           forDid:(NSString *)did
                            limit:(NSUInteger)limit
                           cursor:(nullable NSString *)cursor
                            error:(NSError **)error;

/*! Creates or updates a record. */
- (BOOL)putRecord:(NSString *)collection
              rkey:(NSString *)rkey
             value:(NSDictionary *)value
            forDid:(NSString *)did
    validationMode:(PDSValidationMode)mode
             error:(NSError **)error;

/*! Deletes a record. */
- (BOOL)deleteRecord:(NSString *)collection
                rkey:(NSString *)rkey
              forDid:(NSString *)did
               error:(NSError **)error;

/*! Gets repository statistics. */
- (nullable NSDictionary *)getRepoStatsForDid:(NSString *)did
                                        error:(NSError **)error;

#pragma mark - Blob Operations

/*! Gets a blob by CID. */
- (nullable NSData *)getBlob:(NSData *)cid
                      forDid:(NSString *)did
                       error:(NSError **)error;

/*! Uploads a blob. */
- (nullable NSDictionary *)uploadBlob:(NSData *)blobData
                               forDid:(NSString *)did
                             mimeType:(NSString *)mimeType
                                error:(NSError **)error;

#pragma mark - Admin Operations

/*! Gets all accounts in the PDS. Use adminController directly for new code. */
- (nullable NSArray *)getAllAccountsWithError:(NSError **)error;

/*! Takes down an account. Use adminController directly for new code. */
- (BOOL)takeDownAccount:(NSString *)did
                 reason:(NSString *)reason
                  error:(NSError **)error;

/*! Reinstates a taken down account. Use adminController directly for new code.
 */
- (BOOL)reinstateAccount:(NSString *)did error:(NSError **)error;

/*! Checks if an account is taken down. Use adminController directly for new
 * code. */
- (BOOL)isAccountTakedownActive:(NSString *)did error:(NSError **)error;

#pragma mark - Moderation Operations

/*! Moderates an account. Use adminController directly for new code. */
- (NSDictionary *)moderateAccount:(NSDictionary *)params
                            error:(NSError **)error;

/*! Moderates a record. Use adminController directly for new code. */
- (NSDictionary *)moderateRecord:(NSDictionary *)params error:(NSError **)error;

#pragma mark - Labeling Operations

/*! Creates a label. Use adminController directly for new code. */
- (NSDictionary *)createLabel:(NSDictionary *)params error:(NSError **)error;

/*! Gets labels. Use adminController directly for new code. */
- (NSDictionary *)getLabels:(NSDictionary *)params error:(NSError **)error;

#pragma mark - Health & Metrics

/*! Returns health check information. */
- (NSDictionary<NSString *, id> *)getHealthCheck;

/*! Returns metrics information. */
- (NSDictionary<NSString *, id> *)getMetrics;

#pragma mark - Deprecated Methods
// =============================================================================
// DEPRECATED: The following methods are provided for backward compatibility.
// They will be removed in a future version. Please migrate to the new APIs.
// =============================================================================

/*! @deprecated Use serviceDatabases and userDatabasePool instead. */
@property(nonatomic, strong, readonly, nullable)
    id database DEPRECATED_MSG_ATTRIBUTE(
        "Use serviceDatabases and userDatabasePool instead");

/*! @deprecated Use loginWithHandle:password:error: instead. */
- (nullable NSDictionary *)createSessionForIdentifier:(NSString *)identifier
                                             password:(NSString *)password
                                               handle:(NSString *)handle
                                                  did:(NSString *)did
                                                error:(NSError **)error
    DEPRECATED_MSG_ATTRIBUTE("Use loginWithHandle:password:error: instead");

/*! @deprecated Use refreshAccessToken:error: instead. */
- (nullable NSDictionary *)refreshSessionWithRefreshToken:
                               (NSString *)refreshToken
                                                    error:(NSError **)error
    DEPRECATED_MSG_ATTRIBUTE("Use refreshAccessToken:error: instead");

/*! @deprecated Use getRepoContents:since:error: with nil sinceRev instead. */
- (nullable NSData *)getRepoDataForDid:(NSString *)did
                                 error:(NSError **)error
    DEPRECATED_MSG_ATTRIBUTE(
        "Use getRepoContents:since:error: with nil sinceRev instead");

/*! @deprecated Use getRepoRoot:error: instead. */
- (nullable NSString *)getRepoHeadForDid:(NSString *)did
                                   error:(NSError **)error
    DEPRECATED_MSG_ATTRIBUTE("Use getRepoRoot:error: instead");

/*! @deprecated Use putRecord:rkey:value:forDid:validationMode:error: instead.
 */
- (nullable NSDictionary *)createRecordForDid:(NSString *)did
                                   collection:(NSString *)collection
                                       record:(NSDictionary *)record
                               validationMode:(PDSValidationMode)mode
                                        error:(NSError **)error
    DEPRECATED_MSG_ATTRIBUTE(
        "Use putRecord:rkey:value:forDid:validationMode:error: instead");

/*! @deprecated Use getRecord:forDid:error: instead. */
- (nullable NSDictionary *)getRecordForDid:(NSString *)did
                                collection:(NSString *)collection
                                      rkey:(NSString *)rkey
                                     error:(NSError **)error
    DEPRECATED_MSG_ATTRIBUTE("Use getRecord:forDid:error: instead");

/*! @deprecated Use listRecords:forDid:limit:cursor:error: instead. */
- (nullable NSArray *)listRecordsForDid:(NSString *)did
                             collection:(NSString *)collection
                                  limit:(NSUInteger)limit
                                 cursor:(nullable NSString *)cursor
                                  error:(NSError **)error
    DEPRECATED_MSG_ATTRIBUTE(
        "Use listRecords:forDid:limit:cursor:error: instead");

/*! @deprecated Use deleteRecord:rkey:forDid:error: instead. */
- (BOOL)deleteRecordForDid:(NSString *)did
                collection:(NSString *)collection
                      rkey:(NSString *)rkey
                     error:(NSError **)error
    DEPRECATED_MSG_ATTRIBUTE("Use deleteRecord:rkey:forDid:error: instead");

/*! @deprecated Use putRecord:rkey:value:forDid:validationMode:error: instead.
 */
- (BOOL)putRecordForDid:(NSString *)did
             collection:(NSString *)collection
                   rkey:(NSString *)rkey
                 record:(NSDictionary *)record
         validationMode:(PDSValidationMode)mode
                  error:(NSError **)error
    DEPRECATED_MSG_ATTRIBUTE(
        "Use putRecord:rkey:value:forDid:validationMode:error: instead");

/*! @deprecated Use uploadBlob:forDid:mimeType:error: instead (parameter order
 * changed). */
- (nullable NSDictionary *)uploadBlob:(NSData *)blobData
                             mimeType:(NSString *)mimeType
                                  did:(NSString *)did
                                error:(NSError **)error
    DEPRECATED_MSG_ATTRIBUTE("Use uploadBlob:forDid:mimeType:error: instead");

/*! @deprecated Use blobService.getBlobWithCID:did:error: instead. */
- (nullable NSDictionary *)getBlobWithCID:(NSString *)cid
                                      did:(NSString *)did
                                    error:(NSError **)error
    DEPRECATED_MSG_ATTRIBUTE(
        "Use blobService.getBlobWithCID:did:error: instead");

/*! @deprecated Use blobService.listBlobsForDID:limit:cursor:error: instead. */
- (nullable NSArray *)listBlobsForDID:(NSString *)did
                                limit:(NSUInteger)limit
                               cursor:(nullable NSString *)cursor
                                error:(NSError **)error
    DEPRECATED_MSG_ATTRIBUTE(
        "Use blobService.listBlobsForDID:limit:cursor:error: instead");

/*! @deprecated Use blobService.deleteBlobWithCID:did:error: instead. */
- (BOOL)deleteBlobWithCID:(NSString *)cid
                      did:(NSString *)did
                    error:(NSError **)error
    DEPRECATED_MSG_ATTRIBUTE(
        "Use blobService.deleteBlobWithCID:did:error: instead");

/*! @deprecated Use putRecord/deleteRecord in a loop instead. */
- (nullable NSDictionary *)applyWrites:(NSArray *)writes
                                  repo:(NSString *)repo
                              validate:(BOOL)validate
                            swapCommit:(nullable NSString *)swapCommit
                                 error:(NSError **)error
    DEPRECATED_MSG_ATTRIBUTE("Use putRecord/deleteRecord in a loop instead");

/*! @deprecated This is a composite method - use getRepoRoot, accountService,
 * and recordService instead. */
- (nullable NSDictionary *)describeRepo:(NSString *)repo
                                  error:(NSError **)error
    DEPRECATED_MSG_ATTRIBUTE(
        "Use getRepoRoot, accountService, and recordService directly instead");

@end

NS_ASSUME_NONNULL_END
