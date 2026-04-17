#import "PDSConfiguration.h"
#import "Compat/Foundation/NSDataCompat.h"
#import "Core/PDSDataPaths.h"
#import "Debug/PDSLogger.h"

NSString *const PDSConfigErrorDomain = @"com.atproto.pds.config";

static NSString *PDSConfigTrimmed(NSString *value) {
  if (![value isKindOfClass:[NSString class]]) {
    return nil;
  }
  return [value
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]];
}

static BOOL PDSConfigHostLooksLocal(NSString *host) {
  NSString *normalized = [[PDSConfigTrimmed(host) lowercaseString] copy];
  return normalized.length == 0 || [normalized isEqualToString:@"localhost"] ||
         [normalized isEqualToString:@"127.0.0.1"] ||
         [normalized isEqualToString:@"::1"] ||
         [normalized isEqualToString:@"0.0.0.0"];
}

static NSString *PDSConfigNormalizedHost(NSString *host) {
  NSString *normalized = [[PDSConfigTrimmed(host) lowercaseString] copy];
  return normalized.length > 0 ? normalized : nil;
}

static NSString *PDSConfigCanonicalizedIssuerString(NSString *issuer) {
  NSString *trimmedIssuer = PDSConfigTrimmed(issuer);
  if (trimmedIssuer.length == 0) {
    return nil;
  }

  NSURLComponents *components =
      [NSURLComponents componentsWithString:trimmedIssuer];
  if (components.host.length == 0 || components.scheme.length == 0) {
    NSString *withScheme =
        [NSString stringWithFormat:@"https://%@", trimmedIssuer];
    components = [NSURLComponents componentsWithString:withScheme];
  }

  NSString *scheme =
      [[PDSConfigTrimmed(components.scheme) lowercaseString] copy];
  if (scheme.length == 0) {
    scheme = @"https";
  }

  NSString *host = PDSConfigNormalizedHost(components.host);
  if (host.length == 0) {
    return trimmedIssuer;
  }

  NSUInteger port =
      components.port != nil
          ? (NSUInteger)MAX((NSInteger)0, components.port.integerValue)
          : 0;
  BOOL defaultPort = ([scheme isEqualToString:@"https"] && port == 443) ||
                     ([scheme isEqualToString:@"http"] && port == 80);
  if (port > 0 && !defaultPort) {
    return [NSString
        stringWithFormat:@"%@://%@:%lu", scheme, host, (unsigned long)port];
  }
  return [NSString stringWithFormat:@"%@://%@", scheme, host];
}

static BOOL PDSConfigRunningUnderTests(void) {
  NSDictionary *env = [[NSProcessInfo processInfo] environment];
  if ([env[@"XCTestConfigurationFilePath"] length] > 0 ||
      [env[@"XCTestBundlePath"] length] > 0 ||
      [env[@"PDS_RUNNING_TESTS"] length] > 0) {
    return YES;
  }

  NSString *processName =
      [[[NSProcessInfo processInfo] processName] lowercaseString];
  return [processName containsString:@"alltests"] ||
         [processName containsString:@"xctest"];
}

@interface PDSConfiguration ()
- (BOOL)dictionary:(NSDictionary *)dictionary hasValueForKey:(NSString *)key;
@property (nonatomic, assign) BOOL plcReplicaEnabled;
@property (nonatomic, copy, nullable) NSString *plcReplicaUpstreamURL;
@property (nonatomic, copy, nullable) NSString *plcReplicaBindAddress;
@property (nonatomic, copy, nullable) NSString *plcReplicaDataDir;
@end

@implementation PDSConfiguration {
  NSDictionary *_config;
  NSString *_phoneVerificationProvider;
  PDSDataPaths *_dataPaths;
}

+ (instancetype)sharedConfiguration {
  static PDSConfiguration *shared = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    shared = [[PDSConfiguration alloc] init];
  });
  return shared;
}

+ (NSString *)defaultDataDirectory {
#if defined(__APPLE__)
  NSArray *urls = [[NSFileManager defaultManager]
      URLsForDirectory:NSApplicationSupportDirectory
             inDomains:NSUserDomainMask];
  NSURL *appSupport = [urls count] > 0 ? urls[0] : nil;
  return [[appSupport URLByAppendingPathComponent:@"ATProtoPDS"] path];
#else
  NSString *home = NSHomeDirectory();
  return [home stringByAppendingPathComponent:@".local/share/ATProtoPDS"];
#endif
}

