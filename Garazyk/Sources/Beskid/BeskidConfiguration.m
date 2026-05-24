// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Beskid/BeskidConfiguration.h"
#import "Shared/GZConfigurationParsing.h"

@implementation BeskidConfiguration

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _dataDirectory = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Beskid"];
    _httpPort = 8085;
    _domain = @"slingshot.microcosm.blue";
    _cacheRecordTtlSeconds = 3600;
    _cacheIdentityTtlSeconds = 86400;
    _rateLimitEnabled = YES;
    _rateLimitIpLimit = 200;
    _rateLimitIpWindowSeconds = 60;
    return self;
}

+ (instancetype)defaultConfiguration {
    return [[self alloc] init];
}

+ (GZConfigurationParsing *)sharedParser {
    static GZConfigurationParsing *parser = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        parser = [[GZConfigurationParsing alloc] initWithProperties:@[
            [GZConfigurationProperty propertyWithTargetKey:@"dataDirectory" jsonKeys:@[@"data_directory", @"data_dir"] envVar:@"BESKID_DATA_DIR" type:GZConfigurationPropertyTypeString],
            [GZConfigurationProperty propertyWithTargetKey:@"httpPort" jsonKeys:@[@"http.port", @"port"] envVar:@"BESKID_HTTP_PORT" type:GZConfigurationPropertyTypeInteger],
            [GZConfigurationProperty propertyWithTargetKey:@"domain" jsonKeys:@[@"domain"] envVar:@"BESKID_DOMAIN" type:GZConfigurationPropertyTypeString],
            [GZConfigurationProperty propertyWithTargetKey:@"cacheRecordTtlSeconds" jsonKeys:@[@"cache_record_ttl", @"cache_record_ttl_seconds"] envVar:@"BESKID_CACHE_RECORD_TTL" type:GZConfigurationPropertyTypeDouble],
            [GZConfigurationProperty propertyWithTargetKey:@"cacheIdentityTtlSeconds" jsonKeys:@[@"cache_identity_ttl", @"cache_identity_ttl_seconds"] envVar:@"BESKID_CACHE_IDENTITY_TTL" type:GZConfigurationPropertyTypeDouble],
            [GZConfigurationProperty propertyWithTargetKey:@"rateLimitEnabled" jsonKeys:@[@"rate_limit.enabled", @"rate_limit_enabled"] envVar:@"BESKID_RATELIMIT_ENABLED" type:GZConfigurationPropertyTypeBoolean],
            [GZConfigurationProperty propertyWithTargetKey:@"rateLimitIpLimit" jsonKeys:@[@"rate_limit.ip_limit", @"rate_limit_ip_limit"] envVar:@"BESKID_RATELIMIT_IP_LIMIT" type:GZConfigurationPropertyTypeInteger],
            [GZConfigurationProperty propertyWithTargetKey:@"rateLimitIpWindowSeconds" jsonKeys:@[@"rate_limit.ip_window", @"rate_limit_ip_window"] envVar:@"BESKID_RATELIMIT_IP_WINDOW" type:GZConfigurationPropertyTypeDouble]
        ]];
    });
    return parser;
}

+ (instancetype)configurationFromEnvironment {
    BeskidConfiguration *config = [[self alloc] init];
    [[self sharedParser] applyEnvironmentVariables:[[NSProcessInfo processInfo] environment] toTarget:config];
    return config;
}

- (void)loadFromDictionary:(NSDictionary *)dictionary {
    [[[self class] sharedParser] applyDictionary:dictionary toTarget:self];
}

- (BOOL)validate:(NSError **)error {
    if (self.dataDirectory.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"BeskidConfiguration"
                                                code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"data_directory must be set"}];
        return NO;
    }
    if (self.httpPort > UINT16_MAX) {
        if (error) *error = [NSError errorWithDomain:@"BeskidConfiguration"
                                                code:2
                                            userInfo:@{NSLocalizedDescriptionKey: @"http port must fit in uint16; 0 requests an ephemeral port"}];
        return NO;
    }
    return YES;
}

@end
