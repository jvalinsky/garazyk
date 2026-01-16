/*!
 @file PDSController.h

 @abstract Main application controller for the ATProto PDS.

 @discussion PDSController is the central coordinator for all PDS operations.
 It manages database connections, service instances, and provides high-level
 APIs for account, repository, record, and blob operations.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Services/PDSRecordService.h"

NS_ASSUME_NONNULL_BEGIN

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
@class PDSSyncService;
@class JWTMinter;

/*! Error domain for PDSController operations. */
extern NSString * const PDSControllerErrorDomain;

/*!
 @enum PDSControllerError

 @abstract Error codes for controller operations.

 @constant PDSControllerErrorAccountNotFound Account does not exist.
 @constant PDSControllerErrorAccountAlreadyExists Handle/email already taken.
 @constant PDSControllerErrorInvalidToken Token is invalid or expired.
 @constant PDSControllerErrorInvalidHandle Handle format is invalid.
 @constant PDSControllerErrorRepoNotFound Repository does not exist.
 @constant PDSControllerErrorRecordNotFound Record does not exist.
 @constant PDSControllerErrorBlobNotFound Blob does not exist.
 @constant PDSControllerErrorUnauthorized Operation not authorized.
 */
typedef NS_ENUM(NSInteger, PDSControllerError) {
    PDSControllerErrorAccountNotFound = 1000,
    PDSControllerErrorAccountAlreadyExists,
    PDSControllerErrorInvalidToken,
    PDSControllerErrorInvalidHandle,
    PDSControllerErrorRepoNotFound,
    PDSControllerErrorRecordNotFound,
    PDSControllerErrorBlobNotFound,
    PDSControllerErrorUnauthorized,
};

/*!
 @class PDSController

 @abstract Central controller for PDS operations.

 @discussion Provides high-level APIs for managing accounts, repositories,
 records, and blobs. Coordinates between database pools, service layers,
 and JWT minting.
 */
@interface PDSController : NSObject

/*! Path to the data directory. */
@property (nonatomic, copy, readonly) NSString *dataDirectory;

/*! URL of the PLC directory server. */
@property (nonatomic, copy) NSString *plcServerURL;

/*! Whether the HTTP server is running. */
@property (nonatomic, assign, readonly, getter=isRunning) BOOL running;

/*! Service-level database connections. */
@property (nonatomic, strong, readonly) PDSServiceDatabases *serviceDatabases;

/*! Pool for user-specific databases. */
@property (nonatomic, strong, readonly) PDSDatabasePool *userDatabasePool;

/*! Account management service. */
@property (nonatomic, strong, readonly) PDSAccountService *accountService;

/*! Record management service. */
@property (nonatomic, strong, readonly) PDSRecordService *recordService;

/*! Blob management service. */
@property (nonatomic, strong, readonly) PDSBlobService *blobService;

/*! Repository management service. */
@property (nonatomic, strong, readonly) PDSRepositoryService *repositoryService;

/*! Repository synchronization service. */
@property (nonatomic, strong, readonly) PDSSyncService *syncService;

/*! JWT minting for access tokens. */
@property (nonatomic, strong, readonly) JWTMinter *jwtMinter;

/*! Port for the HTTP XRPC server (default 2583). */
@property (nonatomic, assign) NSUInteger httpPort;

/*! Port for the WebSocket subscribeRepos handler (default 8081). */
@property (nonatomic, assign) NSUInteger wsPort;

/*! Returns a service database connection. */
- (nullable PDSDatabase *)serviceDatabaseWithError:(NSError **)error;

/*! Deprecated - use serviceDatabases and userDatabasePool. */
@property (nonatomic, strong, readonly, nullable) id database;

+ (instancetype)sharedController;

- (instancetype)initWithDirectory:(NSString *)directory 
                   serviceMaxSize:(NSUInteger)serviceMaxSize 
                 userDatabaseSize:(NSUInteger)userDatabaseSize;

- (BOOL)startServerWithError:(NSError **)error;
- (void)stopServer;

#pragma mark - Account Operations

- (nullable NSDictionary *)createAccountForEmail:(NSString *)email
                                        password:(NSString *)password
                                         handle:(NSString *)handle
                                             did:(nullable NSString *)did
                                            error:(NSError **)error;

- (nullable NSDictionary *)getAccountForDid:(NSString *)did error:(NSError **)error;

- (nullable NSDictionary *)loginWithHandle:(NSString *)handle
                                   password:(NSString *)password
                                    error:(NSError **)error;

- (nullable NSDictionary *)refreshAccessToken:(NSString *)refreshToken
                                       error:(NSError **)error;

- (BOOL)deleteAccount:(NSString *)did password:(NSString *)password error:(NSError **)error;

#pragma mark - Legacy Account Operations (for backward compatibility)

- (nullable NSDictionary *)createSessionForIdentifier:(NSString *)identifier
                                             password:(NSString *)password
                                              handle:(NSString *)handle
                                                  did:(NSString *)did
                                                 error:(NSError **)error;

- (nullable NSDictionary *)refreshSessionWithRefreshToken:(NSString *)refreshToken
                                                    error:(NSError **)error;

