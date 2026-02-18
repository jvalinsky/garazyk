#import "PDSController.h"
#import "Database/PDSDatabase.h"
#ifdef GNUSTEP
#import "Compat/NSFileManagerCompat.h"
#endif
#import "Identity/ATProtoHandleValidator.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Monitoring/PDSHealthCheck.h"
#import "Repository/MST.h"
#import "Blob/BlobStorage.h"
#import "Blob/PDSDiskBlobProvider.h"
#import "Core/CID.h"


#import "Core/TID.h"
#import "Auth/JWT.h"
#import "Auth/JWTSigningKeyStore.h"
#import "Sync/SubscribeReposHandler.h"
#import "Repository/RepoCommit.h"
#import "Auth/OAuth2Handler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/RateLimiter.h"
#import "App/PDSConfiguration.h"
#import "App/OAuthDemo/OAuthDemoHandler.h"
#import "Core/PDSServiceContainer.h"
#import "Services/PDSAccountService.h"
#import "Services/PDSRecordService.h"
#import "Services/PDSBlobService.h"
#import "Services/PDSRepositoryService.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Debug/PDSLogger.h"
#import "App/Explore/ExploreHandler.h"
#import "App/MSTViewer/MSTViewerHandler.h"
#import "App/NodeInfo/NodeInfoHandler.h"
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonKeyDerivation.h>
#import "Lexicon/ATProtoLexiconRegistry.h"
#import "Core/ATProtoError.h"
#import "Network/PDSHttpServerBuilder.h"
#import "Admin/PDSAdminController.h"
#import "PDSApplication.h"


NSString *const kDefaultPlcServerURL = @"https://plc.directory";

#import "Email/PDSEmailProvider.h"
#import "Email/PDSMockEmailProvider.h"
#import "Email/PDSSMTPEmailProvider.h"
#import "Email/PDSResendEmailProvider.h"
#import "Email/PDSKeychainSecretsProvider.h"
#import "Email/PDSEnvironmentSecretsProvider.h"

