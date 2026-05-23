// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Beskid/BeskidConfiguration.h"

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

+ (instancetype)configurationFromEnvironment {
    BeskidConfiguration *config = [[self alloc] init];
    NSDictionary *env = [[NSProcessInfo processInfo] environment];

    NSString *dataDir = env[@"BESKID_DATA_DIR"];
    if (dataDir.length > 0) config.dataDirectory = dataDir;

    NSString *port = env[@"BESKID_HTTP_PORT"];
    if (port.integerValue > 0) config.httpPort = (NSUInteger)port.integerValue;

    NSString *domain = env[@"BESKID_DOMAIN"];
    if (domain.length > 0) config.domain = domain;

    NSString *recTtl = env[@"BESKID_CACHE_RECORD_TTL"];
    if (recTtl.doubleValue > 0) config.cacheRecordTtlSeconds = recTtl.doubleValue;

    NSString *idTtl = env[@"BESKID_CACHE_IDENTITY_TTL"];
    if (idTtl.doubleValue > 0) config.cacheIdentityTtlSeconds = idTtl.doubleValue;

    NSString *rlEnabled = env[@"BESKID_RATELIMIT_ENABLED"];
    if (rlEnabled.length > 0) config.rateLimitEnabled = [rlEnabled boolValue];

    NSString *rlIpLimit = env[@"BESKID_RATELIMIT_IP_LIMIT"];
    if (rlIpLimit.integerValue > 0) config.rateLimitIpLimit = rlIpLimit.integerValue;

    NSString *rlIpWindow = env[@"BESKID_RATELIMIT_IP_WINDOW"];
    if (rlIpWindow.doubleValue > 0) config.rateLimitIpWindowSeconds = rlIpWindow.doubleValue;

    return config;
}

- (void)loadFromDictionary:(NSDictionary *)dictionary {
    NSString *dataDir = dictionary[@"data_directory"] ?: dictionary[@"data_dir"];
    if (dataDir.length > 0) self.dataDirectory = dataDir;

    id port = dictionary[@"http.port"] ?: dictionary[@"port"];
    if ([port isKindOfClass:[NSNumber class]]) {
        NSInteger value = [port integerValue];
        if (value >= 0 && value <= UINT16_MAX) self.httpPort = (NSUInteger)value;
    } else if ([port isKindOfClass:[NSString class]] && [(NSString *)port length] > 0) {
        NSInteger value = -1;
        NSScanner *scanner = [NSScanner scannerWithString:(NSString *)port];
        scanner.charactersToBeSkipped = nil;
        if ([scanner scanInteger:&value] && scanner.isAtEnd && value >= 0 && value <= UINT16_MAX) {
            self.httpPort = (NSUInteger)value;
        }
    }

    NSString *domain = dictionary[@"domain"];
    if (domain.length > 0) self.domain = domain;

    id recTtl = dictionary[@"cache_record_ttl"] ?: dictionary[@"cache_record_ttl_seconds"];
    if ([recTtl respondsToSelector:@selector(doubleValue)] && [recTtl doubleValue] > 0) {
        self.cacheRecordTtlSeconds = [recTtl doubleValue];
    }

    id idTtl = dictionary[@"cache_identity_ttl"] ?: dictionary[@"cache_identity_ttl_seconds"];
    if ([idTtl respondsToSelector:@selector(doubleValue)] && [idTtl doubleValue] > 0) {
        self.cacheIdentityTtlSeconds = [idTtl doubleValue];
    }

    id rlEnabled = dictionary[@"rate_limit.enabled"] ?: dictionary[@"rate_limit_enabled"];
    if (rlEnabled) self.rateLimitEnabled = [rlEnabled boolValue];

    id rlIpLimit = dictionary[@"rate_limit.ip_limit"] ?: dictionary[@"rate_limit_ip_limit"];
    if ([rlIpLimit respondsToSelector:@selector(integerValue)] && [rlIpLimit integerValue] > 0) {
        self.rateLimitIpLimit = [rlIpLimit integerValue];
    }

    id rlIpWindow = dictionary[@"rate_limit.ip_window"] ?: dictionary[@"rate_limit_ip_window"];
    if ([rlIpWindow respondsToSelector:@selector(doubleValue)] && [rlIpWindow doubleValue] > 0) {
        self.rateLimitIpWindowSeconds = [rlIpWindow doubleValue];
    }
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
