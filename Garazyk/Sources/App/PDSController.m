#import "PDSController.h"
#import "Blob/BlobStorage.h"
#import "Blob/PDSDiskBlobProvider.h"
#import "Core/CID.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Monitoring/PDSHealthCheck.h"
#import "Database/PDSDatabase.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/Service/ServiceDatabases.h"
#import "Identity/ATProtoHandleValidator.h"
#import "Repository/MST.h"

#import "Admin/PDSAdminController.h"
#import "App/Explore/ExploreHandler.h"
#import "App/MSTViewer/MSTViewerHandler.h"
#import "App/NodeInfo/NodeInfoHandler.h"
#import "App/OAuthDemo/OAuthDemoHandler.h"
#import "App/PDSConfiguration.h"
#import "Auth/JWT.h"
#import "Auth/OAuth2Handler.h"
#import "Auth/PDSKeyManagerFactory.h"
#import "Auth/Secp256k1.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/ATProtoError.h"
#import "Core/PDSServiceContainer.h"
#import "Core/TID.h"
#import "Debug/PDSLogger.h"
#import "Lexicon/ATProtoLexiconRegistry.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import "Network/PDSHttpServerBuilder.h"
#import "Network/RateLimiter.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcMethodRegistry.h"
#import "PDSApplication.h"
#import "Repository/RepoCommit.h"
#import "Services/PDS/PDSAccountService.h"
#import "Services/PDS/PDSBlobService.h"
#import "Services/PDS/PDSRecordService.h"
#import "Services/PDS/PDSRelayService.h"
#import "Services/PDS/PDSRepositoryService.h"
#import "Sync/Firehose/SubscribeReposHandler.h"
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonKeyDerivation.h>

NSString *const kDefaultPlcServerURL = @"https://plc.directory";

#import "Email/PDSEmailProvider.h"
#import "Email/PDSEnvironmentSecretsProvider.h"
#import "Email/PDSKeychainSecretsProvider.h"
#import "Email/PDSMockEmailProvider.h"
#import "Email/PDSResendEmailProvider.h"
#import "Email/PDSSMTPEmailProvider.h"

@implementation PDSController {
  PDSApplication
      *_backingApplication; // When initialized via initWithApplication:
  PDSServiceDatabases *_serviceDatabases;
  PDSDatabasePool *_userDatabasePool;
  PDSAccountService *_accountService;
  PDSRecordService *_recordService;
  PDSBlobService *_blobService;
  PDSRecordService *_serviceRecordService;
  PDSRepositoryService *_repositoryService;
  PDSRelayService *_relayService;
  PDSAdminController *_adminController;
  JWTMinter *_jwtMinter;
  NSMutableDictionary<NSString *, MST *> *_repos;
  NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *_collections;
  dispatch_queue_t _repoQueue;
  dispatch_queue_t _controllerQueue;
  SubscribeReposHandler *_subscribeReposHandler;
  HttpServer *_httpServer;
  XrpcDispatcher *_xrpcDispatcher;
  NSString *_dataDirectory;
  BOOL _running;
}

- (NSString *)dataDirectory {
  return _dataDirectory;
}

- (PDSApplication *)application {
  return _backingApplication;
}

- (PDSAdminController *)adminController {
  return _adminController;
}

- (SubscribeReposHandler *)subscribeReposHandler {
  if (_backingApplication) {
    return _backingApplication.subscribeReposHandler;
  }
  return _subscribeReposHandler;
}

- (PDSRelayService *)relayService {
  return _relayService;
}

- (BOOL)isRunning {
  if (_backingApplication) {
    return _backingApplication.isRunning;
  }
  return _running;
}

- (NSUInteger)wsPort {
  return self.httpPort;
}

- (id)database {
  return nil;
}