@implementation PDSController {
    PDSApplication *_backingApplication;  // When initialized via initWithApplication:
    PDSServiceDatabases *_serviceDatabases;
    PDSDatabasePool *_userDatabasePool;
    PDSAccountService *_accountService;
    PDSRecordService *_recordService;
    PDSBlobService *_blobService;
    PDSRecordService *_serviceRecordService;
    PDSRepositoryService *_repositoryService;
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

- (PDSAdminController *)adminController {
    return _adminController;
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
        _adminController = (PDSAdminController *)application.adminController;
        _jwtMinter = application.jwtMinter;
        _httpPort = application.httpPort;
        _plcServerURL = kDefaultPlcServerURL;
        
        // Initialize internal state
        _repos = [NSMutableDictionary dictionary];
        _collections = [NSMutableDictionary dictionary];
        _repoQueue = dispatch_queue_create("com.atproto.pds.repository", DISPATCH_QUEUE_SERIAL);
        _controllerQueue = dispatch_queue_create("com.atproto.pds.controller", DISPATCH_QUEUE_SERIAL);
        _running = NO;
        
        PDS_LOG_CORE_INFO(@"PDSController initialized as facade over PDSApplication");
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
    self = [super init];
    if (self) {
        // Configure PDSLogger from PDSConfiguration if available
        PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
        if (config) {
            PDSLogger *logger = [PDSLogger sharedLogger];
            if (config.logFilePath) {
                logger.logFilePath = config.logFilePath;
            }
            logger.logLevel = config.logLevel;
            logger.logFormat = config.logFormat;
            logger.maxLogFileSize = config.maxLogFileSize;
            logger.maxLogFiles = config.maxLogFiles;
            logger.asyncLogging = config.asyncLogging;
            if (config.enabledComponents.count > 0) {
                logger.enabledComponents = [NSSet setWithArray:config.enabledComponents];
            }

            PDS_LOG_INFO_C(PDSLogComponentCore, @"PDSController initializing with data directory: %@", directory);
            
            // Configure RateLimiter
            RateLimiter *limiter = [RateLimiter sharedLimiter];
            limiter.enabled = config.rateLimitEnabled;
            // Use granular limits from configuration
            limiter.didLimit = config.rateLimitDidLimit;
            limiter.didWindowSeconds = config.rateLimitDidWindowSeconds;
            limiter.ipLimit = config.rateLimitIpLimit;
            limiter.ipWindowSeconds = config.rateLimitIpWindowSeconds;
            limiter.blobLimit = config.rateLimitBlobLimit;
            limiter.blobWindowSeconds = config.rateLimitBlobWindowSeconds;
        }

        _dataDirectory = [directory copy];
        _serviceDatabases = [[PDSServiceDatabases alloc] initWithDirectory:directory
                                                             serviceMaxSize:serviceMaxSize
                                                           didCacheMaxSize:1000
                                                         sequencerMaxSize:100];
        _userDatabasePool = [[PDSDatabasePool alloc] initWithDbDirectory:directory maxSize:userDatabaseSize];
        
        // Setup Service Container
        PDSServiceContainer *container = [PDSServiceContainer sharedContainer];
        [container reset];
        
        id<PDSEmailProvider> emailProvider = nil;
        if (config) {
            if ([config.emailProviderType isEqualToString:@"mock"]) {
                emailProvider = [[PDSMockEmailProvider alloc] init];
            } else if ([config.emailProviderType isEqualToString:@"smtp"]) {
                emailProvider = [[PDSSMTPEmailProvider alloc] initWithHost:config.emailSmtpHost ?: @"localhost"
                                                                      port:config.emailSmtpPort
                                                                  username:config.emailSmtpUsername
                                                                  password:config.emailSmtpPassword
                                                                    useTLS:config.emailSmtpUseTLS];
            } else if ([config.emailProviderType isEqualToString:@"resend"]) {
                if (config.resendFromAddress.length > 0) {
                    id<PDSSecretsProvider> secretsProvider = nil;
                    NSString *source = config.resendAPIKeySource ?: @"env";
                    
                    if ([source isEqualToString:@"keychain"]) {
                        secretsProvider = [[PDSKeychainSecretsProvider alloc] initWithService:config.resendKeychainService ?: @"com.atproto.pds.resend"];
                    } else {
                        // Default to environment variables
                        secretsProvider = [[PDSEnvironmentSecretsProvider alloc] init];
                    }
                    
                    emailProvider = [[PDSResendEmailProvider alloc] initWithSecretsProvider:secretsProvider
                                                                                fromAddress:config.resendFromAddress
                                                                                apiEndpoint:config.resendAPIEndpoint];
                    
                    PDS_LOG_INFO(@"Initialized Resend email provider (source: %@, from: %@)", source, config.resendFromAddress);
                } else {
                    PDS_LOG_WARN(@"Resend email provider requested but no from address configured.");
                }
            }
        }
        
        PDSAccountService *accountService = [[PDSAccountService alloc] initWithAccountRepository:nil
                                                                                sessionRepository:nil
                                                                                           minter:nil
                                                                                    emailProvider:emailProvider];
        accountService.databasePool = _userDatabasePool;
        accountService.serviceDatabases = _serviceDatabases;
        [container registerInstance:accountService forProtocol:@protocol(PDSAccountService)];
        
        if (emailProvider) {
            [container registerInstance:emailProvider forProtocol:@protocol(PDSEmailProvider)];
        }
        
        _accountService = [container resolveProtocol:@protocol(PDSAccountService)];
        
        // Initialize JWT Minter
        _jwtMinter = [[JWTMinter alloc] init];
        
        _httpPort = 2583;
        _jwtMinter.issuer = [[NSProcessInfo processInfo] environment][@"PDS_ISSUER"] ?: @"https://pds.local:8443";
        _jwtMinter.signingAlgorithm = @"ES256K";
        
        NSError *serverKeyError = nil;
        Secp256k1KeyPair *serverKey = [JWTSigningKeyStore loadOrCreateKeyPairForDataDirectory:_dataDirectory error:&serverKeyError];
        if (serverKeyError) {
            PDS_LOG_AUTH_WARN(@"JWT signing key load/create error: %@", serverKeyError.localizedDescription ?: @"unknown error");
        }
        _jwtMinter.privateKey = serverKey.privateKey;
        _jwtMinter.publicKey = serverKey.publicKey;
        
        _accountService.minter = _jwtMinter;
        
        _recordService = [[PDSRecordService alloc] initWithDatabasePool:_userDatabasePool];
        
        // Initialize Blob Storage Abstraction
        NSString *blobDir = [_dataDirectory stringByAppendingPathComponent:@"blobs"];
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:blobDir]) {
            [fm createDirectoryAtPath:blobDir withIntermediateDirectories:YES attributes:nil error:nil];
        }
        
        NSURL *blobURL = [NSURL fileURLWithPath:blobDir];
        PDSDiskBlobProvider *blobProvider = [[PDSDiskBlobProvider alloc] initWithStorageDirectory:blobURL];
        BlobStorage *blobStorage = [[BlobStorage alloc] initWithDatabasePool:_userDatabasePool provider:blobProvider];
        
        _blobService = [[PDSBlobService alloc] initWithDatabasePool:_userDatabasePool storage:blobStorage];
        _repositoryService = [[PDSRepositoryService alloc] initWithDatabasePool:_userDatabasePool];
        
        // Initialize Admin Controller
        _adminController = [[PDSAdminController alloc] initWithServiceDatabases:_serviceDatabases
                                                                 accountService:_accountService];
        
        _repos = [NSMutableDictionary dictionary];
        _collections = [NSMutableDictionary dictionary];
        _repoQueue = dispatch_queue_create("com.atproto.pds.repository", DISPATCH_QUEUE_SERIAL);
        _controllerQueue = dispatch_queue_create("com.atproto.pds.controller", DISPATCH_QUEUE_SERIAL);
        _plcServerURL = kDefaultPlcServerURL;
        _running = NO;



        // Load lexicons from bundle, working directory, or data directory.
        ATProtoLexiconRegistry *registry = [ATProtoLexiconRegistry sharedRegistry];
        NSArray<NSString *> *lexiconPaths = [registry searchPathsForDirectory:_dataDirectory];
        BOOL loadedAny = NO;
        for (NSString *path in lexiconPaths) {
            NSError *loadError = nil;
            if ([registry loadLexiconsFromDirectory:path error:&loadError]) {
                loadedAny = YES;
                PDS_LOG_INFO(@"Loaded lexicons from %@", path);
            } else if (loadError) {
                PDS_LOG_WARN(@"Failed to load lexicons from %@: %@", path, loadError);
            }
        }
        if (!loadedAny) {
            PDS_LOG_WARN(@"No lexicons loaded. Set PDS_LEXICON_PATH or install lexicons under ATProtoPDS/Resources/lexicons.");
        }

        PDS_LOG_CORE_INFO(@"PDS Controller initialized with single-tenant architecture");
    }
    return self;
}

