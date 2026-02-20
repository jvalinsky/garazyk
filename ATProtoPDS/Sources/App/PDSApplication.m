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
#import "Services/PDSRelayService.h"
#import "Auth/JWT.h"
#import "Auth/Secp256k1.h"
#import "Auth/PDSKeyManagerFactory.h"
#import "Blob/BlobStorage.h"
#import "Blob/PDSDiskBlobProvider.h"
#import "Network/HttpServer.h"
#import "Network/PDSHttpServerBuilder.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/RateLimiter.h"
#import "Sync/SubscribeReposHandler.h"
#import "Core/PDSServiceContainer.h"
#import "Lexicon/ATProtoLexiconRegistry.h"
#import "Debug/PDSLogger.h"
#import "Email/PDSEmailProvider.h"
#import "Email/PDSMockEmailProvider.h"
#import "Email/PDSSMTPEmailProvider.h"
#import "Email/PDSResendEmailProvider.h"
#import "Email/PDSKeychainSecretsProvider.h"
#import "Email/PDSEnvironmentSecretsProvider.h"
#import "Admin/PDSAdminAuth.h"

@interface PDSApplication ()

@property (nonatomic, strong, readwrite) PDSConfiguration *configuration;
@property (nonatomic, copy, readwrite) NSString *dataDirectory;
@property (nonatomic, strong, readwrite) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, strong, readwrite) PDSDatabasePool *userDatabasePool;
@property (nonatomic, strong, readwrite) JWTMinter *jwtMinter;
@property (nonatomic, strong, readwrite) HttpServer *httpServer;
@property (nonatomic, strong, readwrite) PDSRelayService *relayService;
@property (nonatomic, strong, readwrite) id<PDSAccountService> accountService;
@property (nonatomic, strong, readwrite) PDSRecordService *recordService;
@property (nonatomic, strong, readwrite) PDSBlobService *blobService;
@property (nonatomic, strong, readwrite) PDSRepositoryService *repositoryService;
@property (nonatomic, strong, readwrite, nullable) id<PDSEmailProvider> emailProvider;
@property (nonatomic, strong, readwrite) id<PDSAdminController> adminController;
@property (nonatomic, strong, readwrite) PDSController *legacyController;
@property (nonatomic, assign, readwrite, getter=isRunning) BOOL running;

@end

static void PDSApplicationUncaughtExceptionHandler(NSException *exception) {
    PDS_LOG_ERROR(@"Core", @"Uncaught exception: %@ — %@\n%@",
                  exception.name,
                  exception.reason,
                  exception.callStackSymbols);
    exit(1);
}