- (instancetype)initWithApplication:(PDSApplication *)application {
  self = [super init];
  if (self) {
    _backingApplication = application;

    // Reference application's components
    _dataDirectory = application.dataDirectory;
    _serviceDatabases = application.serviceDatabases;
    _userDatabasePool = application.userDatabasePool;
    _accountService = (PDSAccountService *)application.accountService;
    _recordService = application.recordService;
    _blobService = application.blobService;
    _repositoryService = application.repositoryService;
    _relayService = application.relayService;
    _adminController = (PDSAdminController *)application.adminController;
    _jwtMinter = application.jwtMinter;
    _httpPort = application.httpPort;
    _plcServerURL = kDefaultPlcServerURL;

    // Initialize internal state
    _repos = [NSMutableDictionary dictionary];
    _collections = [NSMutableDictionary dictionary];
    _repoQueue = dispatch_queue_create("com.atproto.pds.repository",
                                       DISPATCH_QUEUE_SERIAL);
    _controllerQueue = dispatch_queue_create("com.atproto.pds.controller",
                                             DISPATCH_QUEUE_SERIAL);
    _running = NO;

    PDS_LOG_CORE_INFO(
        @"PDSController initialized as facade over PDSApplication");
  }
  return self;
}

+ (instancetype)sharedController {
  static PDSController *shared = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    // Use PDSApplication as the backing implementation
    shared = [PDSApplication sharedApplication].legacyController;
  });
  return shared;
}

- (instancetype)initWithDirectory:(NSString *)directory
                   serviceMaxSize:(NSUInteger)serviceMaxSize
                 userDatabaseSize:(NSUInteger)userDatabaseSize {
  PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
  PDSApplication *application =
      [[PDSApplication alloc] initWithConfiguration:config
                                      dataDirectory:directory
                                     serviceMaxSize:serviceMaxSize
                                userDatabaseMaxSize:userDatabaseSize
                                    didCacheMaxSize:1000
                                  sequencerMaxSize:100];
  if (application.legacyController) {
    return application.legacyController;
  }
  return [self initWithApplication:application];
}

#pragma mark - Server Lifecycle

- (BOOL)startServerWithError:(NSError **)error {
  if (!_backingApplication) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"PDSControllerErrorDomain"
                     code:1
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"PDSController requires a backing PDSApplication"
                 }];
    }
    return NO;
  }
  PDS_LOG_CORE_INFO(@"Starting server via PDSApplication...");
  BOOL result = [_backingApplication startWithError:error];
  if (result) {
    _httpPort = _backingApplication.httpPort;
    _httpServer = _backingApplication.httpServer;
    _running = YES;
  }
  return result;
}

- (void)stopServer {
  if (!_backingApplication) {
    return;
  }
  PDS_LOG_CORE_INFO(@"Stopping server via PDSApplication...");
  [_backingApplication stop];
  _httpServer = nil;
  _running = NO;
}

#pragma mark - Account Operations

- (nullable NSDictionary *)createAccountForEmail:(NSString *)email
                                        password:(NSString *)password
                                          handle:(NSString *)handle
                                             did:(nullable NSString *)did
                                           error:(NSError **)error {
  NSDictionary *result = [_accountService createAccountForEmail:email
                                                       password:password
                                                         handle:handle
                                                            did:did
                                                          error:error];
  if (!result) {
    return nil;
  }

  // Create the initial empty repo commit so the account is discoverable via
  // sync/listRepos.
  NSString *createdDid = result[@"did"];
  if ([createdDid isKindOfClass:[NSString class]] && createdDid.length > 0) {
    NSError *initError = nil;
    if (![_repositoryService initializeRepoForDid:createdDid
                                            error:&initError]) {
      PDS_LOG_ERROR(
          @"Failed to initialize repo for DID %@ during account creation: %@",
          createdDid, initError.localizedDescription ?: @"unknown error");
    }
  }

  return result;
}

- (nullable NSDictionary *)getAccountForDid:(NSString *)did
                                      error:(NSError **)error {
  return [_accountService getAccountForDid:did error:error];
}

- (nullable NSDictionary *)loginWithHandle:(NSString *)handle
                                  password:(NSString *)password
                                     error:(NSError **)error {
  return [_accountService loginWithHandle:handle password:password error:error];
}

- (nullable NSDictionary *)refreshAccessToken:(NSString *)refreshToken
                                        error:(NSError **)error {
  return [_accountService refreshAccessToken:refreshToken error:error];
}

