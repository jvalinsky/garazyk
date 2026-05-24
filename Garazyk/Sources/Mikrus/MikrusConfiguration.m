// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Mikrus/MikrusConfiguration.h"
#import "Shared/GZConfigurationParsing.h"

@implementation MikrusConfiguration

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _relayURLs = @[@"wss://bsky.network"];
    _dataDirectory = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Mikrus"];
    _httpPort = 3210;
    _cursorCheckpointIntervalMs = 5000;
    _ingestEnabled = YES;
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
            [GZConfigurationProperty propertyWithTargetKey:@"relayURLs" jsonKeys:@[@"relay_urls", @"relays"] envVar:@"MIKRUS_RELAY_URLS" type:GZConfigurationPropertyTypeStringArray],
            [GZConfigurationProperty propertyWithTargetKey:@"dataDirectory" jsonKeys:@[@"data_directory", @"data_dir"] envVar:@"MIKRUS_DATA_DIR" type:GZConfigurationPropertyTypeString],
            [GZConfigurationProperty propertyWithTargetKey:@"httpPort" jsonKeys:@[@"http.port", @"port"] envVar:@"MIKRUS_HTTP_PORT" type:GZConfigurationPropertyTypeInteger],
            [GZConfigurationProperty propertyWithTargetKey:@"cursorCheckpointIntervalMs" jsonKeys:@[@"cursor.checkpoint_interval_ms", @"checkpoint_interval_ms"] envVar:@"MIKRUS_CURSOR_CHECKPOINT_MS" type:GZConfigurationPropertyTypeInteger],
            [GZConfigurationProperty propertyWithTargetKey:@"ingestEnabled" jsonKeys:@[@"ingest.enabled", @"ingest_enabled"] envVar:@"MIKRUS_INGEST_ENABLED" type:GZConfigurationPropertyTypeBoolean],
            [GZConfigurationProperty propertyWithTargetKey:@"rateLimitEnabled" jsonKeys:@[@"rate_limit.enabled", @"rate_limit_enabled"] envVar:@"MIKRUS_RATELIMIT_ENABLED" type:GZConfigurationPropertyTypeBoolean],
            [GZConfigurationProperty propertyWithTargetKey:@"rateLimitIpLimit" jsonKeys:@[@"rate_limit.ip_limit", @"rate_limit_ip_limit"] envVar:@"MIKRUS_RATELIMIT_IP_LIMIT" type:GZConfigurationPropertyTypeInteger],
            [GZConfigurationProperty propertyWithTargetKey:@"rateLimitIpWindowSeconds" jsonKeys:@[@"rate_limit.ip_window", @"rate_limit_ip_window"] envVar:@"MIKRUS_RATELIMIT_IP_WINDOW" type:GZConfigurationPropertyTypeDouble]
        ]];
    });
    return parser;
}

+ (instancetype)configurationFromEnvironment {
    MikrusConfiguration *config = [[self alloc] init];
    [[self sharedParser] applyEnvironmentVariables:[[NSProcessInfo processInfo] environment] toTarget:config];
    return config;
}

- (void)loadFromDictionary:(NSDictionary *)dictionary {
    [[[self class] sharedParser] applyDictionary:dictionary toTarget:self];
}

- (BOOL)validate:(NSError **)error {
    if (self.dataDirectory.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"MikrusConfiguration"
                                                code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"data_directory must be set"}];
        return NO;
    }
    if (self.httpPort > UINT16_MAX) {
        if (error) *error = [NSError errorWithDomain:@"MikrusConfiguration"
                                                code:2
                                            userInfo:@{NSLocalizedDescriptionKey: @"http port must fit in uint16; 0 requests an ephemeral port"}];
        return NO;
    }
    if (self.ingestEnabled && self.relayURLs.count == 0) {
        if (error) *error = [NSError errorWithDomain:@"MikrusConfiguration"
                                                code:3
                                            userInfo:@{NSLocalizedDescriptionKey: @"relay_urls must not be empty when ingest is enabled"}];
        return NO;
    }
    return YES;
}

+ (NSArray<NSString *> *)splitCSV:(NSString *)value {
    NSMutableArray<NSString *> *items = [NSMutableArray array];
    for (NSString *part in [value componentsSeparatedByString:@","]) {
        NSString *trimmed = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) [items addObject:trimmed];
    }
    return [items copy];
}

@end
