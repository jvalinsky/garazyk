#import "Sync/Relay/RelayConfiguration.h"

NSString * const RelayConfigurationErrorDomain = @"com.atproto.relay.configuration";

@interface RelayConfiguration ()

@property (nonatomic, copy, readwrite) NSArray<NSString *> *upstreamURLs;
@property (nonatomic, assign, readwrite) uint16_t downstreamPort;
@property (nonatomic, assign, readwrite) NSUInteger retentionHours;
@property (nonatomic, assign, readwrite) RelayValidationMode validationMode;
@property (nonatomic, assign, readwrite) NSUInteger maxDownstreamConnections;
@property (nonatomic, copy, readwrite, nullable) NSString *dataDirectory;
@property (nonatomic, copy, readwrite, nullable) NSString *adminPassword;
@property (nonatomic, assign, readwrite) BOOL logLevelDebug;

@end

@implementation RelayConfiguration

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

+ (instancetype)configuration {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (instancetype)initWithUpstreamURLs:(NSArray<NSString *> *)upstreamURLs
                    downstreamPort:(uint16_t)port
                     retentionHours:(NSUInteger)hours
                    validationMode:(RelayValidationMode)mode {
    self = [super init];
    if (self) {
        _upstreamURLs = [upstreamURLs copy];
        _downstreamPort = port > 0 ? port : 2584;
        _retentionHours = hours > 0 ? hours : 72;
        _validationMode = mode;
        _maxDownstreamConnections = 1000;
        _dataDirectory = nil;
        _adminPassword = nil;
        _logLevelDebug = NO;
    }
    return self;
}

+ (nullable instancetype)configurationFromFile:(NSString *)path error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) {
        if (error) {
            *error = [NSError errorWithDomain:RelayConfigurationErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to read config file"}];
        }
        return nil;
    }

    NSError *jsonError = nil;
    NSDictionary *config = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (!config || ![config isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:RelayConfigurationErrorDomain
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid JSON config"}];
        }
        return nil;
    }

    NSArray<NSString *> *upstreams = config[@"upstream_urls"];
    if (!upstreams || ![upstreams isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [NSError errorWithDomain:RelayConfigurationErrorDomain
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing upstream_urls"}];
        }
        return nil;
    }

    uint16_t port = [config[@"downstream_port"] unsignedShortValue];
    NSUInteger hours = [config[@"retention_hours"] unsignedIntegerValue];
    
    NSString *validationModeStr = config[@"validation_mode"];
    RelayValidationMode mode = RelayValidationModeLogOnly;
    if ([validationModeStr isEqualToString:@"lenient"]) {
        mode = RelayValidationModeLenient;
    } else if ([validationModeStr isEqualToString:@"strict"]) {
        mode = RelayValidationModeStrict;
    }

    RelayConfiguration *result = [[RelayConfiguration alloc] initWithUpstreamURLs:upstreams
                                                                     downstreamPort:port
                                                                      retentionHours:hours
                                                                    validationMode:mode];
    result.dataDirectory = config[@"data_directory"];
    result.adminPassword = config[@"admin_password"];
    result.maxDownstreamConnections = [config[@"max_connections"] unsignedIntegerValue] ?: 1000;
    result.logLevelDebug = [config[@"debug"] boolValue];

    return result;
}

+ (nullable instancetype)configurationFromEnvironment {
    NSArray<NSString *> *urls = nil;
    
    NSString *upstreamEnv = [[NSProcessInfo processInfo] environment][@"RELAY_UPSTREAM_URLS"];
    if (upstreamEnv.length > 0) {
        urls = [upstreamEnv componentsSeparatedByString:@","];
    }
    
    if (urls.count == 0) {
        return nil;
    }
    
    uint16_t port = (uint16_t)[[[NSProcessInfo processInfo] environment][@"RELAY_DOWNSTREAM_PORT"] integerValue];
    NSUInteger hours = (NSUInteger)[[[NSProcessInfo processInfo] environment][@"RELAY_RETENTION_HOURS"] integerValue];
    
    NSString *validationModeEnv = [[NSProcessInfo processInfo] environment][@"RELAY_VALIDATION_MODE"];
    RelayValidationMode mode = RelayValidationModeLogOnly;
    if ([validationModeEnv isEqualToString:@"lenient"]) {
        mode = RelayValidationModeLenient;
    } else if ([validationModeEnv isEqualToString:@"strict"]) {
        mode = RelayValidationModeStrict;
    }
    
    RelayConfiguration *result = [[RelayConfiguration alloc] initWithUpstreamURLs:urls
                                                                     downstreamPort:port
                                                                      retentionHours:hours
                                                                    validationMode:mode];
    result.dataDirectory = [[NSProcessInfo processInfo] environment][@"RELAY_DATA_DIR"];
    result.adminPassword = [[NSProcessInfo processInfo] environment][@"RELAY_ADMIN_PASSWORD"];
    result.logLevelDebug = [[[NSProcessInfo processInfo] environment][@"DEBUG"] boolValue];
    
    return result;
}

@end