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
#import "Repository/MSTPersistence.h"
#import "Repository/MSTPersistence.h"
#import "Blob/BlobStorage.h"
#import "Blob/PDSDiskBlobProvider.h"
#import "Core/CID.h"
#import "Core/TID.h"
#import "Auth/JWT.h"
#import "Sync/SubscribeReposHandler.h"
#import "Sync/WebSocketServer.h"
#import "Repository/RepoCommit.h"
#import "Auth/OAuth2Handler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/RateLimiter.h"
#import "App/PDSConfiguration.h"
#import "Services/PDSAccountService.h"
#import "Services/PDSRecordService.h"
#import "Services/PDSBlobService.h"
#import "Services/PDSRepositoryService.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Debug/PDSLogger.h"
#import "App/Explore/ExploreHandler.h"
#import "App/MSTViewer/MSTViewerHandler.h"
#import "App/NodeInfo/NodeInfoHandler.h"
#import <os/log.h>
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonKeyDerivation.h>
#import "Lexicon/ATProtoLexiconRegistry.h"

NSString *const PDSControllerErrorDomain = @"com.atproto.pds.controller";
NSString *const kDefaultPlcServerURL = @"https://plc.directory";

@implementation PDSController {
    os_log_t _log;
    PDSServiceDatabases *_serviceDatabases;
    PDSDatabasePool *_userDatabasePool;
    PDSAccountService *_accountService;
    PDSRecordService *_recordService;
    PDSBlobService *_blobService;
    PDSRecordService *_serviceRecordService;
    PDSRepositoryService *_repositoryService;
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

- (id)database {
    return nil;
}

+ (instancetype)sharedController {
    static PDSController *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PDSController alloc] initWithDirectory:[self defaultDataDirectory]
                                           serviceMaxSize:100
                                         userDatabaseSize:30000];
    });
    return shared;
}

+ (NSString *)defaultDataDirectory {
#if defined(__APPLE__)
    NSArray *urls = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory 
                                                               inDomains:NSUserDomainMask];
    NSURL *appSupport = [urls count] > 0 ? urls[0] : nil;
    return [[appSupport URLByAppendingPathComponent:@"ATProtoPDS"] path];
#else
    // Linux: use ~/.local/share/ATProtoPDS
    NSString *home = NSHomeDirectory();
    return [home stringByAppendingPathComponent:@".local/share/ATProtoPDS"];
#endif
}

- (NSArray<NSString *> *)lexiconSearchPathsForDirectory:(NSString *)dataDirectory {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableOrderedSet<NSString *> *paths = [NSMutableOrderedSet orderedSet];
    NSString *overridePath = [NSProcessInfo processInfo].environment[@"PDS_LEXICON_PATH"];
    if (overridePath.length > 0) {
        [paths addObject:overridePath];
    }

    NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"lexicons" ofType:nil];
    if (bundlePath.length > 0) {
        [paths addObject:bundlePath];
    }

    NSString *cwd = fm.currentDirectoryPath ?: @"";
    NSArray<NSString *> *candidates = @[
        @"ATProtoPDS/Resources/lexicons",
        @"Resources/lexicons",
        @"lexicons",
        @"../ATProtoPDS/Resources/lexicons",
        @"../../ATProtoPDS/Resources/lexicons",
        @"../../../ATProtoPDS/Resources/lexicons"
    ];
    for (NSString *candidate in candidates) {
        NSString *path = [cwd stringByAppendingPathComponent:candidate];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:path isDirectory:&isDir] && isDir) {
            [paths addObject:path];
        }
    }

    if (dataDirectory.length > 0) {
        NSString *customPath = [dataDirectory stringByAppendingPathComponent:@"lexicons"];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:customPath isDirectory:&isDir] && isDir) {
            [paths addObject:customPath];
        }
    }

    return paths.array;
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
        _accountService = [[PDSAccountService alloc] initWithDatabasePool:_userDatabasePool];
        _accountService.serviceDatabases = _serviceDatabases;
        
        // Initialize JWT Minter
        _jwtMinter = [[JWTMinter alloc] init];
        
        _httpPort = 2583;
        _wsPort = 8081;
        _jwtMinter.issuer = [[NSProcessInfo processInfo] environment][@"PDS_ISSUER"] ?: @"https://pds.local:8443";
        _jwtMinter.signingAlgorithm = @"ES256";
        
        // Use a generated server key for now
        // In production, this should be loaded from secure storage or config
        Secp256k1KeyPair *serverKey = [[Secp256k1 shared] generateKeyPairWithError:nil];
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
        _repos = [NSMutableDictionary dictionary];
        _collections = [NSMutableDictionary dictionary];
        _repoQueue = dispatch_queue_create("com.atproto.pds.repository", DISPATCH_QUEUE_SERIAL);
        _controllerQueue = dispatch_queue_create("com.atproto.pds.controller", DISPATCH_QUEUE_SERIAL);
        _plcServerURL = kDefaultPlcServerURL;
        _running = NO;



        // Load lexicons from bundle, working directory, or data directory.
        ATProtoLexiconRegistry *registry = [ATProtoLexiconRegistry sharedRegistry];
        NSArray<NSString *> *lexiconPaths = [self lexiconSearchPathsForDirectory:_dataDirectory];
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

        _log = os_log_create("com.atproto.pds", "PDSController");
        os_log_info(_log, "PDS Controller initialized with single-tenant architecture");
    }
    return self;
}