- (BOOL)deleteAccount:(NSString *)did
             password:(NSString *)password
                error:(NSError **)error {
  return [_accountService deleteAccount:did password:password error:error];
}

#pragma mark - Legacy Account Operations (for backward compatibility)

- (nullable NSDictionary *)createSessionForIdentifier:(NSString *)identifier
                                             password:(NSString *)password
                                               handle:(NSString *)handle
                                                  did:(NSString *)did
                                                error:(NSError **)error {
  (void)handle;
  (void)did;
  return [_accountService loginWithIdentifier:identifier
                                     password:password
                                        error:error];
}

- (nullable NSDictionary *)refreshSessionWithRefreshToken:
                               (NSString *)refreshToken
                                                    error:(NSError **)error {
  return [self refreshAccessToken:refreshToken error:error];
}

#pragma mark - Repo Operations

- (nullable NSData *)getRepoRoot:(NSString *)did error:(NSError **)error {
  return [_repositoryService getRepoRoot:did error:error];
}

- (nullable NSData *)getRepoContents:(NSString *)did
                               since:(nullable NSString *)sinceRev
                               error:(NSError **)error {
  return [_repositoryService getRepoContents:did since:sinceRev error:error];
}

- (BOOL)updateRepo:(NSString *)did
            commit:(NSData *)commitData
             error:(NSError **)error {
  return [_repositoryService updateRepo:did commit:commitData error:error];
}

#pragma mark - Legacy Repo Operations (for backward compatibility)

- (nullable NSDictionary *)describeRepo:(NSString *)repo
                                  error:(NSError **)error {
  NSDictionary *latest =
      [_repositoryService getLatestCommitForDid:repo error:error];
  NSDictionary *stats = [_recordService getRepoStatsForDid:repo error:nil];
  NSDictionary *account = [_accountService getAccountForDid:repo error:nil];

  NSMutableDictionary *result = [NSMutableDictionary dictionary];
  if (repo) {
    [result setObject:repo forKey:@"did"];
  }

  NSString *rootCid = latest[@"cid"];
  if (rootCid) {
    [result setObject:rootCid forKey:@"root"];
  }

  if (account[@"handle"]) {
    [result setObject:account[@"handle"] forKey:@"handle"];
  }

  if (stats[@"collections"]) {
    NSMutableArray *colNames = [NSMutableArray array];
    for (NSDictionary *col in stats[@"collections"]) {
      if (col[@"collection"]) {
        [colNames addObject:col[@"collection"]];
      }
    }
    [result setObject:colNames forKey:@"collections"];
  } else {
    [result setObject:@[] forKey:@"collections"];
  }

  if (stats[@"recordCount"]) {
    [result setObject:stats[@"recordCount"] forKey:@"recordCount"];
  }

  return [result copy];
}

- (nullable NSData *)getRepoDataForDid:(NSString *)did error:(NSError **)error {
  return [self getRepoContents:did since:nil error:error];
}

- (nullable NSString *)getRepoHeadForDid:(NSString *)did
                                   error:(NSError **)error {
  NSDictionary *latest =
      [_repositoryService getLatestCommitForDid:did error:error];
  if (!latest)
    return nil;
  return latest[@"cid"];
}

#pragma mark - Record Operations

- (nullable NSDictionary *)getRecord:(NSString *)uri
                              forDid:(NSString *)did
                               error:(NSError **)error {
  return [_recordService getRecord:uri forDid:did error:error];
}

- (nullable NSArray *)listRecords:(NSString *)collection
                           forDid:(NSString *)did
                            limit:(NSUInteger)limit
                           cursor:(nullable NSString *)cursor
                            error:(NSError **)error {
  return [_recordService listRecords:collection
                              forDid:did
                               limit:limit
                              cursor:cursor
                               error:error];
}