@implementation PDSApplication {
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

- (NSUInteger)wsPort {
    return self.httpPort;
}

#pragma mark - Initialization

- (instancetype)initWithConfiguration:(nullable PDSConfiguration *)configuration {
    self = [super init];
    if (self) {
        _configuration = configuration ?: [PDSConfiguration sharedConfiguration];
        _dataDirectory = _configuration.dataDirectory ?: [PDSConfiguration defaultDataDirectory];
        _httpPort = _configuration.serverPort > 0 ? _configuration.serverPort : 2583;
        _running = NO;

        // M2: Catch unhandled ObjC exceptions before they silently crash the process
        NSSetUncaughtExceptionHandler(&PDSApplicationUncaughtExceptionHandler);

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
        
        _legacyController = [[PDSController alloc] initWithApplication:self];
        [PDSAdminAuth sharedAuth].controller = _legacyController;
        
        PDS_LOG_CORE_INFO(@"PDSApplication initialized successfully");
    }
    return self;
}

- (instancetype)initWithDataDirectory:(NSString *)dataDirectory {
    // We need to set the data directory BEFORE calling initWithConfiguration
    // because it creates the legacy controller which needs the correct directory.
    // So we do manual initialization here instead of calling the designated initializer.
    self = [super init];
    if (self) {
        _configuration = [PDSConfiguration sharedConfiguration];
        _dataDirectory = [dataDirectory copy];
        _httpPort = _configuration.serverPort > 0 ? _configuration.serverPort : 2583;
        _running = NO;
        
        // Ensure default ports are set
        if (_httpPort == 0) _httpPort = 2583;
        
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
        
        _legacyController = [[PDSController alloc] initWithApplication:self];
        [PDSAdminAuth sharedAuth].controller = _legacyController;
        
        PDS_LOG_CORE_INFO(@"PDSApplication initialized successfully");
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
    NSDictionary *pdsEnv = [[NSProcessInfo processInfo] environment];
    NSString *configuredIssuer = _configuration.issuer;
    BOOL isProduction = [[pdsEnv[@"PDS_ENV"] lowercaseString] isEqualToString:@"production"] ||
                        [[pdsEnv[@"PDS_REQUIRE_ISSUER"] lowercaseString] isEqualToString:@"1"] ||
                        [[pdsEnv[@"PDS_REQUIRE_ISSUER"] lowercaseString] isEqualToString:@"true"];
    if (isProduction && configuredIssuer.length == 0) {
        PDS_LOG_ERROR(@"Core", @"PDS_ISSUER must be set to your public HTTPS domain in production (e.g. PDS_ISSUER=https://pds.example.com). Refusing to start.");
        exit(1);
    }
    if (isProduction && [configuredIssuer containsString:@"pds.local"]) {
        PDS_LOG_ERROR(@"Core", @"PDS_ISSUER cannot use a local placeholder domain in production. Refusing to start.");
        exit(1);
    }
    _jwtMinter.issuer = [_configuration canonicalIssuerWithPortHint:_httpPort];
    _jwtMinter.signingAlgorithm = @"ES256K";
    
    // Generate server signing key
    NSError *serverKeyError = nil;
    // Use factory to get appropriate key manager
    id<PDSKeyManager> keyManager = [PDSKeyManagerFactory createKeyManagerWithDatabase:[_serviceDatabases serviceDatabaseWithError:nil]];
    
    // Ensure active key exists
    id<PDSKeyPair> activeKey = [keyManager getActiveKeyPair:&serverKeyError];
    if (serverKeyError) {
        PDS_LOG_AUTH_WARN(@"JWT signing key load/create error: %@", serverKeyError.localizedDescription ?: @"unknown error");
    }
    
    _jwtMinter.keyManager = keyManager;
    // Private/Public key properties on Minter are now optional if keyManager is set, 
    // but for backwards compatibility or specific internal use we might still need them?
    // The Minter implementation now prefers keyManager. 
    // If Minter implementation fallback to privateKey/publicKey is removed or deprecated, 
    // we don't need to set them. 
    // Based on my review of JWT.m, it prefers keyManager.
    // However, for completeness if Minter exposes them: 
    // _jwtMinter.privateKey = ... (can't easily access raw ref from protocol without cast)
    // So we rely on keyManager assignment.

    // Initialize Relay Service
    _relayService = [[PDSRelayService alloc] initWithRelays:_configuration.crawlRelays
                                                   hostname:_jwtMinter.issuer];
}

- (void)initializeServices {
    // Setup Service Container
    PDSServiceContainer *container = [PDSServiceContainer sharedContainer];
    [container reset];
    
    // Initialize Account Service
    id<PDSEmailProvider> emailProvider = nil;
    if (_configuration) {
        if ([_configuration.emailProviderType isEqualToString:@"mock"]) {
            emailProvider = [[PDSMockEmailProvider alloc] init];
        } else if ([_configuration.emailProviderType isEqualToString:@"smtp"]) {
            emailProvider = [[PDSSMTPEmailProvider alloc] initWithHost:_configuration.emailSmtpHost ?: @"localhost"
                                                                  port:_configuration.emailSmtpPort
                                                              username:_configuration.emailSmtpUsername
                                                              password:_configuration.emailSmtpPassword
                                                                useTLS:_configuration.emailSmtpUseTLS];
        } else if ([_configuration.emailProviderType isEqualToString:@"resend"]) {
            if (_configuration.resendFromAddress.length > 0) {
                id<PDSSecretsProvider> secretsProvider = nil;
                NSString *source = _configuration.resendAPIKeySource ?: @"env";
                if ([source isEqualToString:@"keychain"]) {
                    secretsProvider = [[PDSKeychainSecretsProvider alloc]
                        initWithService:_configuration.resendKeychainService ?: @"com.atproto.pds.resend"];
                } else {
                    secretsProvider = [[PDSEnvironmentSecretsProvider alloc] init];
                }
                emailProvider = [[PDSResendEmailProvider alloc]
                    initWithSecretsProvider:secretsProvider
                                fromAddress:_configuration.resendFromAddress
                                apiEndpoint:_configuration.resendAPIEndpoint];
                PDS_LOG_INFO(@"Initialized Resend email provider (source: %@, from: %@)", source, _configuration.resendFromAddress);
            } else {
                PDS_LOG_WARN(@"Resend email provider requested but no from address configured (set PDS_EMAIL_RESEND_FROM).");
            }
        }
    }
    _emailProvider = emailProvider;
    if (emailProvider) {
        [container registerInstance:emailProvider forProtocol:@protocol(PDSEmailProvider)];
    }

    PDSAccountService *accountService = [[PDSAccountService alloc] initWithAccountRepository:nil
                                                                            sessionRepository:nil
                                                                                       minter:nil
                                                                                emailProvider:emailProvider];
    accountService.databasePool = _userDatabasePool;
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

    // H3: Give PDSAdminAuth access to data directory so logout survives restarts
    [PDSAdminAuth sharedAuth].dataDirectory = _dataDirectory;

    // H4: Warn if admin password is stored as plain text
    NSDictionary *startupEnv = [[NSProcessInfo processInfo] environment];
    NSString *adminPassword = startupEnv[@"PDS_ADMIN_PASSWORD"];
    if (adminPassword.length > 0 && ![adminPassword hasPrefix:@"pbkdf2:"]) {
        PDS_LOG_WARN(@"Auth", @"PDS_ADMIN_PASSWORD is stored as plain text. Hash it with PBKDF2 (pbkdf2:<iterations>:<salt>:<hash>) for production use.");
    }

    // H5: Warn if X-Admin-Token legacy header is active in production
    BOOL isProductionEnv = [[startupEnv[@"PDS_ENV"] lowercaseString] isEqualToString:@"production"];
    BOOL xAdminTokenDisabled = [[startupEnv[@"PDS_DISABLE_X_ADMIN_TOKEN_HEADER"] lowercaseString] isEqualToString:@"1"] ||
                                [[startupEnv[@"PDS_DISABLE_X_ADMIN_TOKEN_HEADER"] lowercaseString] isEqualToString:@"true"];
    if (isProductionEnv && !xAdminTokenDisabled) {
        PDS_LOG_WARN(@"Auth", @"X-Admin-Token legacy header is active in production. Set PDS_DISABLE_X_ADMIN_TOKEN_HEADER=1 to disable it.");
    }
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
    PDS_LOG_CORE_INFO(@"Starting PDSApplication...");
    
    // Initialize XRPC dispatcher
    _xrpcDispatcher = [XrpcDispatcher sharedDispatcher];
    if (!_subscribeReposHandler) {
        _subscribeReposHandler = [[SubscribeReposHandler alloc] initWithServiceDatabases:_serviceDatabases userDatabasePool:_userDatabasePool];
    }
    
    // Build and configure HTTP server
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] initWithConfiguration:_configuration];
    builder.port = self.httpPort;
    builder.dataDirectory = _dataDirectory;
    builder.application = self;  // Prefer application for service-based registration
    builder.controller = _legacyController;  // Still needed for handlers that use controller
    builder.jwtMinter = _jwtMinter;
    builder.serviceDatabases = _serviceDatabases;
    builder.xrpcDispatcher = _xrpcDispatcher;
    builder.subscribeReposHandler = _subscribeReposHandler;
    builder.issuer = [_configuration canonicalIssuerWithPortHint:self.httpPort];
    
    NSError *buildError = nil;
    _httpServer = [builder buildWithError:&buildError];
    if (!_httpServer) {
        PDS_LOG_CORE_ERROR(@"Failed to build HTTP server: %@", buildError);
        if (error) *error = buildError;
        return NO;
    }
    
    // Start HTTP server
    NSError *httpError = nil;
    if (![_httpServer startWithError:&httpError]) {
        PDS_LOG_CORE_ERROR(@"Failed to start HTTP server: %@", httpError);
        if (error) *error = httpError;
        return NO;
    }
    _httpPort = _httpServer.port;
    _configuration.serverPort = _httpPort;
    PDS_LOG_CORE_INFO(@"HTTP server started on port %lu", (unsigned long)_httpPort);
    PDS_LOG_CORE_INFO(@"subscribeRepos WebSocket upgrades available on HTTP port %lu", (unsigned long)_httpPort);
    
    _running = YES;
    [_relayService start];
    PDS_LOG_CORE_INFO(@"PDSApplication started successfully");
    return YES;
}

- (void)stop {
    PDS_LOG_CORE_INFO(@"Stopping PDSApplication...");
    
    // Stop servers
    [_httpServer stop];
    _httpServer = nil;
    
    [_subscribeReposHandler stop];
    _subscribeReposHandler = nil;
    
    [_relayService stop];
    
    // Close databases
    [_userDatabasePool closeAll];
    [_serviceDatabases closeAll];
    
    // Flush and close logger
    [[PDSLogger sharedLogger] flush];
    [[PDSLogger sharedLogger] closeLogFile];
    
    _running = NO;
    PDS_LOG_CORE_INFO(@"PDSApplication stopped");
}

@end
