#import "PDSConfiguration.h"

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

        _userDatabasePoolMaxSize = 100;
        _serviceDatabasePoolMaxSize = 10;
        _didCachePoolMaxSize = 1000;
        _sequencerPoolMaxSize = 100;

        _accessTokenTtlSeconds = 3600;
        _refreshTokenTtlSeconds = 604800;
        _inviteCodeRequired = NO;

        _rateLimitEnabled = YES;
        _rateLimitRequestsPerMinute = 1000;
        _rateLimitBurstSize = 100;

        _sslPinningEnabled = YES;
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
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&readError];
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
    }

    NSDictionary *sslPinning = config[@"ssl_pinning"];
    if (sslPinning) {
        if (sslPinning[@"enabled"]) _sslPinningEnabled = [sslPinning[@"enabled"] boolValue];
    }
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
    return [current isKindOfClass:[NSString class]] ? current : nil;
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
