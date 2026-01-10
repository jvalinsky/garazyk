#import <Foundation/Foundation.h>

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
@class PDSRecordService;
@class PDSBlobService;
@class PDSRepositoryService;

extern NSString * const PDSControllerErrorDomain;

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

@interface PDSController : NSObject

@property (nonatomic, copy, readonly) NSString *dataDirectory;
@property (nonatomic, copy) NSString *plcServerURL;
@property (nonatomic, assign, readonly, getter=isRunning) BOOL running;
@property (nonatomic, strong, readonly) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, strong, readonly) PDSDatabasePool *userDatabasePool;
@property (nonatomic, strong, readonly) PDSAccountService *accountService;
@property (nonatomic, strong, readonly) PDSRecordService *recordService;
@property (nonatomic, strong, readonly) PDSBlobService *blobService;
@property (nonatomic, strong, readonly) PDSRepositoryService *repositoryService;

- (nullable PDSDatabase *)serviceDatabaseWithError:(NSError **)error;

// NOTE: The 'database' property is deprecated in the single-tenant architecture
// It returns nil to maintain API compatibility with code that expects it
// Use 'serviceDatabases' and 'userDatabasePool' instead
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
              error:(NSError **)error;
- (BOOL)deleteRecord:(NSString *)collection 
                  rkey:(NSString *)rkey 
                forDid:(NSString *)did
                 error:(NSError **)error;

#pragma mark - Legacy Record Operations (for backward compatibility)

- (nullable NSDictionary *)createRecordForDid:(NSString *)did
                                    collection:(NSString *)collection
                                       record:(NSDictionary *)record
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

- (BOOL)putRecordForDid:(NSString *)did
              collection:(NSString *)collection
                   rkey:(NSString *)rkey
                 record:(NSDictionary *)record
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