#pragma mark - Server Lifecycle

- (BOOL)startServerWithError:(NSError **)error {
    // If backed by PDSApplication, delegate to it
    if (_backingApplication) {
        PDS_LOG_CORE_INFO(@"Starting server via PDSApplication...");
        BOOL result = [_backingApplication startWithError:error];
        if (result) {
            _httpPort = _backingApplication.httpPort;
            _httpServer = _backingApplication.httpServer;
            _running = YES;
        }
        return result;
    }
    
    // Legacy path: initialize everything ourselves
    PDS_LOG_CORE_INFO(@"Starting ATProto PDS server with single-tenant architecture...");
    
    // Initialize XRPC dispatcher
    _xrpcDispatcher = [XrpcDispatcher sharedDispatcher];
    if (!_subscribeReposHandler) {
        _subscribeReposHandler = [[SubscribeReposHandler alloc] initWithServiceDatabases:_serviceDatabases];
        // Inject the PDS signing key for firehose commit signatures
        _subscribeReposHandler.signingKey = _jwtMinter.privateKey;
    }
    
    // Build and configure HTTP server using builder
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
    builder.port = self.httpPort;
    builder.controller = self;
    builder.jwtMinter = _jwtMinter;
    builder.serviceDatabases = _serviceDatabases;
    builder.xrpcDispatcher = _xrpcDispatcher;
    builder.subscribeReposHandler = _subscribeReposHandler;
    builder.issuer = [NSString stringWithFormat:@"https://localhost:%lu", (unsigned long)self.httpPort];
    
    // Feature flags (all enabled by default)
    builder.enableXrpc = YES;
    builder.enableOAuth = YES;
    builder.enableExploreUI = YES;
    builder.enableOAuthDemo = YES;
    builder.enableMSTViewer = YES;
    builder.enableNodeInfo = YES;
    
    NSError *buildError = nil;
    _httpServer = [builder buildWithError:&buildError];
    if (!_httpServer) {
        PDS_LOG_CORE_ERROR(@"Failed to build HTTP server: %@", buildError);
        if (error) *error = buildError;
        return NO;
    }
    
    NSError *httpError = nil;
    if (![_httpServer startWithError:&httpError]) {
        PDS_LOG_CORE_ERROR(@"Failed to start HTTP server: %@", httpError);
        if (error) *error = httpError;
        return NO;
    }
    _httpPort = _httpServer.port;
    PDS_LOG_CORE_INFO(@"HTTP server started on port %lu", (unsigned long)_httpPort);
    PDS_LOG_CORE_INFO(@"subscribeRepos WebSocket upgrades available on HTTP port %lu", (unsigned long)_httpPort);
    
    _running = YES;
    return YES;
}

