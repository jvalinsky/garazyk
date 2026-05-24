// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AppViewConfiguration.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/Config/AppViewConfiguration.h"
#import "Shared/GZConfigurationParsing.h"

@interface AppViewConfiguration ()
@property (nonatomic, copy) NSString *modeString;
@end

@implementation AppViewConfiguration

- (void)setModeString:(NSString *)modeString {
    if ([modeString isEqualToString:@"proxy"]) self.mode = AppViewModeProxy;
    else if ([modeString isEqualToString:@"standalone"]) self.mode = AppViewModeStandalone;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    [self _applyDefaults];
    return self;
}

- (void)_applyDefaults {
    _mode                      = AppViewModeStandalone;
    _relayURLs                 = @[];
    _dataDirectory             = [NSHomeDirectory() stringByAppendingPathComponent:
                                  @"Library/Application Support/AppView"];
    _httpPort                  = 3200;
    _masterSecret              = nil;
    _adminSecret               = nil;
    _cursorCheckpointIntervalMs = 5000;
    _backfillEnabled           = YES;
    _backfillGlobalWorkers     = 8;
    _backfillPerHostWorkers    = 2;
    _partialEnabled            = NO;
    _partialSeedDIDs           = @[];
    _partialAllowlist          = @[];
    _partialTTLHours           = 168;
    _partialProxyFallback      = NO;
    _partialProxyFallbackURL   = nil;
    _videoServiceURL           = nil;
    _plcURL                  = @"https://plc.directory";
}

// ---------------------------------------------------------------------------

+ (instancetype)defaultConfiguration {
    return [[self alloc] init];
}