#pragma mark - Repo Operations

- (nullable NSData *)getRepoRoot:(NSString *)did error:(NSError **)error;
- (nullable NSData *)getRepoContents:(NSString *)did since:(nullable NSData *)sinceCid error:(NSError **)error;
- (BOOL)updateRepo:(NSString *)did commit:(NSData *)commitData error:(NSError **)error;

#pragma mark - Legacy Repo Operations (for backward compatibility)

- (nullable NSDictionary *)describeRepo:(NSString *)repo error:(NSError **)error;
- (nullable NSData *)getRepoDataForDid:(NSString *)did error:(NSError **)error;
- (nullable NSString *)getRepoHeadForDid:(NSString *)did error:(NSError **)error;

#pragma mark - Record Operations

- (nullable NSDictionary *)getRecord:(NSString *)uri forDid:(NSString *)did error:(NSError **)error;
- (nullable NSArray *)listRecords:(NSString *)collection 
                          forDid:(NSString *)did
                            limit:(NSUInteger)limit
                           cursor:(nullable NSString *)cursor
                           error:(NSError **)error;
- (BOOL)putRecord:(NSString *)collection 
               rkey:(NSString *)rkey 
              value:(NSDictionary *)value 
             forDid:(NSString *)did
     validationMode:(PDSValidationMode)mode
              error:(NSError **)error;

- (BOOL)deleteRecord:(NSString *)collection 
                  rkey:(NSString *)rkey 
                forDid:(NSString *)did
                 error:(NSError **)error;

#pragma mark - Legacy Record Operations (for backward compatibility)

- (nullable NSDictionary *)createRecordForDid:(NSString *)did
                                    collection:(NSString *)collection
                                       record:(NSDictionary *)record
                               validationMode:(PDSValidationMode)mode
                                        error:(NSError **)error;

- (nullable NSDictionary *)getRecordForDid:(NSString *)did
                                 collection:(NSString *)collection
                                      rkey:(NSString *)rkey
                                     error:(NSError **)error;

- (nullable NSArray *)listRecordsForDid:(NSString *)did
                              collection:(NSString *)collection
                                   limit:(NSUInteger)limit
                                  cursor:(nullable NSString *)cursor
                                   error:(NSError **)error;

- (BOOL)deleteRecordForDid:(NSString *)did
                 collection:(NSString *)collection
                      rkey:(NSString *)rkey
                     error:(NSError **)error;

- (nullable NSDictionary *)getRepoStatsForDid:(NSString *)did error:(NSError **)error;

- (BOOL)putRecordForDid:(NSString *)did
              collection:(NSString *)collection
                   rkey:(NSString *)rkey
                 record:(NSDictionary *)record
         validationMode:(PDSValidationMode)mode
                  error:(NSError **)error;

#pragma mark - Blob Operations

- (nullable NSData *)getBlob:(NSData *)cid forDid:(NSString *)did error:(NSError **)error;
- (nullable NSDictionary *)uploadBlob:(NSData *)blobData 
                               forDid:(NSString *)did 
                               mimeType:(NSString *)mimeType
                                  error:(NSError **)error;

#pragma mark - Legacy Blob Operations (for backward compatibility)

- (nullable NSDictionary *)uploadBlob:(NSData *)blobData 
                             mimeType:(NSString *)mimeType 
                                  did:(NSString *)did
                                error:(NSError **)error;

- (nullable NSDictionary *)getBlobWithCID:(NSString *)cid 
                                      did:(NSString *)did
                                    error:(NSError **)error;

- (nullable NSArray *)listBlobsForDID:(NSString *)did
                                limit:(NSUInteger)limit
                               cursor:(nullable NSString *)cursor
                                error:(NSError **)error;

- (BOOL)deleteBlobWithCID:(NSString *)cid did:(NSString *)did error:(NSError **)error;

#pragma mark - Write Operations (for backward compatibility)

- (nullable NSDictionary *)applyWrites:(NSArray *)writes 
                                 repo:(NSString *)repo 
                             validate:(BOOL)validate 
                           swapCommit:(nullable NSString *)swapCommit
                                error:(NSError **)error;

#pragma mark - Admin Operations

- (nullable NSArray *)getAllAccountsWithError:(NSError **)error;
- (BOOL)takeDownAccount:(NSString *)did reason:(NSString *)reason error:(NSError **)error;
- (BOOL)reinstateAccount:(NSString *)did error:(NSError **)error;

#pragma mark - Moderation Operations

- (NSDictionary *)moderateAccount:(NSDictionary *)params error:(NSError **)error;
- (NSDictionary *)moderateRecord:(NSDictionary *)params error:(NSError **)error;

#pragma mark - Labeling Operations

- (NSDictionary *)createLabel:(NSDictionary *)params error:(NSError **)error;
- (NSDictionary *)getLabels:(NSDictionary *)params error:(NSError **)error;

#pragma mark - Health & Metrics

- (NSDictionary<NSString *, id> *)getHealthCheck;
- (NSDictionary<NSString *, id> *)getMetrics;

@end

NS_ASSUME_NONNULL_END