- (void)stopServer {
    // If backed by PDSApplication, delegate to it
    if (_backingApplication) {
        PDS_LOG_CORE_INFO(@"Stopping server via PDSApplication...");
        [_backingApplication stop];
        _httpServer = nil;
        _running = NO;
        return;
    }
    
    // Legacy path
    PDS_LOG_CORE_INFO(@"Stopping PDS server...");
    
    [_httpServer stop];
    [_subscribeReposHandler stop];
    
    // Close databases
    [_userDatabasePool closeAll];
    [_serviceDatabases closeAll]; // Assuming PDSServiceDatabases has a closeAll method
    
    // Flush and close logger to release file handles in the data directory
    [[PDSLogger sharedLogger] flush];
    [[PDSLogger sharedLogger] closeLogFile];
    
    PDS_LOG_CORE_INFO(@"PDS server stopped.");
    _running = NO;
}

#pragma mark - Account Operations

- (nullable NSDictionary *)createAccountForEmail:(NSString *)email
                                           password:(NSString *)password
                                            handle:(NSString *)handle
                                                did:(nullable NSString *)did
                                               error:(NSError **)error {
    return [_accountService createAccountForEmail:email
                                         password:password
                                          handle:handle
                                              did:did
                                             error:error];
}

- (nullable NSDictionary *)getAccountForDid:(NSString *)did error:(NSError **)error {
    return [_accountService getAccountForDid:did error:error];
}

- (nullable NSDictionary *)loginWithHandle:(NSString *)handle
                                   password:(NSString *)password
                                      error:(NSError **)error {
    return [_accountService loginWithHandle:handle
                                  password:password
                                     error:error];
}

- (nullable NSDictionary *)refreshAccessToken:(NSString *)refreshToken error:(NSError **)error {
    return [_accountService refreshAccessToken:refreshToken error:error];
}

- (BOOL)deleteAccount:(NSString *)did password:(NSString *)password error:(NSError **)error {
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

- (nullable NSDictionary *)refreshSessionWithRefreshToken:(NSString *)refreshToken
                                                     error:(NSError **)error {
    return [self refreshAccessToken:refreshToken error:error];
}

#pragma mark - Repo Operations

- (nullable NSData *)getRepoRoot:(NSString *)did error:(NSError **)error {
    return [_repositoryService getRepoRoot:did error:error];
}

- (nullable NSData *)getRepoContents:(NSString *)did since:(nullable NSString *)sinceRev error:(NSError **)error {
    return [_repositoryService getRepoContents:did since:sinceRev error:error];
}

- (BOOL)updateRepo:(NSString *)did commit:(NSData *)commitData error:(NSError **)error {
    return [_repositoryService updateRepo:did commit:commitData error:error];
}

#pragma mark - Legacy Repo Operations (for backward compatibility)

- (nullable NSDictionary *)describeRepo:(NSString *)repo error:(NSError **)error {
    NSData *root = [self getRepoRoot:repo error:error];
    
    NSDictionary *stats = [_recordService getRepoStatsForDid:repo error:nil];
    NSDictionary *account = [_accountService getAccountForDid:repo error:nil];
    
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"did"] = repo;
    if (root) {
        result[@"root"] = [root base64EncodedStringWithOptions:0];
    }
    
    if (account[@"handle"]) {
        result[@"handle"] = account[@"handle"];
    }
    
    if (stats[@"collections"]) {
        NSMutableArray *colNames = [NSMutableArray array];
        for (NSDictionary *col in stats[@"collections"]) {
            if (col[@"collection"]) {
                [colNames addObject:col[@"collection"]];
            }
        }
        result[@"collections"] = colNames;
    } else {
        result[@"collections"] = @[];
    }
    
    if (stats[@"recordCount"]) {
        result[@"recordCount"] = stats[@"recordCount"];
    }
    
    return [result copy];
}

- (nullable NSData *)getRepoDataForDid:(NSString *)did error:(NSError **)error {
    return [self getRepoContents:did since:nil error:error];
}

- (nullable NSString *)getRepoHeadForDid:(NSString *)did error:(NSError **)error {
    NSData *root = [self getRepoRoot:did error:error];
    if (!root) return nil;
    // Use CID's base32 encoding utility
    return [CID base32Encode:root];
}

#pragma mark - Record Operations

- (nullable NSDictionary *)getRecord:(NSString *)uri forDid:(NSString *)did error:(NSError **)error {
    return [_recordService getRecord:uri forDid:did error:error];
}

