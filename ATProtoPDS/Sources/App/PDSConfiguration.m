#import "PDSConfiguration.h"
#import "Debug/PDSLogger.h"

NSString *const PDSConfigErrorDomain = @"com.atproto.pds.config";

@implementation PDSConfiguration {
    NSDictionary *_config;
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
    NSArray *urls = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                              inDomains:NSUserDomainMask];
    NSURL *appSupport = [urls count] > 0 ? urls[0] : nil;
    return [[appSupport URLByAppendingPathComponent:@"ATProtoPDS"] path];
#else
    NSString *home = NSHomeDirectory();
    return [home stringByAppendingPathComponent:@".local/share/ATProtoPDS"];
#endif
}

+ (nullable instancetype)configurationWithPath:(NSString *)path error:(NSError **)error {
    PDSConfiguration *config = [[PDSConfiguration alloc] init];
    if ([config loadFromPath:path error:error]) {
        return config;
    }
    return nil;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _config = @{};

        _serverHost = @"0.0.0.0";
        _serverPort = 8080;
        _dataDirectory = @"./data";

        _plcURL = @"mock";
        _plcRetryCount = 3;
        _plcRetryDelayMs = 1000;

        _debugSkipPlcOperations = YES;
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

        _rateLimitEnabled = YES;
        _rateLimitRequestsPerMinute = 1000;
        _rateLimitDidLimit = 5000;
        _rateLimitDidWindowSeconds = 3600;
        _rateLimitIpLimit = 1000; // Increased default as 100/min is low for tests
        _rateLimitIpWindowSeconds = 60;
        _rateLimitBlobLimit = 50;
        _rateLimitBlobWindowSeconds = 3600;

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
        _nodeinfoSoftwareName = @"atprotopds";
        _nodeinfoSoftwareVersion = @"1.0.0";
        _nodeinfoRepositoryURL = @"https://github.com/jvalinsky/NSPds";
        _nodeinfoHomepageURL = @"https://github.com/jvalinsky/NSPds";
        _nodeinfoOpenRegistrations = YES;
        
        // Apply environment overrides and empty config defaults
        [self applyConfig:_config];
    }
    return self;
}

- (BOOL)loadFromPath:(NSString *)path error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSConfigErrorDomain
                                         code:PDSConfigErrorFileNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Config file not found: %@", path]}];
        }
        return NO;
    }

    NSError *readError = nil;
#if defined(__APPLE__)
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&readError];
#else
    NSData *data = [NSData dataWithContentsOfFile:path];
    readError = nil; // GNUstep doesn't support error parameter