+ (nullable instancetype)configurationWithPath:(NSString *)path
                                         error:(NSError **)error {
  PDSConfiguration *config = [[PDSConfiguration alloc] init];
  if ([config loadFromPath:path error:error]) {
    return config;
  }
  return nil;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    BOOL runningUnderTests = PDSConfigRunningUnderTests();
    _config = @{};

    _serverHost = @"0.0.0.0";
    _serverPort = 8080;
    _dataDirectory = [[self class] defaultDataDirectory];

    _issuer = nil;

    _plcURL = @"mock";
    _plcRetryCount = 3;
    _plcRetryDelayMs = 1000;
    _plcReplicaEnabled = NO;
    _plcReplicaUpstreamURL = nil;
    _plcReplicaBindAddress = nil;
    _plcReplicaDataDir = nil;

    _debugVerboseLogging = YES;
    _debugInMemoryDatabases = NO;
    _debugResetOnStartup = NO;
    _useNewRepositoryImplementation = NO;

    _userDatabasePoolMaxSize = 100;
    _serviceDatabasePoolMaxSize = 10;
    _didCachePoolMaxSize = 1000;
    _sequencerPoolMaxSize = 100;

    _accessTokenTtlSeconds = 3600;
    _refreshTokenTtlSeconds = 604800;
    _inviteCodeRequired = NO;
    _availableUserDomains = nil;
    _phoneVerificationProvider = @"none";
    _emailProviderType = @"none";
    _emailSmtpHost = nil;
    _emailSmtpPort = 587;
    _emailSmtpUsername = nil;
    _emailSmtpPassword = nil;
    _emailSmtpUseTLS = YES;

    _appViewURL = nil;
    _appViewDID = nil;
    _localAppViewEnabled = YES;

    _ozoneURL = nil;
    _ozoneDID = nil;

    _resendAPIKeySource = @"env";
    _resendAPIKeyEnvVar = @"RESEND_API_KEY";
    _resendKeychainService = @"com.atproto.pds";
    _resendKeychainAccount = @"resend_api_key";
    _resendFromAddress = nil;
    _resendAPIEndpoint = nil;

    _rateLimitEnabled = YES;
    _rateLimitRequestsPerMinute = 1000;
    _rateLimitDidLimit = 5000;
    _rateLimitDidWindowSeconds = 3600;
    _rateLimitIpLimit = 1000; // Increased default as 100/min is low for tests
    _rateLimitIpWindowSeconds = 60;
    _rateLimitBlobLimit = 50;
    _rateLimitBlobWindowSeconds = 3600;

    _blobStorageType = @"disk"; // Default to disk storage
    _s3Bucket = nil;
    _s3Region = nil;
    _s3Endpoint = nil;
    _s3KeyPrefix = nil;
    _s3AccessKeyId = nil;
    _s3SecretAccessKey = nil;
    _cdnURL = nil;

    _sslPinningEnabled = YES;

    // Logging defaults
    _logFilePath = nil; // No file logging by default
    _logLevel = PDSLogLevelInfo;
    _logFormat = PDSLogFormatText;
    _maxLogFileSize = 10 * 1024 * 1024; // 10MB
    _maxLogFiles = 5;
    _asyncLogging = YES;
    _enabledComponents = nil; // All components enabled

    // NodeInfo defaults
    _nodeinfoEnabled = YES;
    _nodeinfoSoftwareName = @"kaszlak";
    _nodeinfoSoftwareVersion = @"1.0.0";
    _nodeinfoRepositoryURL = @"https://github.com/jvalinsky/NSPds";
    _nodeinfoHomepageURL = @"https://github.com/jvalinsky/NSPds";
    _nodeinfoOpenRegistrations = YES;

    _privacyPolicyURL = nil;
    _termsOfServiceURL = nil;

    _crawlRelays = @[ @"https://bsky.network" ];

    // Security defaults
    _useBiometricProtection = runningUnderTests ? NO : YES;
    if ([self envVarExists:@"PDS_USE_BIOMETRIC_PROTECTION"]) {
      _useBiometricProtection =
          [self boolFromEnv:@"PDS_USE_BIOMETRIC_PROTECTION"
                    default:_useBiometricProtection];
    }

    _useKeychain = runningUnderTests ? NO : YES;
    if ([self envVarExists:@"PDS_USE_KEYCHAIN"]) {
      _useKeychain = [self boolFromEnv:@"PDS_USE_KEYCHAIN"
                               default:_useKeychain];
    }

    _masterSecret = [self resolveEnvOverrideForKey:@"PDS_MASTER_SECRET" default:nil];

    _useSecureEnclave = NO;
    if ([self envVarExists:@"PDS_USE_SECURE_ENCLAVE"]) {
      _useSecureEnclave = [self boolFromEnv:@"PDS_USE_SECURE_ENCLAVE" default:NO];
    }

    _requireDPoPNonce = [self boolFromEnv:@"PDS_REQUIRE_DPOP_NONCE" default:NO];

    // Apply environment overrides and empty config defaults
    [self applyConfig:_config];
  }
  return self;
}