#pragma mark - Server Lifecycle

- (BOOL)startServerWithError:(NSError **)error {
    os_log_info(_log, "Starting ATProto PDS server with single-tenant architecture...");
    
    // Start HTTP server with XRPC handlers
    _httpServer = [HttpServer serverWithPort:self.httpPort];
    
    // Add OAuth2 routes
    OAuth2Handler *oauthHandler = [[OAuth2Handler alloc] initWithDatabase:[self serviceDatabaseWithError:nil]];
    oauthHandler.minter = _jwtMinter;
    [oauthHandler registerRoutesWithServer:_httpServer];
    
    _xrpcDispatcher = [XrpcDispatcher sharedDispatcher];
    
    [XrpcMethodRegistry registerMethodsWithDispatcher:_xrpcDispatcher controller:self];
    
    __weak typeof(self) weakSelf = self;
    [_httpServer addHandlerForPath:@"/xrpc" handler:^(HttpRequest *request, HttpResponse *response) {
        PDSController *strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf->_xrpcDispatcher handleRequest:request response:response];
        }
    }];

    [_httpServer addHandlerForPath:@"/xrpc/" handler:^(HttpRequest *request, HttpResponse *response) {
        PDSController *strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf->_xrpcDispatcher handleRequest:request response:response];
        }
    }];

    [_httpServer addRoute:@"*" path:@"/xrpc/:method" handler:^(HttpRequest *request, HttpResponse *response) {
        PDSController *strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf->_xrpcDispatcher handleRequest:request response:response];
        }
    }];

    // Explore UI + API
    ExploreHandler *exploreHandler = [ExploreHandler sharedHandler];
    [exploreHandler setController:self];

    [_httpServer addHandlerForPath:@"/explore" handler:^(HttpRequest *request, HttpResponse *response) {
        [exploreHandler handleRequest:request response:response];
    }];

    [_httpServer addRoute:@"GET" path:@"/explore/api/:endpoint" handler:^(HttpRequest *request, HttpResponse *response) {
        [exploreHandler handleRequest:request response:response];
    }];

    // Wildcard for static assets (css, js, etc.)
    fprintf(stderr, "Registering wildcard route for /explore/*\n");
    [_httpServer addRoute:@"GET" path:@"/explore/*" handler:^(HttpRequest *request, HttpResponse *response) {
        [exploreHandler handleRequest:request response:response];
    }];
    
    // Fallback exact route for debugging
    [_httpServer addRoute:@"GET" path:@"/explore/css/style.css" handler:^(HttpRequest *request, HttpResponse *response) {
        fprintf(stderr, "Hit exact route for style.css\n");
        [exploreHandler handleRequest:request response:response];
    }];

    // MST Viewer (development/debugging tool)
    MSTViewerHandler *mstViewerHandler = [MSTViewerHandler sharedHandler];
    [mstViewerHandler setController:self];

    [_httpServer addHandlerForPath:@"/mst-viewer" handler:^(HttpRequest *request, HttpResponse *response) {
        [mstViewerHandler handleRequest:request response:response];
    }];

    [_httpServer addHandlerForPath:@"/api/mst" handler:^(HttpRequest *request, HttpResponse *response) {
        [mstViewerHandler handleRequest:request response:response];
    }];

    // NodeInfo endpoints
    NodeInfoHandler *nodeInfoHandler = [NodeInfoHandler sharedHandler];
    NSString *issuer = [NSString stringWithFormat:@"https://localhost:%lu", (unsigned long)self.httpPort];
    [nodeInfoHandler setIssuer:issuer];
    [nodeInfoHandler setController:self];
    [nodeInfoHandler registerRoutesWithServer:_httpServer];

    NSError *httpError = nil;
    if (![_httpServer startWithError:&httpError]) {
        os_log_error(_log, "Failed to start HTTP server: %@", httpError);
        if (error) *error = httpError;
        return NO;
    }
    _httpPort = _httpServer.port;
    os_log_info(_log, "HTTP server started on port %lu", (unsigned long)_httpPort);
    
    // Start WebSocket handler for subscribeRepos
    NSError *streamingError = nil;
    _subscribeReposHandler = [[SubscribeReposHandler alloc] initWithController:self];
    
    if (![_subscribeReposHandler startOnPort:self.wsPort error:&streamingError]) {
        os_log_error(_log, "Failed to start subscribeRepos WebSocket handler: %@", streamingError);
        if (error) *error = streamingError;
        return NO;
    }
    _wsPort = _subscribeReposHandler.webSocketServer.port;
    
    _running = YES;
    os_log_info(_log, "PDS server started successfully - XRPC at port %lu, WebSocket at port %lu", (unsigned long)_httpPort, (unsigned long)_wsPort);
    return YES;
}

