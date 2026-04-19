/*!
 @file PDSApplication.m

 @abstract Implementation of the main application facade.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "PDSApplication.h"
#import "PDSConfiguration.h"
#import "PDSController.h"
#import "Admin/PDSAdminController.h"
#import "Services/PDS/PDSAccountService.h"
#import "Services/PDS/PDSRecordService.h"
#import "Services/PDS/PDSBlobService.h"
#import "Services/PDS/PDSRepositoryService.h"
#import "Admin/Diagnostics/BlobAudit/PDSBlobAuditManager.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/PDSRepositoryFactory.h"
#import "Services/PDS/PDSRelayService.h"
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
#import "Sync/Firehose/SubscribeReposHandler.h"
#import "Admin/Diagnostics/Analytics/PDSSequencerAnalyticsCollector.h"
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
@property (nonatomic, strong, readwrite) PDSBlobAuditManager *blobAuditManager;
@property (nonatomic, strong, readwrite) PDSController *legacyController;
@property (nonatomic, assign, readwrite, getter=isRunning) BOOL running;
@property (nonatomic, assign) NSUInteger servicePoolSizeOverride;
@property (nonatomic, assign) NSUInteger userPoolSizeOverride;
@property (nonatomic, assign) NSUInteger didCachePoolSizeOverride;
@property (nonatomic, assign) NSUInteger sequencerPoolSizeOverride;

@end

static void PDSApplicationUncaughtExceptionHandler(NSException *exception) {
    PDS_LOG_ERROR(@"Core", @"Uncaught exception: %@ — %@\n%@",
                  exception.name,
                  exception.reason,
                  exception.callStackSymbols);
    exit(1);
}

static BOOL PDSApplicationShouldUseEphemeralJWTKeyForTests(void) {
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    NSString *processName = [[NSProcessInfo processInfo] processName] ?: @"";
    BOOL runningTests = [env[@"PDS_RUNNING_TESTS"] length] > 0 ||
                        [processName containsString:@"AllTests"];
    if (!runningTests) {
        return NO;
    }

    NSString *useKeychainEnv = [env[@"PDS_USE_KEYCHAIN"] lowercaseString];
    if ([useKeychainEnv isEqualToString:@"0"] ||
        [useKeychainEnv isEqualToString:@"false"] ||
        [useKeychainEnv isEqualToString:@"no"]) {
        return YES;
    }

    return ![PDSConfiguration sharedConfiguration].useKeychain;
}

static void PDSApplicationLogEphemeralJWTKeyModeOnce(void) {
    static BOOL didLog = NO;
    if (didLog) {
        return;
    }
    didLog = YES;
    PDS_LOG_AUTH_INFO(@"Using in-memory secp256k1 JWT signing key in test mode (keychain disabled).");
}

@implementation PDSApplication {
    SubscribeReposHandler *_subscribeReposHandler;
    PDSSequencerAnalyticsCollector *_analyticsCollector;
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

- (SubscribeReposHandler *)subscribeReposHandler {
    return _subscribeReposHandler;
}

- (PDSSequencerAnalyticsCollector *)analyticsCollector {
    return _analyticsCollector;
}

#pragma mark - Initialization

- (instancetype)initWithConfiguration:(nullable PDSConfiguration *)configuration {
    return [self initWithConfiguration:configuration
                         dataDirectory:nil
                        serviceMaxSize:0
                   userDatabaseMaxSize:0
                       didCacheMaxSize:0
                     sequencerMaxSize:0];
}

- (instancetype)initWithDataDirectory:(NSString *)dataDirectory {
    return [self initWithConfiguration:nil
                         dataDirectory:dataDirectory
                        serviceMaxSize:0
                   userDatabaseMaxSize:0
                       didCacheMaxSize:0
                     sequencerMaxSize:0];
}

- (instancetype)initWithConfiguration:(nullable PDSConfiguration *)configuration dataDirectory:(nullable NSString *)dataDirectory {
    return [self initWithConfiguration:configuration
                         dataDirectory:dataDirectory
                        serviceMaxSize:0
                   userDatabaseMaxSize:0
                       didCacheMaxSize:0
                     sequencerMaxSize:0];
}

- (instancetype)initWithConfiguration:(nullable PDSConfiguration *)configuration
                        dataDirectory:(nullable NSString *)dataDirectory
                       serviceMaxSize:(NSUInteger)serviceMaxSize
                  userDatabaseMaxSize:(NSUInteger)userDatabaseMaxSize
                      didCacheMaxSize:(NSUInteger)didCacheMaxSize
                    sequencerMaxSize:(NSUInteger)sequencerMaxSize {
    self = [super init];
    if (self) {
        _configuration = configuration ?: [PDSConfiguration sharedConfiguration];
        _dataDirectory = dataDirectory ?: (_configuration.dataDirectory ?: [PDSConfiguration defaultDataDirectory]);
        _httpPort = _configuration.serverPort > 0 ? _configuration.serverPort : 2583;
        _running = NO;
        _servicePoolSizeOverride = serviceMaxSize;
        _userPoolSizeOverride = userDatabaseMaxSize;
        _didCachePoolSizeOverride = didCacheMaxSize;
        _sequencerPoolSizeOverride = sequencerMaxSize;

        // M2: Catch unhandled ObjC exceptions
        NSSetUncaughtExceptionHandler(&PDSApplicationUncaughtExceptionHandler);

        [self configureLogging];
        [self configureRateLimiter];
        
        PDS_LOG_INFO_C(PDSLogComponentCore, @"PDSApplication initializing with data directory: %@", _dataDirectory);
        
        [self initializeInfrastructure];
        [self initializeServices];
        [self loadLexicons];
        
        _legacyController = [[PDSController alloc] initWithApplication:self];
        [PDSAdminAuth sharedAuth].controller = _legacyController;
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
    NSString *rateLimitPath = [[_dataDirectory stringByAppendingPathComponent:@"service"]
                               stringByAppendingPathComponent:@"ratelimits.db"];
    [limiter reconfigureDatabasePath:rateLimitPath];
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
        NSError *dirError = nil;
        if (![fm createDirectoryAtPath:_dataDirectory
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:&dirError]) {
            PDS_LOG_ERROR(@"Core", @"Failed to create data directory %@: %@", _dataDirectory, dirError);
        }
    }
    
    // Initialize database pools
    NSUInteger serviceMaxSize = self.servicePoolSizeOverride > 0
                                    ? self.servicePoolSizeOverride
                                    : (_configuration.serviceDatabasePoolMaxSize > 0
                                           ? _configuration.serviceDatabasePoolMaxSize
                                           : 100);
    NSUInteger userMaxSize = self.userPoolSizeOverride > 0
                                 ? self.userPoolSizeOverride
                                 : (_configuration.userDatabasePoolMaxSize > 0
                                        ? _configuration.userDatabasePoolMaxSize
                                        : 30000);
    NSUInteger didCacheSize = self.didCachePoolSizeOverride > 0
                                  ? self.didCachePoolSizeOverride
                                  : (_configuration.didCachePoolMaxSize > 0
                                         ? _configuration.didCachePoolMaxSize
                                         : 1000);
    NSUInteger sequencerSize = self.sequencerPoolSizeOverride > 0
                                   ? self.sequencerPoolSizeOverride
                                   : (_configuration.sequencerPoolMaxSize > 0
                                          ? _configuration.sequencerPoolMaxSize
                                          : 100);
    
    _serviceDatabases = [[PDSServiceDatabases alloc] initWithDirectory:_dataDirectory
                                                         serviceMaxSize:serviceMaxSize
                                                       didCacheMaxSize:didCacheSize
                                                     sequencerMaxSize:sequencerSize];
    _serviceDatabases.refreshTokenTTLSeconds = _configuration.refreshTokenTtlSeconds;
    
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

    BOOL hasProvisionedSigningKey = NO;
    if (PDSApplicationShouldUseEphemeralJWTKeyForTests()) {
        NSError *fallbackError = nil;
        Secp256k1KeyPair *fallbackKeyPair = [[Secp256k1 shared] generateKeyPairWithError:&fallbackError];
        if (fallbackKeyPair) {
            _jwtMinter.keyManager = nil;
            _jwtMinter.signingAlgorithm = @"ES256K";
            _jwtMinter.privateKey = fallbackKeyPair.privateKey;
            _jwtMinter.publicKey = fallbackKeyPair.publicKey;
            hasProvisionedSigningKey = YES;
            PDSApplicationLogEphemeralJWTKeyModeOnce();
        } else {
            PDS_LOG_AUTH_WARN(@"Test-mode ephemeral JWT key generation failed; falling back to key manager path: %@",
                              fallbackError.localizedDescription ?: @"unknown error");
        }
    }

    if (!hasProvisionedSigningKey) {
        NSError *serverKeyError = nil;
        id<PDSKeyManager> keyManager = [PDSKeyManagerFactory createKeyManagerWithDatabase:[_serviceDatabases serviceDatabaseWithError:nil]];
        id<PDSKeyPair> activeKey = [keyManager getActiveKeyPair:&serverKeyError];
        if (serverKeyError) {
            PDS_LOG_AUTH_WARN(@"JWT signing key load/create error: %@", serverKeyError.localizedDescription ?: @"unknown error");
        }

        if (activeKey) {
            _jwtMinter.keyManager = keyManager;
        } else if (!isProduction) {
            NSError *fallbackError = nil;
            Secp256k1KeyPair *fallbackKeyPair = [[Secp256k1 shared] generateKeyPairWithError:&fallbackError];
            if (fallbackKeyPair) {
                _jwtMinter.keyManager = nil;
                _jwtMinter.signingAlgorithm = @"ES256K";
                _jwtMinter.privateKey = fallbackKeyPair.privateKey;
                _jwtMinter.publicKey = fallbackKeyPair.publicKey;
                PDS_LOG_AUTH_WARN(@"Using in-memory secp256k1 JWT signing key fallback because key manager provisioning failed.");
            } else {
                _jwtMinter.keyManager = keyManager;
                PDS_LOG_AUTH_WARN(@"JWT fallback key generation failed: %@", fallbackError.localizedDescription ?: @"unknown error");
            }
        } else {
            _jwtMinter.keyManager = keyManager;
        }
    }
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

    id<PDSAccountRepository> accountRepo = [PDSRepositoryFactory accountRepositoryWithServiceDatabases:_serviceDatabases];
    id<PDSSessionRepository> sessionRepo = [PDSRepositoryFactory sessionRepositoryWithServiceDatabases:_serviceDatabases];

    PDSAccountService *accountService = [[PDSAccountService alloc] initWithAccountRepository:accountRepo
                                                                            sessionRepository:sessionRepo
                                                                                        minter:_jwtMinter
                                                                                 emailProvider:emailProvider];
    accountService.databasePool = _userDatabasePool;
    accountService.serviceDatabases = _serviceDatabases;
    [container registerInstance:accountService forProtocol:@protocol(PDSAccountService)];
    _accountService = accountService;
    
    // Initialize Record Service
    id<PDSRecordRepository> recordRepo = [PDSRepositoryFactory recordRepositoryWithDatabasePool:_userDatabasePool];
    _recordService = [[PDSRecordService alloc] initWithDatabasePool:_userDatabasePool];
    _recordService.recordRepository = recordRepo;
    
    // Initialize Blob Storage and Service
    NSString *blobDir = [_dataDirectory stringByAppendingPathComponent:@"blobs"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:blobDir]) {
        [fm createDirectoryAtPath:blobDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    NSURL *blobURL = [NSURL fileURLWithPath:blobDir];
    PDSDiskBlobProvider *blobProvider = [[PDSDiskBlobProvider alloc] initWithStorageDirectory:blobURL];
    BlobStorage *blobStorage = [[BlobStorage alloc] initWithDatabasePool:_userDatabasePool provider:blobProvider];
    
    id<PDSBlobRepository> blobRepo = [PDSRepositoryFactory blobRepositoryWithDatabasePool:_userDatabasePool];
    _blobService = [[PDSBlobService alloc] initWithDatabasePool:_userDatabasePool storage:blobStorage];
    _blobService.blobRepository = blobRepo;
    
    // Initialize Repository Service
    id<PDSBlockRepository> blockRepo = [PDSRepositoryFactory blockRepositoryWithDatabasePool:_userDatabasePool];
    id<PDSRepoRepository> repoRepo = [PDSRepositoryFactory repoRepositoryWithServiceDatabases:_serviceDatabases];
    _repositoryService = [[PDSRepositoryService alloc] initWithDatabasePool:_userDatabasePool];
    _repositoryService.blockRepository = blockRepo;
    _repositoryService.repoRepository = repoRepo;
    
    // Initialize Admin Controller
    _adminController = [[PDSAdminController alloc] initWithServiceDatabases:_serviceDatabases
                                                             accountService:_accountService];
    [container registerInstance:_adminController forProtocol:@protocol(PDSAdminController)];

    // Initialize Blob Audit Manager
    _blobAuditManager = [[PDSBlobAuditManager alloc] initWithBlobStorage:_blobService.blobStorage
                                                        serviceDatabases:_serviceDatabases];

    // H3: Give PDSAdminAuth access to data directory so logout survives restarts
    [PDSAdminAuth sharedAuth].dataDirectory = _dataDirectory;

    // H4: Validate admin password format (enforce in production mode)
    [self validateAdminPasswordWithConfiguration:_configuration];

    // H5: Warn if X-Admin-Token legacy header is active in production
    NSDictionary *startupEnv = [[NSProcessInfo processInfo] environment];
    BOOL isProductionEnv = [[startupEnv[@"PDS_ENV"] lowercaseString] isEqualToString:@"production"];
    BOOL xAdminTokenDisabled = [[startupEnv[@"PDS_DISABLE_X_ADMIN_TOKEN_HEADER"] lowercaseString] isEqualToString:@"1"] ||
                                [[startupEnv[@"PDS_DISABLE_X_ADMIN_TOKEN_HEADER"] lowercaseString] isEqualToString:@"true"];
    if (isProductionEnv && !xAdminTokenDisabled) {
        PDS_LOG_WARN(@"Auth", @"X-Admin-Token legacy header is active in production. Set PDS_DISABLE_X_ADMIN_TOKEN_HEADER=1 to disable it.");
    }
    
    // Initialize Firehose (subscribeRepos) handler early so it's available for persistence in tests
    if (!_subscribeReposHandler) {
        _subscribeReposHandler = [[SubscribeReposHandler alloc] initWithServiceDatabases:_serviceDatabases userDatabasePool:_userDatabasePool];
    }

    // Initialize Sequencer Analytics Collector for system diagnostics
    if (!_analyticsCollector) {
        _analyticsCollector = [[PDSSequencerAnalyticsCollector alloc] initWithServiceDatabases:_serviceDatabases
                                                                              subscribeHandler:_subscribeReposHandler];
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
        PDS_LOG_WARN(@"No lexicons loaded. Set PDS_LEXICON_PATH or install lexicons under Garazyk/Resources/lexicons.");
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
        @"Garazyk/Resources/lexicons",
        @"Resources/lexicons",
        @"lexicons",
        @"../Garazyk/Resources/lexicons",
        @"../../Garazyk/Resources/lexicons",
        @"../../../Garazyk/Resources/lexicons"
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

#pragma mark - Configuration Validation

- (void)validateAdminPasswordWithConfiguration:(PDSConfiguration *)configuration {
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    NSString *adminPassword = env[@"PDS_ADMIN_PASSWORD"];

    if (!adminPassword || adminPassword.length == 0) {
        // No admin password set is OK (admin auth may be disabled)
        return;
    }

    // Check if password is hashed with pbkdf2 format
    if (![adminPassword hasPrefix:@"pbkdf2:"]) {
        // Check if in production mode
        NSString *envMode = [env[@"PDS_ENV"] lowercaseString];
        if ([envMode isEqualToString:@"production"]) {
            // FAIL in production mode - plaintext passwords not allowed
            PDS_LOG_AUTH_ERROR(@"CRITICAL: Admin password must use pbkdf2 format in production mode. "
                              @"Plaintext passwords are not permitted for security reasons. "
                              @"To generate a hashed password, use: scripts/ops/hash_admin_password.sh");
            // Exit with error rather than silently continuing
            NSString *errorMsg = @"Admin password must be hashed with pbkdf2 in production mode";
            fprintf(stderr, "FATAL: %s\n", errorMsg.UTF8String);
            exit(1);
        } else {
            // WARN in development mode - allow but strongly encourage hashing
            PDS_LOG_AUTH_WARN(@"Admin password is stored as plain text. "
                             @"For production use, hash it with PBKDF2: pbkdf2:600000:<salt>:<hash>");
        }
    }
}

#pragma mark - Lifecycle

- (BOOL)startWithError:(NSError **)error {
    PDS_LOG_CORE_INFO(@"Starting PDSApplication...");

    // TODO (Sprint 4 Phase 2): Integrate PDSReadinessCheck before accepting traffic
    // Uncomment when PDSReadinessCheck is fully integrated:
    //
    // NSError *readinessError = nil;
    // if (![PDSReadinessCheck performReadinessChecksWithConfig:_configuration error:&readinessError]) {
    //     PDS_LOG_CORE_ERROR(@"Server failed readiness checks: %@", readinessError);
    //     if (error) *error = readinessError;
    //     return NO;
    // }

    // Initialize XRPC dispatcher
    _xrpcDispatcher = [XrpcDispatcher sharedDispatcher];

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

    // Start analytics collection for diagnostics dashboard
    [_analyticsCollector startCollecting];
    PDS_LOG_CORE_INFO(@"Sequencer analytics collector started");

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

    // Stop analytics collection
    [_analyticsCollector stopCollecting];
    _analyticsCollector = nil;

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
