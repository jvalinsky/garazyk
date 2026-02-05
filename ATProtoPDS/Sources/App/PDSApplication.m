/*!
 @file PDSApplication.m

 @abstract Implementation of the main application facade.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "PDSApplication.h"
#import "PDSConfiguration.h"
#import "PDSController.h"
#import "Admin/PDSAdminController.h"
#import "Services/PDSAccountService.h"
#import "Services/PDSRecordService.h"
#import "Services/PDSBlobService.h"
#import "Services/PDSRepositoryService.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/Pool/DatabasePool.h"
#import "Auth/JWT.h"
#import "Auth/Secp256k1.h"
#import "Auth/JWTSigningKeyStore.h"
#import "Blob/BlobStorage.h"
#import "Blob/PDSDiskBlobProvider.h"
#import "Network/HttpServer.h"
#import "Network/PDSHttpServerBuilder.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/RateLimiter.h"
#import "Sync/SubscribeReposHandler.h"
#import "Sync/WebSocketServer.h"
#import "Core/PDSServiceContainer.h"
#import "Lexicon/ATProtoLexiconRegistry.h"
#import "Debug/PDSLogger.h"
#import <os/log.h>

@interface PDSApplication ()

@property (nonatomic, strong, readwrite) PDSConfiguration *configuration;
@property (nonatomic, copy, readwrite) NSString *dataDirectory;
@property (nonatomic, strong, readwrite) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, strong, readwrite) PDSDatabasePool *userDatabasePool;
@property (nonatomic, strong, readwrite) JWTMinter *jwtMinter;
@property (nonatomic, strong, readwrite) HttpServer *httpServer;
@property (nonatomic, strong, readwrite) id<PDSAccountService> accountService;
@property (nonatomic, strong, readwrite) PDSRecordService *recordService;
@property (nonatomic, strong, readwrite) PDSBlobService *blobService;
@property (nonatomic, strong, readwrite) PDSRepositoryService *repositoryService;
@property (nonatomic, strong, readwrite) id<PDSAdminController> adminController;
@property (nonatomic, strong, readwrite) PDSController *legacyController;
@property (nonatomic, assign, readwrite, getter=isRunning) BOOL running;

@end

@implementation PDSApplication {
    os_log_t _log;
    SubscribeReposHandler *_subscribeReposHandler;
    XrpcDispatcher *_xrpcDispatcher;
}

#pragma mark - Singleton

+ (instancetype)sharedApplication {
    static PDSApplication *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PDSApplication alloc] initWithConfiguration:[PDSConfiguration sharedConfiguration]];
    });
    return shared;
}

#pragma mark - Initialization

- (instancetype)initWithConfiguration:(nullable PDSConfiguration *)configuration {
    self = [super init];
    if (self) {
        _log = os_log_create("com.atproto.pds", "PDSApplication");
        
        _configuration = configuration ?: [PDSConfiguration sharedConfiguration];
        _dataDirectory = _configuration.dataDirectory ?: [PDSConfiguration defaultDataDirectory];
        _httpPort = _configuration.serverPort > 0 ? _configuration.serverPort : 2583;
        _wsPort = 8081;
        _running = NO;
        
        // Configure logging from configuration
        [self configureLogging];
        
        // Configure rate limiter
        [self configureRateLimiter];
        
        PDS_LOG_INFO_C(PDSLogComponentCore, @"PDSApplication initializing with data directory: %@", _dataDirectory);
        
        // Initialize infrastructure
        [self initializeInfrastructure];
        
        // Initialize services
        [self initializeServices];
        
        // Load lexicons
        [self loadLexicons];
        
        // Create legacy controller for backward compatibility
        // This allows PDSController.sharedController to work
        _legacyController = [[PDSController alloc] initWithApplication:self];
        
        os_log_info(_log, "PDSApplication initialized successfully");
    }
    return self;
}

- (instancetype)initWithDataDirectory:(NSString *)dataDirectory {
    // We need to set the data directory BEFORE calling initWithConfiguration
    // because it creates the legacy controller which needs the correct directory.
    // So we do manual initialization here instead of calling the designated initializer.
    self = [super init];
    if (self) {
        _log = os_log_create("com.atproto.pds", "PDSApplication");
        
        _configuration = [PDSConfiguration sharedConfiguration];
        _dataDirectory = [dataDirectory copy];
        _httpPort = _configuration.serverPort > 0 ? _configuration.serverPort : 2583;
        _wsPort = 8081;
        _running = NO;
        
        // Ensure default ports are set
        if (_httpPort == 0) _httpPort = 2583;
        if (_wsPort == 0) _wsPort = 8081;
        
        // Configure logging from configuration
        [self configureLogging];
        
        // Configure rate limiter
        [self configureRateLimiter];
        
        PDS_LOG_INFO_C(PDSLogComponentCore, @"PDSApplication initializing with data directory: %@", _dataDirectory);
        
        // Initialize infrastructure
        [self initializeInfrastructure];
        
        // Initialize services
        [self initializeServices];
        
        // Load lexicons
        [self loadLexicons];
        
        // Create legacy controller for backward compatibility
        _legacyController = [[PDSController alloc] initWithApplication:self];
        
        os_log_info(_log, "PDSApplication initialized successfully");
    }
    return self;
}

#pragma mark - Configuration Helpers

- (void)configureLogging {
    if (!_configuration) return;
    
    PDSLogger *logger = [PDSLogger sharedLogger];
    if (_configuration.logFilePath) {
        logger.logFilePath = _configuration.logFilePath;
    }
    logger.logLevel = _configuration.logLevel;
    logger.logFormat = _configuration.logFormat;
    logger.maxLogFileSize = _configuration.maxLogFileSize;
    logger.maxLogFiles = _configuration.maxLogFiles;
    logger.asyncLogging = _configuration.asyncLogging;
    if (_configuration.enabledComponents.count > 0) {
        logger.enabledComponents = [NSSet setWithArray:_configuration.enabledComponents];
    }
}

- (void)configureRateLimiter {
    if (!_configuration) return;
    
    RateLimiter *limiter = [RateLimiter sharedLimiter];
    limiter.enabled = _configuration.rateLimitEnabled;
    limiter.didLimit = _configuration.rateLimitDidLimit;
    limiter.didWindowSeconds = _configuration.rateLimitDidWindowSeconds;
    limiter.ipLimit = _configuration.rateLimitIpLimit;
    limiter.ipWindowSeconds = _configuration.rateLimitIpWindowSeconds;
    limiter.blobLimit = _configuration.rateLimitBlobLimit;
    limiter.blobWindowSeconds = _configuration.rateLimitBlobWindowSeconds;
}

#pragma mark - Initialization Helpers

- (void)initializeInfrastructure {
    // Create data directory if needed
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:_dataDirectory]) {
        [fm createDirectoryAtPath:_dataDirectory 
      withIntermediateDirectories:YES 
                       attributes:nil 
                            error:nil];
    }
    
    // Initialize database pools
    NSUInteger serviceMaxSize = _configuration.serviceDatabasePoolMaxSize > 0 ? _configuration.serviceDatabasePoolMaxSize : 100;
    NSUInteger userMaxSize = _configuration.userDatabasePoolMaxSize > 0 ? _configuration.userDatabasePoolMaxSize : 30000;
    NSUInteger didCacheSize = _configuration.didCachePoolMaxSize > 0 ? _configuration.didCachePoolMaxSize : 1000;
    NSUInteger sequencerSize = _configuration.sequencerPoolMaxSize > 0 ? _configuration.sequencerPoolMaxSize : 100;
    
    _serviceDatabases = [[PDSServiceDatabases alloc] initWithDirectory:_dataDirectory
                                                         serviceMaxSize:serviceMaxSize
                                                       didCacheMaxSize:didCacheSize
                                                     sequencerMaxSize:sequencerSize];
    
    _userDatabasePool = [[PDSDatabasePool alloc] initWithDbDirectory:_dataDirectory maxSize:userMaxSize];
    
    // Initialize JWT Minter
    _jwtMinter = [[JWTMinter alloc] init];
    _jwtMinter.issuer = [[NSProcessInfo processInfo] environment][@"PDS_ISSUER"] ?: @"https://pds.local:8443";
    _jwtMinter.signingAlgorithm = @"ES256K";
    
    // Generate server signing key
    NSError *serverKeyError = nil;
    Secp256k1KeyPair *serverKey = [JWTSigningKeyStore loadOrCreateKeyPairForDataDirectory:_dataDirectory error:&serverKeyError];
    if (serverKeyError) {
        PDS_LOG_AUTH_WARN(@"JWT signing key load/create error: %@", serverKeyError.localizedDescription ?: @"unknown error");
    }
    _jwtMinter.privateKey = serverKey.privateKey;
    _jwtMinter.publicKey = serverKey.publicKey;
}

- (void)initializeServices {
    // Setup Service Container
    PDSServiceContainer *container = [PDSServiceContainer sharedContainer];
    [container reset];
    
    // Initialize Account Service
    PDSAccountService *accountService = [[PDSAccountService alloc] initWithDatabasePool:_userDatabasePool];
    accountService.serviceDatabases = _serviceDatabases;
    accountService.minter = _jwtMinter;
    [container registerInstance:accountService forProtocol:@protocol(PDSAccountService)];
    _accountService = accountService;
    
    // Initialize Record Service
    _recordService = [[PDSRecordService alloc] initWithDatabasePool:_userDatabasePool];
    
    // Initialize Blob Storage and Service
    NSString *blobDir = [_dataDirectory stringByAppendingPathComponent:@"blobs"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:blobDir]) {
        [fm createDirectoryAtPath:blobDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    NSURL *blobURL = [NSURL fileURLWithPath:blobDir];
    PDSDiskBlobProvider *blobProvider = [[PDSDiskBlobProvider alloc] initWithStorageDirectory:blobURL];
    BlobStorage *blobStorage = [[BlobStorage alloc] initWithDatabasePool:_userDatabasePool provider:blobProvider];
    _blobService = [[PDSBlobService alloc] initWithDatabasePool:_userDatabasePool storage:blobStorage];
    
    // Initialize Repository Service
    _repositoryService = [[PDSRepositoryService alloc] initWithDatabasePool:_userDatabasePool];
    
    // Initialize Admin Controller
    _adminController = [[PDSAdminController alloc] initWithServiceDatabases:_serviceDatabases
                                                             accountService:_accountService];
    [container registerInstance:_adminController forProtocol:@protocol(PDSAdminController)];
}

- (void)loadLexicons {
    ATProtoLexiconRegistry *registry = [ATProtoLexiconRegistry sharedRegistry];
    NSArray<NSString *> *lexiconPaths = [self lexiconSearchPaths];
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
}

- (NSArray<NSString *> *)lexiconSearchPaths {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableOrderedSet<NSString *> *paths = [NSMutableOrderedSet orderedSet];
    
    // Environment override
    NSString *overridePath = [NSProcessInfo processInfo].environment[@"PDS_LEXICON_PATH"];
    if (overridePath.length > 0) {
        [paths addObject:overridePath];
    }
    
    // Bundle path
    NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"lexicons" ofType:nil];
    if (bundlePath.length > 0) {
        [paths addObject:bundlePath];
    }
    
    // Working directory candidates
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
    
    // Data directory custom lexicons
    if (_dataDirectory.length > 0) {
        NSString *customPath = [_dataDirectory stringByAppendingPathComponent:@"lexicons"];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:customPath isDirectory:&isDir] && isDir) {
            [paths addObject:customPath];
        }
    }
    
    return paths.array;
}

#pragma mark - Lifecycle

- (BOOL)startWithError:(NSError **)error {
    os_log_info(_log, "Starting PDSApplication...");
    
    // Initialize XRPC dispatcher
    _xrpcDispatcher = [XrpcDispatcher sharedDispatcher];
    
    // Build and configure HTTP server
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] initWithConfiguration:_configuration];
    builder.port = self.httpPort;
    builder.application = self;  // Prefer application for service-based registration
    builder.controller = _legacyController;  // Still needed for handlers that use controller
    builder.jwtMinter = _jwtMinter;
    builder.serviceDatabases = _serviceDatabases;
    builder.xrpcDispatcher = _xrpcDispatcher;
    builder.issuer = [NSString stringWithFormat:@"https://localhost:%lu", (unsigned long)self.httpPort];
    
    NSError *buildError = nil;
    _httpServer = [builder buildWithError:&buildError];
    if (!_httpServer) {
        os_log_error(_log, "Failed to build HTTP server: %@", buildError);
        if (error) *error = buildError;
        return NO;
    }
    
    // Start HTTP server
    NSError *httpError = nil;
    if (![_httpServer startWithError:&httpError]) {
        os_log_error(_log, "Failed to start HTTP server: %@", httpError);
        if (error) *error = httpError;
        return NO;
    }
    _httpPort = _httpServer.port;
    os_log_info(_log, "HTTP server started on port %lu", (unsigned long)_httpPort);
    
    // Start WebSocket handler for subscribeRepos
    _subscribeReposHandler = [[SubscribeReposHandler alloc] initWithController:_legacyController];
    NSError *wsError = nil;
    if (![_subscribeReposHandler startOnPort:self.wsPort error:&wsError]) {
        os_log_error(_log, "Failed to start WebSocket handler: %@", wsError);
        if (error) *error = wsError;
        [_httpServer stop];
        return NO;
    }
    _wsPort = _subscribeReposHandler.webSocketServer.port;
    os_log_info(_log, "WebSocket server started on port %lu", (unsigned long)_wsPort);
    
    _running = YES;
    os_log_info(_log, "PDSApplication started successfully");
    return YES;
}

- (void)stop {
    os_log_info(_log, "Stopping PDSApplication...");
    
    // Stop servers
    [_httpServer stop];
    _httpServer = nil;
    
    [_subscribeReposHandler stop];
    _subscribeReposHandler = nil;
    
    // Close databases
    [_userDatabasePool closeAll];
    [_serviceDatabases closeAll];
    
    // Flush and close logger
    [[PDSLogger sharedLogger] flush];
    [[PDSLogger sharedLogger] closeLogFile];
    
    _running = NO;
    os_log_info(_log, "PDSApplication stopped");
}

@end