- (void)stopServer {
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

- (nullable NSData *)getRepoContents:(NSString *)did since:(nullable NSData *)sinceCid error:(NSError **)error {
    return [_repositoryService getRepoContents:did since:sinceCid error:error];
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
    return [self base32Encode:root];
}

- (NSString *)base32Encode:(NSData *)data {
    static const char *alphabet = "abcdefghijklmnopqrstuvwxyz234567";
    NSMutableString *result = [NSMutableString string];
    NSUInteger length = data.length;
    NSUInteger i = 0;

    while (i < length) {
        uint8_t byte = ((uint8_t *)data.bytes)[i++];
        [result appendFormat:@"%c", alphabet[byte >> 3]];
        uint8_t nextByte = (i < length) ? ((uint8_t *)data.bytes)[i++] : 0;
        [result appendFormat:@"%c", alphabet[((byte & 0x07) << 2) | (nextByte >> 6)]];
        if (i >= length + 1) break;
        [result appendFormat:@"%c", alphabet[(nextByte >> 1) & 0x1F]];
        if (i >= length) break;
        nextByte = (i < length) ? ((uint8_t *)data.bytes)[i++] : 0;
        [result appendFormat:@"%c", alphabet[((nextByte & 0x0F) << 1) | (nextByte >> 7)]];
        if (i >= length) break;
        [result appendFormat:@"%c", alphabet[(nextByte >> 2) & 0x1F]];
        if (i >= length) break;
        nextByte = (i < length) ? ((uint8_t *)data.bytes)[i++] : 0;
        [result appendFormat:@"%c", alphabet[nextByte & 0x1F]];
    }

    return result;
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
    if (![_recordService putRecord:collection rkey:rkey value:value forDid:did validationMode:mode error:error]) {
        return NO;
    }
    
    // Update MST
    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
    NSDictionary *record = [_recordService getRecord:uri forDid:did error:nil];
    if (record && record[@"cid"]) {
        CID *cid = [CID cidFromString:record[@"cid"]];
        NSString *key = [NSString stringWithFormat:@"%@/%@", collection, rkey];
        return [_repositoryService updateMSTForDid:did key:key cid:cid error:error];
    }
    return YES;
}

- (BOOL)deleteRecord:(NSString *)collection
                  rkey:(NSString *)rkey
                forDid:(NSString *)did
                 error:(NSError **)error {
    if (![_recordService deleteRecord:collection rkey:rkey forDid:did error:error]) {
        return NO;
    }
    
    // Update MST (remove)
    NSString *key = [NSString stringWithFormat:@"%@/%@", collection, rkey];
    return [_repositoryService updateMSTForDid:did key:key cid:nil error:error];
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
    for (NSDictionary *write in writes) {
        NSString *action = write[@"action"];
        NSDictionary *record = write[@"record"];
        NSString *collection = write[@"collection"];
        NSString *rkey = write[@"rkey"];
        
        if ([action isEqualToString:@"create"] || [action isEqualToString:@"update"]) {
            PDSValidationMode mode = validate ? PDSValidationModeRequired : PDSValidationModeOff;
            if (![self putRecord:collection rkey:rkey value:record forDid:repo validationMode:mode error:error]) {
                return nil;
            }
        } else if ([action isEqualToString:@"delete"]) {
            if (![self deleteRecord:collection rkey:rkey forDid:repo error:error]) {
                return nil;
            }
        }
    }
    return @{@"commit": @{@"root": @"newroot"}};
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
    return NO;
}

- (BOOL)reinstateAccount:(NSString *)did error:(NSError **)error {
    return NO;
}

#pragma mark - Moderation Operations

- (NSDictionary *)moderateAccount:(NSDictionary *)params error:(NSError **)error {
    return @{@"status": @"not_implemented"};
}

- (NSDictionary *)moderateRecord:(NSDictionary *)params error:(NSError **)error {
    return @{@"status": @"not_implemented"};
}

#pragma mark - Labeling Operations

- (NSDictionary *)createLabel:(NSDictionary *)params error:(NSError **)error {
    return @{@"status": @"not_implemented"};
}

- (NSDictionary *)getLabels:(NSDictionary *)params error:(NSError **)error {
    return @{@"status": @"not_implemented"};
}

@end