- (BOOL)putRecord:(NSString *)collection
              rkey:(NSString *)rkey
             value:(NSDictionary *)value
            forDid:(NSString *)did
    validationMode:(PDSValidationMode)mode
             error:(NSError **)error {
  return [_recordService putRecord:collection
                              rkey:rkey
                             value:value
                            forDid:did
                    validationMode:mode
                             error:error];
}

- (BOOL)deleteRecord:(NSString *)collection
                rkey:(NSString *)rkey
              forDid:(NSString *)did
               error:(NSError **)error {
  return
      [_recordService deleteRecord:collection rkey:rkey forDid:did error:error];
}

- (nullable NSDictionary *)getRepoStatsForDid:(NSString *)did
                                        error:(NSError **)error {
  return [_recordService getRepoStatsForDid:did error:error];
}

#pragma mark - Legacy Record Operations (for backward compatibility)

- (nullable NSDictionary *)createRecordForDid:(NSString *)did
                                   collection:(NSString *)collection
                                       record:(NSDictionary *)record
                               validationMode:(PDSValidationMode)mode
                                        error:(NSError **)error {
  NSString *rkey = [TID tid].stringValue;
  BOOL success = [self putRecord:collection
                            rkey:rkey
                           value:record
                          forDid:did
                  validationMode:mode
                           error:error];
  if (!success)
    return nil;
  NSLog(@"[PDSController] Service call success, calculating record CID...");

  // Use DAG-CBOR for record CID calculation
  NSError *cborError = nil;
  NSLog(@"[PDSController] Encoding record with CBOR...");
  NSData *recordData =
      [ATProtoCBORSerialization encodeDataWithJSONObject:record
                                                   error:&cborError];

  if (!recordData) {
    NSLog(@"[PDSController] CBOR encoding failed, falling back to JSON...");
    // Fallback to JSON if CBOR fails (shouldn't happen for valid JSON types)
    recordData =
        [NSJSONSerialization dataWithJSONObject:record options:0 error:nil];
  }

  if (!recordData) {
    NSLog(@"[PDSController] CRITICAL: Record data is NIL after fallback!");
  } else {
    NSLog(@"[PDSController] Record data length: %lu",
          (unsigned long)recordData.length);
  }

  NSLog(@"[PDSController] Calculating SHA-256 digest...");
  NSData *digest = [CID sha256Digest:recordData];
  NSLog(@"[PDSController] Digest calculated: %@",
        digest ? [digest description] : @"NIL");

  NSLog(@"[PDSController] Creating CID object...");
  CID *cid = [CID cidWithDigest:digest codec:0x71]; // Use dag-cbor codec
  NSLog(@"[PDSController] CID string value: %@", cid.stringValue);

  NSDictionary *result = @{
    @"uri" :
        [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey],
    @"cid" : cid.stringValue ?: @"bafkreiplaceholder"
  };
  NSLog(@"[PDSController] Returning result: %@", result);
  return result;
}