- (nullable NSArray *)listRecords:(NSString *)collection
                           forDid:(NSString *)did
                             limit:(NSUInteger)limit
                            cursor:(nullable NSString *)cursor
                            error:(NSError **)error {
    return [_recordService listRecords:collection forDid:did limit:limit cursor:cursor error:error];
}

- (BOOL)putRecord:(NSString *)collection
              rkey:(NSString *)rkey
             value:(NSDictionary *)value
            forDid:(NSString *)did
    validationMode:(PDSValidationMode)mode
             error:(NSError **)error {
    return [_recordService putRecord:collection rkey:rkey value:value forDid:did validationMode:mode error:error];
}

- (BOOL)deleteRecord:(NSString *)collection
                  rkey:(NSString *)rkey
                forDid:(NSString *)did
                 error:(NSError **)error {
    return [_recordService deleteRecord:collection rkey:rkey forDid:did error:error];
}

- (nullable NSDictionary *)getRepoStatsForDid:(NSString *)did error:(NSError **)error {
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
    if (!success) return nil;

    // Use DAG-CBOR for record CID calculation
    NSError *cborError = nil;
    NSData *recordData = [ATProtoCBORSerialization encodeDataWithJSONObject:record error:&cborError];
    
    if (!recordData) {
        // Fallback to JSON if CBOR fails (shouldn't happen for valid JSON types)
        recordData = [NSJSONSerialization dataWithJSONObject:record options:0 error:nil];
    }
    
    NSData *digest = [CID sha256Digest:recordData];
    CID *cid = [CID cidWithMultihash:digest codec:0x71]; // Use dag-cbor codec
    
    return @{
        @"uri": [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey],
        @"cid": cid.stringValue ?: @"bafkreiplaceholder"
    };
}

- (nullable NSDictionary *)getRecordForDid:(NSString *)did
                                 collection:(NSString *)collection
                                      rkey:(NSString *)rkey
                                     error:(NSError **)error {
    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
    return [self getRecord:uri forDid:did error:error];
}

- (nullable NSArray *)listRecordsForDid:(NSString *)did
                              collection:(NSString *)collection
                                   limit:(NSUInteger)limit
                                  cursor:(nullable NSString *)cursor
                                   error:(NSError **)error {
    return [self listRecords:collection forDid:did limit:limit cursor:cursor error:error];
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
    return [self putRecord:collection rkey:rkey value:record forDid:did validationMode:mode error:error];
}

#pragma mark - Blob Operations

- (nullable NSData *)getBlob:(NSData *)cid forDid:(NSString *)did error:(NSError **)error {
    return [_blobService getBlob:cid forDid:did error:error];
}

- (nullable NSDictionary *)uploadBlob:(NSData *)blobData
                               forDid:(NSString *)did
                              mimeType:(NSString *)mimeType
                                 error:(NSError **)error {
    return [_blobService uploadBlob:blobData forDid:did mimeType:mimeType error:error];
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
    return [_blobService listBlobsForDID:did limit:limit cursor:cursor error:error];
}

- (BOOL)deleteBlobWithCID:(NSString *)cid did:(NSString *)did error:(NSError **)error {
    return [_blobService deleteBlobWithCID:cid did:did error:error];
}

#pragma mark - Write Operations (for backward compatibility)

- (nullable NSDictionary *)applyWrites:(NSArray *)writes
                                 repo:(NSString *)repo
                             validate:(BOOL)validate
                           swapCommit:(nullable NSString *)swapCommit
                                error:(NSError **)error {
    return [_recordService applyWrites:writes
                                forDid:repo
                              validate:validate
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
        @"timestamp": @([[NSDate date] timeIntervalSince1970]),
        @"user_databases": [_userDatabasePool collectMetrics] ?: @{},
        @"service_databases": @{}
    };
}

#pragma mark - Admin Operations

- (nullable NSArray *)getAllAccountsWithError:(NSError **)error {
    return [_accountService getAllAccountsWithError:error];
}



- (BOOL)takeDownAccount:(NSString *)did reason:(NSString *)reason error:(NSError **)error {
    return [_adminController takeDownAccount:did reason:reason error:error];
}

- (BOOL)reinstateAccount:(NSString *)did error:(NSError **)error {
    return [_adminController reinstateAccount:did error:error];
}

- (BOOL)isAccountTakedownActive:(NSString *)did error:(NSError **)error {
    return [_adminController isAccountTakedownActive:did error:error];
}

#pragma mark - Moderation Operations

- (NSDictionary *)moderateAccount:(NSDictionary *)params error:(NSError **)error {
    return [_adminController moderateAccount:params error:error];
}

- (NSDictionary *)moderateRecord:(NSDictionary *)params error:(NSError **)error {
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