#endif
    if (!data) {
        if (error) {
            *error = [NSError errorWithDomain:PDSConfigErrorDomain
                                         code:PDSConfigErrorFileNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to read config file: %@", readError.localizedDescription]}];
        }
        return NO;
    }

    NSError *parseError = nil;
    NSDictionary *yamlConfig = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
    if (!yamlConfig && parseError) {
        if (error) {
            *error = [NSError errorWithDomain:PDSConfigErrorDomain
                                         code:PDSConfigErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to parse config file: %@", parseError.localizedDescription]}];
        }
        return NO;
    }

    _config = [yamlConfig copy] ?: @{};
    [self applyConfig:_config];
    return YES;
}

- (void)applyConfig:(NSDictionary *)config {
    NSDictionary *server = config[@"server"];
    if (server) {
        if (server[@"host"]) _serverHost = [self resolveEnvOverrideForKey:@"PDS_HOST" default:server[@"host"]];
        if (server[@"port"]) _serverPort = [server[@"port"] unsignedIntegerValue];
        if (server[@"data_dir"]) _dataDirectory = [self resolveEnvOverrideForKey:@"PDS_DATA_DIR" default:server[@"data_dir"]];
    }

    NSDictionary *plc = config[@"plc"];
    if (plc) {
        if (plc[@"url"]) _plcURL = [self resolveEnvOverrideForKey:@"PDS_PLC_URL" default:plc[@"url"]];
        if (plc[@"retry_count"]) _plcRetryCount = [plc[@"retry_count"] unsignedIntegerValue];
        if (plc[@"retry_delay_ms"]) _plcRetryDelayMs = [plc[@"retry_delay_ms"] unsignedIntegerValue];
    }

    NSDictionary *debug = config[@"debug"];
    if (debug) {
        if (debug[@"skip_plc_operations"]) _debugSkipPlcOperations = [self boolFromEnv:@"PDS_DEBUG_SKIP_PLC" default:[debug[@"skip_plc_operations"] boolValue]];
        if (debug[@"verbose_logging"]) _debugVerboseLogging = [self boolFromEnv:@"PDS_DEBUG_VERBOSE" default:[debug[@"verbose_logging"] boolValue]];
        if (debug[@"in_memory_databases"]) _debugInMemoryDatabases = [self boolFromEnv:@"PDS_DEBUG_IN_MEMORY" default:[debug[@"in_memory_databases"] boolValue]];
        if (debug[@"reset_on_startup"]) _debugResetOnStartup = [self boolFromEnv:@"PDS_DEBUG_RESET" default:[debug[@"reset_on_startup"] boolValue]];
        if (debug[@"use_new_repository"]) _useNewRepositoryImplementation = [self boolFromEnv:@"PDS_USE_NEW_REPO" default:[debug[@"use_new_repository"] boolValue]];
    }

    NSDictionary *database = config[@"database"];
    if (database) {
        if (database[@"user_pool_max_size"]) _userDatabasePoolMaxSize = [database[@"user_pool_max_size"] unsignedIntegerValue];
        if (database[@"service_pool_max_size"]) _serviceDatabasePoolMaxSize = [database[@"service_pool_max_size"] unsignedIntegerValue];
        if (database[@"did_cache_pool_max_size"]) _didCachePoolMaxSize = [database[@"did_cache_pool_max_size"] unsignedIntegerValue];
        if (database[@"sequencer_pool_max_size"]) _sequencerPoolMaxSize = [database[@"sequencer_pool_max_size"] unsignedIntegerValue];
    }

    NSDictionary *session = config[@"session"];
    if (session) {
        if (session[@"access_token_ttl_seconds"]) _accessTokenTtlSeconds = [session[@"access_token_ttl_seconds"] unsignedIntegerValue];
        if (session[@"refresh_token_ttl_seconds"]) _refreshTokenTtlSeconds = [session[@"refresh_token_ttl_seconds"] unsignedIntegerValue];
        if (session[@"invite_code_required"]) _inviteCodeRequired = [session[@"invite_code_required"] boolValue];
    }

    NSDictionary *rateLimit = config[@"rate_limit"];
    if (rateLimit) {
        if (rateLimit[@"enabled"]) _rateLimitEnabled = [rateLimit[@"enabled"] boolValue];
        if (rateLimit[@"requests_per_minute"]) _rateLimitRequestsPerMinute = [rateLimit[@"requests_per_minute"] unsignedIntegerValue];
        if (rateLimit[@"burst_size"]) _rateLimitBurstSize = [rateLimit[@"burst_size"] unsignedIntegerValue];
        // Load granular limits from config map if present, else fallback check
        if (rateLimit[@"did_limit"]) _rateLimitDidLimit = [rateLimit[@"did_limit"] unsignedIntegerValue];
        if (rateLimit[@"did_window"]) _rateLimitDidWindowSeconds = [rateLimit[@"did_window"] doubleValue];
        if (rateLimit[@"ip_limit"]) _rateLimitIpLimit = [rateLimit[@"ip_limit"] unsignedIntegerValue];
        if (rateLimit[@"ip_window"]) _rateLimitIpWindowSeconds = [rateLimit[@"ip_window"] doubleValue];
        if (rateLimit[@"blob_limit"]) _rateLimitBlobLimit = [rateLimit[@"blob_limit"] unsignedIntegerValue];
        if (rateLimit[@"blob_window"]) _rateLimitBlobWindowSeconds = [rateLimit[@"blob_window"] doubleValue];
    }
    
    // Environment variables override everything
    if ([self envVarExists:@"PDS_RATELIMIT_ENABLED"]) _rateLimitEnabled = [self boolFromEnv:@"PDS_RATELIMIT_ENABLED" default:_rateLimitEnabled];
    
    NSString *envDidLimit = [self resolveEnvOverrideForKey:@"PDS_RATELIMIT_DID_LIMIT" default:nil];
    if (envDidLimit) _rateLimitDidLimit = [envDidLimit integerValue];
    
    NSString *envDidWindow = [self resolveEnvOverrideForKey:@"PDS_RATELIMIT_DID_WINDOW" default:nil];
    if (envDidWindow) _rateLimitDidWindowSeconds = [envDidWindow doubleValue];

    NSString *envIpLimit = [self resolveEnvOverrideForKey:@"PDS_RATELIMIT_IP_LIMIT" default:nil];
    if (envIpLimit) _rateLimitIpLimit = [envIpLimit integerValue];

    NSString *envIpWindow = [self resolveEnvOverrideForKey:@"PDS_RATELIMIT_IP_WINDOW" default:nil];
    if (envIpWindow) _rateLimitIpWindowSeconds = [envIpWindow doubleValue];

    NSString *envBlobLimit = [self resolveEnvOverrideForKey:@"PDS_RATELIMIT_BLOB_LIMIT" default:nil];
    if (envBlobLimit) _rateLimitBlobLimit = [envBlobLimit integerValue];

    NSString *envBlobWindow = [self resolveEnvOverrideForKey:@"PDS_RATELIMIT_BLOB_WINDOW" default:nil];
    if (envBlobWindow) _rateLimitBlobWindowSeconds = [envBlobWindow doubleValue];

    NSDictionary *sslPinning = config[@"ssl_pinning"];
    if (sslPinning) {
        if (sslPinning[@"enabled"]) _sslPinningEnabled = [sslPinning[@"enabled"] boolValue];
    }

    NSDictionary *logging = config[@"logging"];
    if (logging) {
        if (logging[@"file_path"]) {
            _logFilePath = [self resolveEnvOverrideForKey:@"PDS_LOG_FILE" default:logging[@"file_path"]];
        }

        if (logging[@"level"]) {
            NSString *level = [[self resolveEnvOverrideForKey:@"PDS_LOG_LEVEL" default:logging[@"level"]] lowercaseString];
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
            NSString *format = [[self resolveEnvOverrideForKey:@"PDS_LOG_FORMAT" default:logging[@"format"]] lowercaseString];
            if ([format isEqualToString:@"json"]) {
                _logFormat = PDSLogFormatJSON;
            } else if ([format isEqualToString:@"both"]) {
                _logFormat = PDSLogFormatBoth;
            } else {
                _logFormat = PDSLogFormatText;
            }
        }

        if (logging[@"max_file_size_mb"]) {
            NSString *envValue = [[NSProcessInfo processInfo] environment][@"PDS_LOG_MAX_SIZE_MB"];
            NSUInteger sizeMB = envValue ? [envValue integerValue] : [logging[@"max_file_size_mb"] unsignedIntegerValue];
            _maxLogFileSize = sizeMB * 1024 * 1024; // Convert MB to bytes
        }

        if (logging[@"max_files"]) {
            NSString *envValue = [[NSProcessInfo processInfo] environment][@"PDS_LOG_MAX_FILES"];
            _maxLogFiles = envValue ? [envValue integerValue] : [logging[@"max_files"] unsignedIntegerValue];
        }

        if (logging[@"async"]) {
            _asyncLogging = [self boolFromEnv:@"PDS_LOG_ASYNC" default:[logging[@"async"] boolValue]];
        }

        if (logging[@"components"]) {
            NSString *envValue = [[NSProcessInfo processInfo] environment][@"PDS_LOG_COMPONENTS"];
            if (envValue) {
                _enabledComponents = [envValue componentsSeparatedByString:@","];
            } else {
                _enabledComponents = logging[@"components"];
            }
        }
    }

    NSDictionary *nodeinfo = config[@"nodeinfo"];
    if (nodeinfo) {
        if (nodeinfo[@"enabled"]) _nodeinfoEnabled = [self boolFromEnv:@"PDS_NODEINFO_ENABLED" default:[nodeinfo[@"enabled"] boolValue]];
        if (nodeinfo[@"software_name"]) _nodeinfoSoftwareName = [self resolveEnvOverrideForKey:@"PDS_NODEINFO_SOFTWARE_NAME" default:nodeinfo[@"software_name"]];
        if (nodeinfo[@"software_version"]) _nodeinfoSoftwareVersion = [self resolveEnvOverrideForKey:@"PDS_NODEINFO_SOFTWARE_VERSION" default:nodeinfo[@"software_version"]];
        if (nodeinfo[@"repository_url"]) _nodeinfoRepositoryURL = [self resolveEnvOverrideForKey:@"PDS_NODEINFO_REPOSITORY_URL" default:nodeinfo[@"repository_url"]];
        if (nodeinfo[@"homepage_url"]) _nodeinfoHomepageURL = [self resolveEnvOverrideForKey:@"PDS_NODEINFO_HOMEPAGE_URL" default:nodeinfo[@"homepage_url"]];
        if (nodeinfo[@"open_registrations"]) _nodeinfoOpenRegistrations = [self boolFromEnv:@"PDS_NODEINFO_OPEN_REGISTRATIONS" default:[nodeinfo[@"open_registrations"] boolValue]];
    }

    // Also check environment variables if no config file logging section
    if (!logging) {
        NSString *logFile = [[NSProcessInfo processInfo] environment][@"PDS_LOG_FILE"];
        if (logFile) _logFilePath = logFile;

        NSString *logLevel = [[[NSProcessInfo processInfo] environment][@"PDS_LOG_LEVEL"] lowercaseString];
        if (logLevel) {
            if ([logLevel isEqualToString:@"debug"]) _logLevel = PDSLogLevelDebug;
            else if ([logLevel isEqualToString:@"info"]) _logLevel = PDSLogLevelInfo;
            else if ([logLevel isEqualToString:@"warn"]) _logLevel = PDSLogLevelWarn;
            else if ([logLevel isEqualToString:@"error"]) _logLevel = PDSLogLevelError;
        }

        NSString *logFormat = [[[NSProcessInfo processInfo] environment][@"PDS_LOG_FORMAT"] lowercaseString];
        if (logFormat) {
            if ([logFormat isEqualToString:@"json"]) _logFormat = PDSLogFormatJSON;
            else if ([logFormat isEqualToString:@"both"]) _logFormat = PDSLogFormatBoth;
            else _logFormat = PDSLogFormatText;
        }
    }
}

- (BOOL)envVarExists:(NSString *)envKey {
    return [self resolveEnvOverrideForKey:envKey default:nil] != nil;
}

- (NSString *)resolveEnvOverrideForKey:(NSString *)envKey default:(NSString *)defaultValue {
    NSString *envValue = [[NSProcessInfo processInfo] environment][envKey];
    return envValue ?: defaultValue;
}

- (BOOL)boolFromEnv:(NSString *)envKey default:(BOOL)defaultValue {
    NSString *envValue = [[NSProcessInfo processInfo] environment][envKey];
    if (!envValue) return defaultValue;
    return [@"true" isEqualToString:envValue.lowercaseString] ||
           [@"1" isEqualToString:envValue];
}

- (nullable NSString *)stringForKey:(NSString *)key {
    NSArray *components = [key componentsSeparatedByString:@"."];
    id current = _config;
    for (NSString *component in components) {
        if (![current isKindOfClass:[NSDictionary class]]) return nil;
        current = ((NSDictionary *)current)[component];
        if (!current) return nil;
    }
    return [current isKindOfClass:[NSString class]] ? (NSString *)current : nil;
}

- (NSInteger)integerForKey:(NSString *)key {
    NSString *value = [self stringForKey:key];
    return value ? [value integerValue] : 0;
}

- (BOOL)boolForKey:(NSString *)key {
    NSString *value = [self stringForKey:key];
    if (!value) return NO;
    return [@"true" isEqualToString:value.lowercaseString] ||
           [@"1" isEqualToString:value];
}

@end