- (BOOL)loadFromPath:(NSString *)path error:(NSError **)error {
  NSFileManager *fm = [NSFileManager defaultManager];
  if (![fm fileExistsAtPath:path]) {
    if (error) {
      *error = [NSError
          errorWithDomain:PDSConfigErrorDomain
                     code:PDSConfigErrorFileNotFound
                 userInfo:@{
                   NSLocalizedDescriptionKey : [NSString
                       stringWithFormat:@"Config file not found: %@", path]
                 }];
    }
    return NO;
  }

  NSError *readError = nil;
#if defined(__APPLE__)
  NSData *data =
      [NSData dataWithContentsOfFile:path options:0 error:&readError];
#else
  NSData *data = [NSData dataWithContentsOfFile:path];
  readError = nil; // GNUstep doesn't support error parameter
#endif
  if (!data) {
    if (error) {
      *error = [NSError
          errorWithDomain:PDSConfigErrorDomain
                     code:PDSConfigErrorFileNotFound
                 userInfo:@{
                   NSLocalizedDescriptionKey : [NSString
                       stringWithFormat:@"Failed to read config file: %@",
                                        readError.localizedDescription]
                 }];
    }
    return NO;
  }

  NSError *parseError = nil;
  NSDictionary *yamlConfig =
      [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
  if (!yamlConfig && parseError) {
    if (error) {
      *error = [NSError
          errorWithDomain:PDSConfigErrorDomain
                     code:PDSConfigErrorInvalidFormat
                 userInfo:@{
                   NSLocalizedDescriptionKey : [NSString
                       stringWithFormat:@"Failed to parse config file: %@",
                                        parseError.localizedDescription]
                 }];
    }
    return NO;
  }

  _config = [yamlConfig copy] ?: @{};
  [self applyConfig:_config];
  return YES;
}

- (void)applyConfig:(NSDictionary *)config {
  _dataPaths = nil; // Reset cached data paths so they are re-evaluated
  NSDictionary *server = config[@"server"];
  if (server) {
    if (server[@"host"])
      _serverHost =
          [self resolveEnvOverrideForKey:@"PDS_HOST" default:server[@"host"]];

    // Add support for PDS_HOSTNAME env var
    NSString *envHost =
        [self resolveEnvOverrideForKey:@"PDS_HOSTNAME" default:nil];
    if (envHost.length > 0) {
      _serverHost = envHost;
    }

    if (server[@"port"])
      _serverPort = [server[@"port"] unsignedIntegerValue];
    if (server[@"data_dir"])
      _dataDirectory = server[@"data_dir"];
    
    _dataDirectory = [self resolveEnvOverrideForKey:@"PDS_DATA_DIR"
                                            default:_dataDirectory];
    if (server[@"issuer"])
      _issuer = [self resolveEnvOverrideForKey:@"PDS_ISSUER"
                                       default:server[@"issuer"]];
    if (server[@"available_user_domains"] &&
        [server[@"available_user_domains"] isKindOfClass:[NSArray class]]) {
      _availableUserDomains = server[@"available_user_domains"];
    }

    // Add support for PDS_AVAILABLE_USER_DOMAINS env var (comma separated)
    NSString *envDomains =
        [self resolveEnvOverrideForKey:@"PDS_AVAILABLE_USER_DOMAINS"
                               default:nil];
    if (envDomains.length > 0) {
      _availableUserDomains = [envDomains componentsSeparatedByString:@","];
    }
  }

  // Top-level issuer override
  if (config[@"issuer"])
    _issuer =
        [self resolveEnvOverrideForKey:@"PDS_ISSUER" default:config[@"issuer"]];

  // Always check PDS_ISSUER env var
  NSString *envIssuer =
      [self resolveEnvOverrideForKey:@"PDS_ISSUER" default:nil];
  if (envIssuer.length > 0) {
    _issuer = envIssuer;
  }

  NSString *envMasterSecret = [self resolveEnvOverrideForKey:@"PDS_MASTER_SECRET" default:nil];
  if (envMasterSecret.length > 0) {
    _masterSecret = envMasterSecret;
    PDS_LOG_AUTH_DEBUG(@"Master secret resolved from environment (length: %lu)", (unsigned long)_masterSecret.length);
  }

  if ([self envVarExists:@"PDS_USE_SECURE_ENCLAVE"]) {
    _useSecureEnclave = [self boolFromEnv:@"PDS_USE_SECURE_ENCLAVE" default:NO];
  }

  if ([self envVarExists:@"PDS_USE_KEYCHAIN"]) {
    _useKeychain = [self boolFromEnv:@"PDS_USE_KEYCHAIN" default:YES];
  }

  if ([self envVarExists:@"PDS_USE_BIOMETRIC_PROTECTION"]) {
    _useBiometricProtection =
        [self boolFromEnv:@"PDS_USE_BIOMETRIC_PROTECTION" default:YES];
  }

  _requireDPoPNonce = [self boolFromEnv:@"PDS_REQUIRE_DPOP_NONCE" default:NO];

  NSDictionary *plc = config[@"plc"];
  if (plc) {
    if (plc[@"url"])
      _plcURL =
          [self resolveEnvOverrideForKey:@"PDS_PLC_URL" default:plc[@"url"]];
    if (plc[@"retry_count"])
      _plcRetryCount = [plc[@"retry_count"] unsignedIntegerValue];
    if (plc[@"retry_delay_ms"])
      _plcRetryDelayMs = [plc[@"retry_delay_ms"] unsignedIntegerValue];
    
    NSDictionary *replica = plc[@"replica"];
    if (replica) {
      _plcReplicaEnabled = [self boolFromEnv:@"PDS_PLC_REPLICA_ENABLED" default:[replica[@"enabled"] boolValue]];
      _plcReplicaUpstreamURL = [self resolveEnvOverrideForKey:@"PDS_PLC_REPLICA_UPSTREAM_URL" default:replica[@"upstream_url"]];
      _plcReplicaBindAddress = [self resolveEnvOverrideForKey:@"PDS_PLC_REPLICA_BIND" default:replica[@"bind_address"]];
      _plcReplicaDataDir = [self resolveEnvOverrideForKey:@"PDS_PLC_REPLICA_DATA_DIR" default:replica[@"data_dir"]];
    }
  }

  // Allow env overrides even when plc section is missing.
  NSString *envPlcURL =
      [[NSProcessInfo processInfo] environment][@"PDS_PLC_URL"];
  if (envPlcURL.length > 0) {
    _plcURL = envPlcURL;
  }

  NSDictionary *debug = config[@"debug"];
  if (debug) {
    // Use objectForKey: != nil checks instead of if(value) since @NO is falsy
    if (debug[@"verbose_logging"] != nil)
      _debugVerboseLogging =
          [self boolFromEnv:@"PDS_DEBUG_VERBOSE"
                    default:[debug[@"verbose_logging"] boolValue]];
    if (debug[@"in_memory_databases"] != nil)
      _debugInMemoryDatabases =
          [self boolFromEnv:@"PDS_DEBUG_IN_MEMORY"
                    default:[debug[@"in_memory_databases"] boolValue]];
    if (debug[@"reset_on_startup"] != nil)
      _debugResetOnStartup =
          [self boolFromEnv:@"PDS_DEBUG_RESET"
                    default:[debug[@"reset_on_startup"] boolValue]];
    if (debug[@"use_new_repository"] != nil)
      _useNewRepositoryImplementation =
          [self boolFromEnv:@"PDS_USE_NEW_REPO"
                    default:[debug[@"use_new_repository"] boolValue]];
  }

  NSDictionary *database = config[@"database"];
  if (database) {
    if ([self dictionary:database hasValueForKey:@"user_pool_max_size"])
      _userDatabasePoolMaxSize =
          [database[@"user_pool_max_size"] unsignedIntegerValue];
    if ([self dictionary:database hasValueForKey:@"service_pool_max_size"])
      _serviceDatabasePoolMaxSize =
          [database[@"service_pool_max_size"] unsignedIntegerValue];
    if ([self dictionary:database hasValueForKey:@"did_cache_pool_max_size"])
      _didCachePoolMaxSize =
          [database[@"did_cache_pool_max_size"] unsignedIntegerValue];
    if ([self dictionary:database hasValueForKey:@"sequencer_pool_max_size"])
      _sequencerPoolMaxSize =
          [database[@"sequencer_pool_max_size"] unsignedIntegerValue];
  }

  NSDictionary *session = config[@"session"];
  if (session) {
    if ([self dictionary:session hasValueForKey:@"access_token_ttl_seconds"])
      _accessTokenTtlSeconds =
          [session[@"access_token_ttl_seconds"] unsignedIntegerValue];
    if ([self dictionary:session hasValueForKey:@"refresh_token_ttl_seconds"])
      _refreshTokenTtlSeconds =
          [session[@"refresh_token_ttl_seconds"] unsignedIntegerValue];
    if ([self dictionary:session hasValueForKey:@"invite_code_required"])
      _inviteCodeRequired = [session[@"invite_code_required"] boolValue];
  }

  NSDictionary *phoneVerification = config[@"phone_verification"];
  if (phoneVerification) {
    NSString *provider = phoneVerification[@"provider"];
    if ([provider isKindOfClass:[NSString class]]) {
      NSString *trimmed =
          [provider stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if (trimmed.length > 0) {
        _phoneVerificationProvider = trimmed.lowercaseString;
      }
    }
  }

  NSDictionary *email = config[@"email"];
  if (email) {
    NSString *provider = email[@"provider"];
    if ([provider isKindOfClass:[NSString class]]) {
      _emailProviderType =
          [self resolveEnvOverrideForKey:@"PDS_EMAIL_PROVIDER" default:provider]
              .lowercaseString;
    }

    if (email[@"smtp_host"])
      _emailSmtpHost = [self resolveEnvOverrideForKey:@"PDS_EMAIL_SMTP_HOST"
                                              default:email[@"smtp_host"]];
    if ([self dictionary:email hasValueForKey:@"smtp_port"])
      _emailSmtpPort = [email[@"smtp_port"] unsignedIntegerValue];
    if (email[@"smtp_username"])
      _emailSmtpUsername =
          [self resolveEnvOverrideForKey:@"PDS_EMAIL_SMTP_USERNAME"
                                 default:email[@"smtp_username"]];
    if (email[@"smtp_password"])
      _emailSmtpPassword =
          [self resolveEnvOverrideForKey:@"PDS_EMAIL_SMTP_PASSWORD"
                                 default:email[@"smtp_password"]];
    if ([self dictionary:email hasValueForKey:@"smtp_use_tls"])
      _emailSmtpUseTLS = [self boolFromEnv:@"PDS_EMAIL_SMTP_USE_TLS"
                                   default:[email[@"smtp_use_tls"] boolValue]];

    _resendAPIKeySource =
        [self resolveEnvOverrideForKey:@"PDS_RESEND_KEY_SOURCE"
                               default:email[@"resend_api_key_source"]
                                           ?: _resendAPIKeySource];
    _resendAPIKeyEnvVar =
        [self resolveEnvOverrideForKey:@"PDS_RESEND_KEY_ENV_VAR"
                               default:email[@"resend_api_key_env_var"]
                                           ?: _resendAPIKeyEnvVar];
    _resendKeychainService =
        [self resolveEnvOverrideForKey:@"PDS_RESEND_KEYCHAIN_SERVICE"
                               default:email[@"resend_keychain_service"]
                                           ?: _resendKeychainService];
    _resendKeychainAccount =
        [self resolveEnvOverrideForKey:@"PDS_RESEND_KEYCHAIN_ACCOUNT"
                               default:email[@"resend_keychain_account"]
                                           ?: _resendKeychainAccount];
    _resendFromAddress =
        [self resolveEnvOverrideForKey:@"PDS_RESEND_FROM_ADDRESS"
                               default:email[@"resend_from_address"]
                                           ?: _resendFromAddress];
    _resendAPIEndpoint =
        [self resolveEnvOverrideForKey:@"PDS_RESEND_API_ENDPOINT"
                               default:email[@"resend_api_endpoint"]
                                           ?: _resendAPIEndpoint];
  } else {
    // Check environment variables even if config section is missing
    _emailProviderType = [self resolveEnvOverrideForKey:@"PDS_EMAIL_PROVIDER"
                                                default:_emailProviderType]
                             .lowercaseString;
    _emailSmtpHost = [self resolveEnvOverrideForKey:@"PDS_EMAIL_SMTP_HOST"
                                            default:_emailSmtpHost];
    if ([self envVarExists:@"PDS_EMAIL_SMTP_PORT"])
      _emailSmtpPort = [[self resolveEnvOverrideForKey:@"PDS_EMAIL_SMTP_PORT"
                                               default:nil] integerValue];
    _emailSmtpUsername =
        [self resolveEnvOverrideForKey:@"PDS_EMAIL_SMTP_USERNAME"
                               default:_emailSmtpUsername];
    _emailSmtpPassword =
        [self resolveEnvOverrideForKey:@"PDS_EMAIL_SMTP_PASSWORD"
                               default:_emailSmtpPassword];
    if ([self envVarExists:@"PDS_EMAIL_SMTP_USE_TLS"])
      _emailSmtpUseTLS =
          [self boolFromEnv:@"PDS_EMAIL_SMTP_USE_TLS" default:_emailSmtpUseTLS];

    _resendAPIKeySource =
        [self resolveEnvOverrideForKey:@"PDS_RESEND_KEY_SOURCE"
                               default:_resendAPIKeySource];
    _resendAPIKeyEnvVar =
        [self resolveEnvOverrideForKey:@"PDS_RESEND_KEY_ENV_VAR"
                               default:_resendAPIKeyEnvVar];
    _resendKeychainService =
        [self resolveEnvOverrideForKey:@"PDS_RESEND_KEYCHAIN_SERVICE"
                               default:_resendKeychainService];
    _resendKeychainAccount =
        [self resolveEnvOverrideForKey:@"PDS_RESEND_KEYCHAIN_ACCOUNT"
                               default:_resendKeychainAccount];
    _resendFromAddress =
        [self resolveEnvOverrideForKey:@"PDS_RESEND_FROM_ADDRESS"
                               default:_resendFromAddress];
    _resendAPIEndpoint =
        [self resolveEnvOverrideForKey:@"PDS_RESEND_API_ENDPOINT"
                               default:_resendAPIEndpoint];
  }

  NSDictionary *rateLimit = config[@"rate_limit"];
  if (rateLimit) {
    if ([self dictionary:rateLimit hasValueForKey:@"enabled"])
      _rateLimitEnabled = [rateLimit[@"enabled"] boolValue];
    if ([self dictionary:rateLimit hasValueForKey:@"requests_per_minute"])
      _rateLimitRequestsPerMinute =
          [rateLimit[@"requests_per_minute"] unsignedIntegerValue];
    if ([self dictionary:rateLimit hasValueForKey:@"burst_size"])
      _rateLimitBurstSize = [rateLimit[@"burst_size"] unsignedIntegerValue];
    // Load granular limits from config map if present, else fallback check
    if ([self dictionary:rateLimit hasValueForKey:@"did_limit"])
      _rateLimitDidLimit = [rateLimit[@"did_limit"] unsignedIntegerValue];
    if ([self dictionary:rateLimit hasValueForKey:@"did_window"])
      _rateLimitDidWindowSeconds = [rateLimit[@"did_window"] doubleValue];
    if ([self dictionary:rateLimit hasValueForKey:@"ip_limit"])
      _rateLimitIpLimit = [rateLimit[@"ip_limit"] unsignedIntegerValue];
    if ([self dictionary:rateLimit hasValueForKey:@"ip_window"])
      _rateLimitIpWindowSeconds = [rateLimit[@"ip_window"] doubleValue];
    if ([self dictionary:rateLimit hasValueForKey:@"blob_limit"])
      _rateLimitBlobLimit = [rateLimit[@"blob_limit"] unsignedIntegerValue];
    if ([self dictionary:rateLimit hasValueForKey:@"blob_window"])
      _rateLimitBlobWindowSeconds = [rateLimit[@"blob_window"] doubleValue];
  }

  // Environment variables override everything
  if ([self envVarExists:@"PDS_RATELIMIT_ENABLED"])
    _rateLimitEnabled =
        [self boolFromEnv:@"PDS_RATELIMIT_ENABLED" default:_rateLimitEnabled];

  NSString *envDidLimit =
      [self resolveEnvOverrideForKey:@"PDS_RATELIMIT_DID_LIMIT" default:nil];
  if (envDidLimit)
    _rateLimitDidLimit = [envDidLimit integerValue];

  NSString *envDidWindow =
      [self resolveEnvOverrideForKey:@"PDS_RATELIMIT_DID_WINDOW" default:nil];
  if (envDidWindow)
    _rateLimitDidWindowSeconds = [envDidWindow doubleValue];

  NSString *envIpLimit =
      [self resolveEnvOverrideForKey:@"PDS_RATELIMIT_IP_LIMIT" default:nil];
  if (envIpLimit)
    _rateLimitIpLimit = [envIpLimit integerValue];

  NSString *envIpWindow =
      [self resolveEnvOverrideForKey:@"PDS_RATELIMIT_IP_WINDOW" default:nil];
  if (envIpWindow)
    _rateLimitIpWindowSeconds = [envIpWindow doubleValue];

  NSString *envBlobLimit =
      [self resolveEnvOverrideForKey:@"PDS_RATELIMIT_BLOB_LIMIT" default:nil];
  if (envBlobLimit)
    _rateLimitBlobLimit = [envBlobLimit integerValue];

  NSString *envBlobWindow =
      [self resolveEnvOverrideForKey:@"PDS_RATELIMIT_BLOB_WINDOW" default:nil];
  if (envBlobWindow)
    _rateLimitBlobWindowSeconds = [envBlobWindow doubleValue];

  NSDictionary *sslPinning = config[@"ssl_pinning"];
  if (sslPinning) {
    if ([self dictionary:sslPinning hasValueForKey:@"enabled"])
      _sslPinningEnabled = [sslPinning[@"enabled"] boolValue];
  }

  NSDictionary *logging = config[@"logging"];
  if (logging) {
    if (logging[@"file_path"]) {
      _logFilePath = [self resolveEnvOverrideForKey:@"PDS_LOG_FILE"
                                            default:logging[@"file_path"]];
    }

    if (logging[@"level"]) {
      NSString *level =
          [[self resolveEnvOverrideForKey:@"PDS_LOG_LEVEL"
                                  default:logging[@"level"]] lowercaseString];
      if ([level isEqualToString:@"debug"]) {
        _logLevel = PDSLogLevelDebug;
      } else if ([level isEqualToString:@"info"]) {
        _logLevel = PDSLogLevelInfo;
      } else if ([level isEqualToString:@"warn"]) {
        _logLevel = PDSLogLevelWarn;
      } else if ([level isEqualToString:@"error"]) {
        _logLevel = PDSLogLevelError;
      }
    }

    if (logging[@"format"]) {
      NSString *format =
          [[self resolveEnvOverrideForKey:@"PDS_LOG_FORMAT"
                                  default:logging[@"format"]] lowercaseString];
      if ([format isEqualToString:@"json"]) {
        _logFormat = PDSLogFormatJSON;
      } else if ([format isEqualToString:@"both"]) {
        _logFormat = PDSLogFormatBoth;
      } else {
        _logFormat = PDSLogFormatText;
      }
    }

    if ([self dictionary:logging hasValueForKey:@"max_file_size_mb"]) {
      NSString *envValue =
          [[NSProcessInfo processInfo] environment][@"PDS_LOG_MAX_SIZE_MB"];
      NSUInteger sizeMB =
          envValue ? [envValue integerValue]
                   : [logging[@"max_file_size_mb"] unsignedIntegerValue];
      _maxLogFileSize = sizeMB * 1024 * 1024; // Convert MB to bytes
    }

    if ([self dictionary:logging hasValueForKey:@"max_files"]) {
      NSString *envValue =
          [[NSProcessInfo processInfo] environment][@"PDS_LOG_MAX_FILES"];
      _maxLogFiles = envValue ? [envValue integerValue]
                              : [logging[@"max_files"] unsignedIntegerValue];
    }

    if ([self dictionary:logging hasValueForKey:@"async"]) {
      _asyncLogging = [self boolFromEnv:@"PDS_LOG_ASYNC"
                                default:[logging[@"async"] boolValue]];
    }

    if (logging[@"components"]) {
      NSString *envValue =
          [[NSProcessInfo processInfo] environment][@"PDS_LOG_COMPONENTS"];
      if (envValue) {
        _enabledComponents = [envValue componentsSeparatedByString:@","];
      } else {
        _enabledComponents = logging[@"components"];
      }
    }
  }

  NSDictionary *nodeinfo = config[@"nodeinfo"];
  if (nodeinfo) {
    if ([self dictionary:nodeinfo hasValueForKey:@"enabled"])
      _nodeinfoEnabled = [self boolFromEnv:@"PDS_NODEINFO_ENABLED"
                                   default:[nodeinfo[@"enabled"] boolValue]];
    if (nodeinfo[@"software_name"])
      _nodeinfoSoftwareName =
          [self resolveEnvOverrideForKey:@"PDS_NODEINFO_SOFTWARE_NAME"
                                 default:nodeinfo[@"software_name"]];
    if (nodeinfo[@"software_version"])
      _nodeinfoSoftwareVersion =
          [self resolveEnvOverrideForKey:@"PDS_NODEINFO_SOFTWARE_VERSION"
                                 default:nodeinfo[@"software_version"]];
    if (nodeinfo[@"repository_url"])
      _nodeinfoRepositoryURL =
          [self resolveEnvOverrideForKey:@"PDS_NODEINFO_REPOSITORY_URL"
                                 default:nodeinfo[@"repository_url"]];
    if (nodeinfo[@"homepage_url"])
      _nodeinfoHomepageURL =
          [self resolveEnvOverrideForKey:@"PDS_NODEINFO_HOMEPAGE_URL"
                                 default:nodeinfo[@"homepage_url"]];
    if ([self dictionary:nodeinfo hasValueForKey:@"open_registrations"])
      _nodeinfoOpenRegistrations =
          [self boolFromEnv:@"PDS_NODEINFO_OPEN_REGISTRATIONS"
                    default:[nodeinfo[@"open_registrations"] boolValue]];
  }

  NSDictionary *links = config[@"links"];
  if (links) {
    if (links[@"privacy_policy"])
      _privacyPolicyURL =
          [self resolveEnvOverrideForKey:@"PDS_PRIVACY_POLICY_URL"
                                 default:links[@"privacy_policy"]];
    if (links[@"terms_of_service"])
      _termsOfServiceURL =
          [self resolveEnvOverrideForKey:@"PDS_TERMS_OF_SERVICE_URL"
                                 default:links[@"terms_of_service"]];
  }

  // Environment variables override everything
  NSString *envPrivacy =
      [self resolveEnvOverrideForKey:@"PDS_PRIVACY_POLICY_URL" default:nil];
  if (envPrivacy)
    _privacyPolicyURL = envPrivacy;

  NSString *envTerms =
      [self resolveEnvOverrideForKey:@"PDS_TERMS_OF_SERVICE_URL" default:nil];
  if (envTerms)
    _termsOfServiceURL = envTerms;

  NSArray *relays = config[@"relays"];
  if ([relays isKindOfClass:[NSArray class]]) {
    _crawlRelays = [relays copy];
  }

  NSString *envRelays =
      [self resolveEnvOverrideForKey:@"PDS_CRAWL_RELAYS" default:nil];
  if (envRelays.length > 0) {
    _crawlRelays = [envRelays componentsSeparatedByString:@","];
  }

  // Also check environment variables if no config file logging section
  if (!logging) {
    NSString *logFile =
        [[NSProcessInfo processInfo] environment][@"PDS_LOG_FILE"];
    if (logFile)
      _logFilePath = logFile;

    NSString *logLevel = [[[NSProcessInfo processInfo]
        environment][@"PDS_LOG_LEVEL"] lowercaseString];
    if (logLevel) {
      if ([logLevel isEqualToString:@"debug"])
        _logLevel = PDSLogLevelDebug;
      else if ([logLevel isEqualToString:@"info"])
        _logLevel = PDSLogLevelInfo;
      else if ([logLevel isEqualToString:@"warn"])
        _logLevel = PDSLogLevelWarn;
      else if ([logLevel isEqualToString:@"error"])
        _logLevel = PDSLogLevelError;
    }

    NSString *logFormat = [[[NSProcessInfo processInfo]
        environment][@"PDS_LOG_FORMAT"] lowercaseString];
    if (logFormat) {
      if ([logFormat isEqualToString:@"json"])
        _logFormat = PDSLogFormatJSON;
      else if ([logFormat isEqualToString:@"both"])
        _logFormat = PDSLogFormatBoth;
      else
        _logFormat = PDSLogFormatText;
    }
  }

  NSDictionary *appview = config[@"appview"];
  if (appview) {
    _appViewURL = [self resolveEnvOverrideForKey:@"PDS_APPVIEW_URL"
                                         default:appview[@"url"]];
    _appViewDID = [self resolveEnvOverrideForKey:@"PDS_APPVIEW_DID"
                                         default:appview[@"did"]];
    if (appview[@"local_enabled"] != nil) {
      _localAppViewEnabled =
          [self boolFromEnv:@"PDS_LOCAL_APPVIEW"
                    default:[appview[@"local_enabled"] boolValue]];
    }
  }

  // Environment variables override everything for AppView as well
  NSString *envAppViewURL =
      [self resolveEnvOverrideForKey:@"PDS_APPVIEW_URL" default:nil];
  if (envAppViewURL.length > 0) {
    _appViewURL = envAppViewURL;
  }

  NSString *envAppViewDID =
      [self resolveEnvOverrideForKey:@"PDS_APPVIEW_DID" default:nil];
  if (envAppViewDID.length > 0) {
    _appViewDID = envAppViewDID;
  }

  if ([self envVarExists:@"PDS_LOCAL_APPVIEW"]) {
    _localAppViewEnabled =
        [self boolFromEnv:@"PDS_LOCAL_APPVIEW" default:_localAppViewEnabled];
  }

  // Ozone moderation service configuration
  NSDictionary *ozone = config[@"ozone"];
  if (ozone) {
    _ozoneURL = [self resolveEnvOverrideForKey:@"PDS_OZONE_URL"
                                       default:ozone[@"url"]];
    _ozoneDID = [self resolveEnvOverrideForKey:@"PDS_OZONE_DID"
                                       default:ozone[@"did"]];
  }

  // Environment variables override everything for Ozone as well
  NSString *envOzoneURL =
      [self resolveEnvOverrideForKey:@"PDS_OZONE_URL" default:nil];
  if (envOzoneURL.length > 0) {
    _ozoneURL = envOzoneURL;
  }

  NSString *envOzoneDID =
      [self resolveEnvOverrideForKey:@"PDS_OZONE_DID" default:nil];
  if (envOzoneDID.length > 0) {
    _ozoneDID = envOzoneDID;
  }

  // Blob storage configuration
  NSDictionary *blobStorage = config[@"blob_storage"];
  if (blobStorage) {
    if (blobStorage[@"storage_type"])
      _blobStorageType = [self resolveEnvOverrideForKey:@"PDS_BLOB_STORAGE_TYPE"
                                                default:blobStorage[@"storage_type"]];

    if (blobStorage[@"s3_bucket"])
      _s3Bucket = [self resolveEnvOverrideForKey:@"PDS_S3_BUCKET"
                                         default:blobStorage[@"s3_bucket"]];
    if (blobStorage[@"s3_region"])
      _s3Region = [self resolveEnvOverrideForKey:@"PDS_S3_REGION"
                                         default:blobStorage[@"s3_region"]];
    if (blobStorage[@"s3_endpoint"])
      _s3Endpoint = [self resolveEnvOverrideForKey:@"PDS_S3_ENDPOINT"
                                           default:blobStorage[@"s3_endpoint"]];
    if (blobStorage[@"s3_key_prefix"])
      _s3KeyPrefix = [self resolveEnvOverrideForKey:@"PDS_S3_KEY_PREFIX"
                                            default:blobStorage[@"s3_key_prefix"]];
    if (blobStorage[@"s3_access_key_id"])
      _s3AccessKeyId = [self resolveEnvOverrideForKey:@"PDS_S3_ACCESS_KEY_ID"
                                              default:blobStorage[@"s3_access_key_id"]];
    if (blobStorage[@"s3_secret_access_key"])
      _s3SecretAccessKey = [self resolveEnvOverrideForKey:@"PDS_S3_SECRET_ACCESS_KEY"
                                                  default:blobStorage[@"s3_secret_access_key"]];
    if (blobStorage[@"cdn_url"])
      _cdnURL = [self resolveEnvOverrideForKey:@"PDS_CDN_URL"
                                      default:blobStorage[@"cdn_url"]];
  }

  // Environment variable overrides
  NSString *envBlobStorageType = [self resolveEnvOverrideForKey:@"PDS_BLOB_STORAGE_TYPE" default:nil];
  if (envBlobStorageType.length > 0)
    _blobStorageType = envBlobStorageType;

  NSString *envS3Bucket = [self resolveEnvOverrideForKey:@"PDS_S3_BUCKET" default:nil];
  if (envS3Bucket.length > 0)
    _s3Bucket = envS3Bucket;

  NSString *envS3Region = [self resolveEnvOverrideForKey:@"PDS_S3_REGION" default:nil];
  if (envS3Region.length > 0)
    _s3Region = envS3Region;

  NSString *envS3Endpoint = [self resolveEnvOverrideForKey:@"PDS_S3_ENDPOINT" default:nil];
  if (envS3Endpoint.length > 0)
    _s3Endpoint = envS3Endpoint;

  NSString *envS3KeyPrefix = [self resolveEnvOverrideForKey:@"PDS_S3_KEY_PREFIX" default:nil];
  if (envS3KeyPrefix.length > 0)
    _s3KeyPrefix = envS3KeyPrefix;

  NSString *envS3AccessKeyId = [self resolveEnvOverrideForKey:@"PDS_S3_ACCESS_KEY_ID" default:nil];
  if (envS3AccessKeyId.length > 0)
    _s3AccessKeyId = envS3AccessKeyId;

  NSString *envS3SecretAccessKey = [self resolveEnvOverrideForKey:@"PDS_S3_SECRET_ACCESS_KEY" default:nil];
  if (envS3SecretAccessKey.length > 0)
    _s3SecretAccessKey = envS3SecretAccessKey;

  NSString *envCdnURL = [self resolveEnvOverrideForKey:@"PDS_CDN_URL" default:nil];
  if (envCdnURL.length > 0)
    _cdnURL = envCdnURL;
}

- (BOOL)envVarExists:(NSString *)envKey {
  return [self resolveEnvOverrideForKey:envKey default:nil] != nil;
}

- (BOOL)dictionary:(NSDictionary *)dictionary hasValueForKey:(NSString *)key {
  if (![dictionary isKindOfClass:[NSDictionary class]]) {
    return NO;
  }
  return dictionary[key] != nil;
}

- (NSString *)resolveEnvOverrideForKey:(NSString *)envKey
                               default:(NSString *)defaultValue {
  NSString *envValue = [[NSProcessInfo processInfo] environment][envKey];
  return envValue ?: defaultValue;
}

- (BOOL)boolFromEnv:(NSString *)envKey default:(BOOL)defaultValue {
  NSString *envValue = [[NSProcessInfo processInfo] environment][envKey];
  if (!envValue)
    return defaultValue;
  return [@"true" isEqualToString:envValue.lowercaseString] ||
         [@"1" isEqualToString:envValue];
}

- (nullable NSArray *)arrayForKey:(NSString *)key {
  NSArray *components = [key componentsSeparatedByString:@"."];
  id current = _config;
  for (NSString *component in components) {
    if (![current isKindOfClass:[NSDictionary class]])
      return nil;
    current = ((NSDictionary *)current)[component];
    if (!current)
      return nil;
  }
  return [current isKindOfClass:[NSArray class]] ? (NSArray *)current : nil;
}

- (nullable NSString *)stringForKey:(NSString *)key {
  NSArray *components = [key componentsSeparatedByString:@"."];
  id current = _config;
  for (NSString *component in components) {
    if (![current isKindOfClass:[NSDictionary class]])
      return nil;
    current = ((NSDictionary *)current)[component];
    if (!current)
      return nil;
  }
  return [current isKindOfClass:[NSString class]] ? (NSString *)current : nil;
}

- (NSInteger)integerForKey:(NSString *)key {
  NSString *value = [self stringForKey:key];
  return value ? [value integerValue] : 0;
}

- (BOOL)boolForKey:(NSString *)key {
  NSString *value = [self stringForKey:key];
  if (!value)
    return NO;
  return [@"true" isEqualToString:value.lowercaseString] ||
         [@"1" isEqualToString:value];
}

- (NSString *)canonicalIssuer {
  return [self canonicalIssuerWithPortHint:0];
}

- (NSString *)canonicalIssuerWithPortHint:(NSUInteger)portHint {
  NSString *configuredIssuer = PDSConfigCanonicalizedIssuerString(self.issuer);
  if (configuredIssuer.length > 0) {
    return configuredIssuer;
  }

  NSString *host = PDSConfigNormalizedHost(self.serverHost);
  if (PDSConfigHostLooksLocal(host)) {
    host = @"localhost";
  }
  if (host.length == 0) {
    host = @"localhost";
  }

  // Check if host already contains a port
  BOOL hostHasPort = [host containsString:@":"];

  BOOL localHost = PDSConfigHostLooksLocal(host);
  NSString *scheme = localHost ? @"http" : @"https";

  if (hostHasPort) {
    return [NSString stringWithFormat:@"%@://%@", scheme, host];
  }

  NSUInteger port =
      portHint > 0 ? portHint : (self.serverPort > 0 ? self.serverPort : 2583);
  BOOL defaultPort = ([scheme isEqualToString:@"https"] && port == 443) ||
                     ([scheme isEqualToString:@"http"] && port == 80);
  if (defaultPort) {
    return [NSString stringWithFormat:@"%@://%@", scheme, host];
  }
  return [NSString
      stringWithFormat:@"%@://%@:%lu", scheme, host, (unsigned long)port];
}

- (NSString *)canonicalHostname {
  NSString *canonicalIssuer = [self canonicalIssuerWithPortHint:0];
  NSURLComponents *components =
      [NSURLComponents componentsWithString:canonicalIssuer];
  NSString *host = PDSConfigNormalizedHost(components.host);

  // If issuer had a port, components.host only returns the host portion.
  // If we want to return exactly what's needed for the domain part of the
  // handle without ports, we use components.host
  if (host.length > 0) {
    return host;
  }

  NSString *fallbackHost = PDSConfigNormalizedHost(self.serverHost);

  // Strip port from fallbackHost if present
  if ([fallbackHost containsString:@":"]) {
    fallbackHost =
        [[fallbackHost componentsSeparatedByString:@":"] firstObject];
  }

  if (PDSConfigHostLooksLocal(fallbackHost)) {
    return @"localhost";
  }
  return fallbackHost.length > 0 ? fallbackHost : @"localhost";
}

- (PDSDataPaths *)dataPaths {
  if (!_dataPaths) {
    _dataPaths = [PDSDataPaths pathsForBaseDirectory:self.dataDirectory];
  }
  return _dataPaths;
}

- (NSString *)phoneVerificationProvider {
  NSString *envValue =
      [self resolveEnvOverrideForKey:@"PDS_PHONE_VERIFICATION_PROVIDER"
                             default:nil];
  NSString *candidate = envValue ?: _phoneVerificationProvider;
  if (![candidate isKindOfClass:[NSString class]]) {
    return @"none";
  }

  NSString *trimmed = [[candidate
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]]
      lowercaseString];
  return trimmed.length > 0 ? trimmed : @"none";
}

@end