- (nullable NSDictionary *)getRecordForDid:(NSString *)did
                                collection:(NSString *)collection
                                      rkey:(NSString *)rkey
                                     error:(NSError **)error {
  NSString *uri =
      [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
  return [self getRecord:uri forDid:did error:error];
}

- (nullable NSArray *)listRecordsForDid:(NSString *)did
                             collection:(NSString *)collection
                                  limit:(NSUInteger)limit
                                 cursor:(nullable NSString *)cursor
                                  error:(NSError **)error {
  return [self listRecords:collection
                    forDid:did
                     limit:limit
                    cursor:cursor
                     error:error];
}

- (BOOL)deleteRecordForDid:(NSString *)did
                collection:(NSString *)collection
                      rkey:(NSString *)rkey
                     error:(NSError **)error {
  return [self deleteRecord:collection rkey:rkey forDid:did error:error];
}

- (BOOL)putRecordForDid:(NSString *)did
             collection:(NSString *)collection
                   rkey:(NSString *)rkey
                 record:(NSDictionary *)record
         validationMode:(PDSValidationMode)mode
                  error:(NSError **)error {
  return [self putRecord:collection
                    rkey:rkey
                   value:record
                  forDid:did
          validationMode:mode
                   error:error];
}

#pragma mark - Blob Operations

- (nullable NSData *)getBlob:(NSData *)cid
                      forDid:(NSString *)did
                       error:(NSError **)error {
  return [_blobService getBlob:cid forDid:did error:error];
}

- (nullable NSDictionary *)uploadBlob:(NSData *)blobData
                               forDid:(NSString *)did
                             mimeType:(NSString *)mimeType
                                error:(NSError **)error {
  return [_blobService uploadBlob:blobData
                           forDid:did
                         mimeType:mimeType
                            error:error];
}

#pragma mark - Legacy Blob Operations (for backward compatibility)

- (nullable NSDictionary *)uploadBlob:(NSData *)blobData
                             mimeType:(NSString *)mimeType
                                  did:(NSString *)did
                                error:(NSError **)error {
  return [self uploadBlob:blobData forDid:did mimeType:mimeType error:error];
}

- (nullable NSDictionary *)getBlobWithCID:(NSString *)cid
                                      did:(NSString *)did
                                    error:(NSError **)error {
  return [_blobService getBlobWithCID:cid did:did error:error];
}

- (nullable NSArray *)listBlobsForDID:(NSString *)did
                                limit:(NSUInteger)limit
                               cursor:(nullable NSString *)cursor
                                error:(NSError **)error {
  return
      [_blobService listBlobsForDID:did limit:limit cursor:cursor error:error];
}

- (BOOL)deleteBlobWithCID:(NSString *)cid
                      did:(NSString *)did
                    error:(NSError **)error {
  return [_blobService deleteBlobWithCID:cid did:did error:error];
}

#pragma mark - Write Operations (for backward compatibility)

- (nullable NSDictionary *)applyWrites:(NSArray *)writes
                                  repo:(NSString *)repo
                              validate:(BOOL)validate
                            swapCommit:(nullable NSString *)swapCommit
                                 error:(NSError **)error {
  PDSValidationMode mode =
      validate ? PDSValidationModeRequired : PDSValidationModeOff;
  return [_recordService applyWrites:writes
                              forDid:repo
                      validationMode:mode
                          swapCommit:swapCommit
                               error:error];
}

#pragma mark - Health & Metrics

- (NSDictionary<NSString *, id> *)getHealthCheck {
  return [[PDSHealthCheck sharedInstance] performHealthCheck];
}

- (nullable PDSDatabase *)serviceDatabaseWithError:(NSError **)error {
  return [_serviceDatabases serviceDatabaseWithError:error];
}

- (NSDictionary<NSString *, id> *)getMetrics {
  return @{
    @"timestamp" : @([[NSDate date] timeIntervalSince1970]),
    @"user_databases" : [_userDatabasePool collectMetrics] ?: @{},
    @"service_databases" : @{}
  };
}

#pragma mark - Admin Operations

- (nullable NSArray *)getAllAccountsWithError:(NSError **)error {
  return [_accountService getAllAccountsWithError:error];
}

- (BOOL)takeDownAccount:(NSString *)did
                 reason:(NSString *)reason
                  error:(NSError **)error {
  return [_adminController takeDownAccount:did reason:reason error:error];
}

- (BOOL)reinstateAccount:(NSString *)did error:(NSError **)error {
  return [_adminController reinstateAccount:did error:error];
}

- (BOOL)isAccountTakedownActive:(NSString *)did error:(NSError **)error {
  return [_adminController isAccountTakedownActive:did error:error];
}

#pragma mark - Moderation Operations

- (NSDictionary *)moderateAccount:(NSDictionary *)params
                            error:(NSError **)error {
  return [_adminController moderateAccount:params error:error];
}

- (NSDictionary *)moderateRecord:(NSDictionary *)params
                           error:(NSError **)error {
  return [_adminController moderateRecord:params error:error];
}

#pragma mark - Labeling Operations

- (NSDictionary *)createLabel:(NSDictionary *)params error:(NSError **)error {
  return [_adminController createLabel:params error:error];
}

- (NSDictionary *)getLabels:(NSDictionary *)params error:(NSError **)error {
  return [_adminController getLabels:params error:error];
}

@end