+ (GZConfigurationParsing *)sharedParser {
    static GZConfigurationParsing *parser = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        parser = [[GZConfigurationParsing alloc] initWithProperties:@[
            [GZConfigurationProperty propertyWithTargetKey:@"modeString" jsonKeys:@[@"mode"] envVar:@"APPVIEW_MODE" type:GZConfigurationPropertyTypeString],
            [GZConfigurationProperty propertyWithTargetKey:@"relayURLs" jsonKeys:@[@"relay_urls"] envVar:@"APPVIEW_RELAY_URLS" type:GZConfigurationPropertyTypeStringArray],
            [GZConfigurationProperty propertyWithTargetKey:@"dataDirectory" jsonKeys:@[@"data_directory", @"data_dir"] envVar:@"APPVIEW_DATA_DIR" type:GZConfigurationPropertyTypeString],
            [GZConfigurationProperty propertyWithTargetKey:@"httpPort" jsonKeys:@[@"http.port", @"port", @"http_port"] envVar:@"APPVIEW_HTTP_PORT" type:GZConfigurationPropertyTypeInteger],
            [GZConfigurationProperty propertyWithTargetKey:@"adminSecret" jsonKeys:@[@"admin_secret"] envVar:@"APPVIEW_ADMIN_SECRET" type:GZConfigurationPropertyTypeString],
            [GZConfigurationProperty propertyWithTargetKey:@"masterSecret" jsonKeys:@[@"master_secret"] envVar:@"APPVIEW_MASTER_SECRET" type:GZConfigurationPropertyTypeString],
            [GZConfigurationProperty propertyWithTargetKey:@"cursorCheckpointIntervalMs" jsonKeys:@[@"cursor.checkpoint_interval_ms", @"cursor_checkpoint_interval_ms"] envVar:@"APPVIEW_CURSOR_CHECKPOINT_MS" type:GZConfigurationPropertyTypeInteger],
            [GZConfigurationProperty propertyWithTargetKey:@"plcURL" jsonKeys:@[@"plc.url", @"plc_url"] envVar:@"APPVIEW_PLC_URL" type:GZConfigurationPropertyTypeString],
            [GZConfigurationProperty propertyWithTargetKey:@"backfillEnabled" jsonKeys:@[@"backfill.enabled", @"backfill_enabled"] envVar:@"APPVIEW_BACKFILL_ENABLED" type:GZConfigurationPropertyTypeBoolean],
            [GZConfigurationProperty propertyWithTargetKey:@"backfillGlobalWorkers" jsonKeys:@[@"backfill.global_workers", @"backfill_global_workers"] envVar:@"APPVIEW_BACKFILL_GLOBAL_WORKERS" type:GZConfigurationPropertyTypeInteger],
            [GZConfigurationProperty propertyWithTargetKey:@"backfillPerHostWorkers" jsonKeys:@[@"backfill.per_host_workers", @"backfill_per_host_workers"] envVar:@"APPVIEW_BACKFILL_PER_HOST_WORKERS" type:GZConfigurationPropertyTypeInteger],
            [GZConfigurationProperty propertyWithTargetKey:@"partialEnabled" jsonKeys:@[@"partial.enabled", @"partial_enabled"] envVar:@"APPVIEW_PARTIAL_ENABLED" type:GZConfigurationPropertyTypeBoolean],
            [GZConfigurationProperty propertyWithTargetKey:@"partialSeedDIDs" jsonKeys:@[@"partial.seed_dids", @"partial_seed_dids"] envVar:@"APPVIEW_PARTIAL_SEED_DIDS" type:GZConfigurationPropertyTypeStringArray],
            [GZConfigurationProperty propertyWithTargetKey:@"partialAllowlist" jsonKeys:@[@"partial.allowlist", @"partial_allowlist"] envVar:@"APPVIEW_PARTIAL_ALLOWLIST" type:GZConfigurationPropertyTypeStringArray],
            [GZConfigurationProperty propertyWithTargetKey:@"partialTTLHours" jsonKeys:@[@"partial.ttl_hours", @"partial_ttl_hours"] envVar:@"APPVIEW_PARTIAL_TTL_HOURS" type:GZConfigurationPropertyTypeInteger],
            [GZConfigurationProperty propertyWithTargetKey:@"partialProxyFallback" jsonKeys:@[@"partial.proxy_fallback", @"partial_proxy_fallback"] envVar:@"APPVIEW_PARTIAL_PROXY_FALLBACK" type:GZConfigurationPropertyTypeBoolean],
            [GZConfigurationProperty propertyWithTargetKey:@"partialProxyFallbackURL" jsonKeys:@[@"partial.proxy_fallback_url", @"proxy_fallback_url"] envVar:@"APPVIEW_PARTIAL_PROXY_FALLBACK_URL" type:GZConfigurationPropertyTypeString],
            [GZConfigurationProperty propertyWithTargetKey:@"videoServiceURL" jsonKeys:@[@"video_service_url"] envVar:@"APPVIEW_VIDEO_SERVICE_URL" type:GZConfigurationPropertyTypeString]
        ]];
    });
    return parser;
}

+ (instancetype)configurationFromEnvironment {
    AppViewConfiguration *config = [[self alloc] init];
    [[self sharedParser] applyEnvironmentVariables:[[NSProcessInfo processInfo] environment] toTarget:config];
    if (config.partialProxyFallbackURL.length == 0) {
        NSString *fallback = [[NSProcessInfo processInfo] environment][@"APPVIEW_PROXY_FALLBACK_URL"];
        if (fallback.length > 0) config.partialProxyFallbackURL = fallback;
    }
    return config;
}

- (void)loadFromDictionary:(NSDictionary *)dict {
    [[[self class] sharedParser] applyDictionary:dict toTarget:self];
}

- (BOOL)validate:(NSError **)error {
    if (_relayURLs.count == 0) {
        if (error) *error = [NSError errorWithDomain:@"AppViewConfiguration"
                                                code:1
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           @"appview.relay_urls must not be empty"}];
        return NO;
    }
    if (_dataDirectory.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"AppViewConfiguration"
                                                code:2
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           @"appview.data_directory must be set"}];
        return NO;
    }
    if (_partialProxyFallback && _partialProxyFallbackURL.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"AppViewConfiguration"
                                                code:3
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           @"partial.proxy_fallback requires partial.proxy_fallback_url"}];
        return NO;
    }
    return YES;
}

@end
