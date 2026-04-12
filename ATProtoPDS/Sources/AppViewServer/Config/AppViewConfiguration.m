/*!
 @file AppViewConfiguration.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppViewServer/Config/AppViewConfiguration.h"

@implementation AppViewConfiguration

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    [self _applyDefaults];
    return self;
}

- (void)_applyDefaults {
    _mode                      = AppViewModeStandalone;
    _relayURLs                 = @[@"wss://bsky.network"];
    _dataDirectory             = [NSHomeDirectory() stringByAppendingPathComponent:
                                  @"Library/Application Support/AppView"];
    _httpPort                  = 3200;
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
}

// ---------------------------------------------------------------------------

+ (instancetype)defaultConfiguration {
    return [[self alloc] init];
}

+ (instancetype)configurationFromEnvironment {
    AppViewConfiguration *config = [[self alloc] init];

    // Mode
    NSString *modeStr = [NSProcessInfo.processInfo.environment objectForKey:@"APPVIEW_MODE"];
    if ([modeStr isEqualToString:@"proxy"])      config.mode = AppViewModeProxy;
    if ([modeStr isEqualToString:@"standalone"]) config.mode = AppViewModeStandalone;

    // Relay URLs
    NSString *relayEnv = [NSProcessInfo.processInfo.environment objectForKey:@"APPVIEW_RELAY_URLS"];
    if (relayEnv.length > 0) {
        config.relayURLs = [relayEnv componentsSeparatedByString:@","];
    }

    // Data dir
    NSString *dataDir = [NSProcessInfo.processInfo.environment objectForKey:@"APPVIEW_DATA_DIR"];
    if (dataDir.length > 0) config.dataDirectory = dataDir;

    // Port
    NSString *portStr = [NSProcessInfo.processInfo.environment objectForKey:@"APPVIEW_HTTP_PORT"];
    if (portStr.integerValue > 0) config.httpPort = (NSUInteger)portStr.integerValue;

    // Admin secret
    NSString *secret = [NSProcessInfo.processInfo.environment objectForKey:@"APPVIEW_ADMIN_SECRET"];
    if (secret.length > 0) config.adminSecret = secret;

    // Checkpoint interval
    NSString *checkpointMs = [NSProcessInfo.processInfo.environment objectForKey:@"APPVIEW_CURSOR_CHECKPOINT_MS"];
    if (checkpointMs.integerValue > 0) config.cursorCheckpointIntervalMs = (NSUInteger)checkpointMs.integerValue;

    // Backfill
    NSString *bfEnabled = [NSProcessInfo.processInfo.environment objectForKey:@"APPVIEW_BACKFILL_ENABLED"];
    if (bfEnabled) config.backfillEnabled = [bfEnabled boolValue];

    NSString *bfGlobal = [NSProcessInfo.processInfo.environment objectForKey:@"APPVIEW_BACKFILL_GLOBAL_WORKERS"];
    if (bfGlobal.integerValue > 0) config.backfillGlobalWorkers = (NSUInteger)bfGlobal.integerValue;

    NSString *bfHost = [NSProcessInfo.processInfo.environment objectForKey:@"APPVIEW_BACKFILL_PER_HOST_WORKERS"];
    if (bfHost.integerValue > 0) config.backfillPerHostWorkers = (NSUInteger)bfHost.integerValue;

    // Partial mode
    NSString *partialEnabled = [NSProcessInfo.processInfo.environment objectForKey:@"APPVIEW_PARTIAL_ENABLED"];
    if (partialEnabled) config.partialEnabled = [partialEnabled boolValue];

    NSString *seedDIDs = [NSProcessInfo.processInfo.environment objectForKey:@"APPVIEW_PARTIAL_SEED_DIDS"];
    if (seedDIDs.length > 0) config.partialSeedDIDs = [seedDIDs componentsSeparatedByString:@","];

    NSString *allowlist = [NSProcessInfo.processInfo.environment objectForKey:@"APPVIEW_PARTIAL_ALLOWLIST"];
    if (allowlist.length > 0) config.partialAllowlist = [allowlist componentsSeparatedByString:@","];

    NSString *ttl = [NSProcessInfo.processInfo.environment objectForKey:@"APPVIEW_PARTIAL_TTL_HOURS"];
    if (ttl.integerValue > 0) config.partialTTLHours = (NSUInteger)ttl.integerValue;

    NSString *proxyFallback = [NSProcessInfo.processInfo.environment objectForKey:@"APPVIEW_PARTIAL_PROXY_FALLBACK"];
    if (proxyFallback) config.partialProxyFallback = [proxyFallback boolValue];

    NSString *fallbackURL = [NSProcessInfo.processInfo.environment objectForKey:@"APPVIEW_PROXY_FALLBACK_URL"];
    if (fallbackURL.length > 0) config.partialProxyFallbackURL = fallbackURL;

    return config;
}

- (void)loadFromDictionary:(NSDictionary *)dict {
    // mode
    NSString *mode = dict[@"mode"];
    if ([mode isEqualToString:@"proxy"])      _mode = AppViewModeProxy;
    if ([mode isEqualToString:@"standalone"]) _mode = AppViewModeStandalone;

    // relay_urls
    id relays = dict[@"relay_urls"];
    if ([relays isKindOfClass:[NSArray class]]) _relayURLs = relays;
    if ([relays isKindOfClass:[NSString class]]) _relayURLs = @[relays];

    // data_directory
    NSString *dataDir = dict[@"data_directory"];
    if (dataDir.length > 0) _dataDirectory = dataDir;

    // http.port
    id port = dict[@"http.port"] ?: dict[@"port"];
    if ([port respondsToSelector:@selector(integerValue)] && [port integerValue] > 0)
        _httpPort = (NSUInteger)[port integerValue];

    // admin_secret
    NSString *secret = dict[@"admin_secret"];
    if (secret.length > 0) _adminSecret = secret;

    // cursor.checkpoint_interval_ms
    id ckpt = dict[@"cursor.checkpoint_interval_ms"];
    if ([ckpt respondsToSelector:@selector(integerValue)] && [ckpt integerValue] > 0)
        _cursorCheckpointIntervalMs = (NSUInteger)[ckpt integerValue];

    // backfill.*
    id bfEnabled = dict[@"backfill.enabled"];
    if (bfEnabled) _backfillEnabled = [bfEnabled boolValue];

    id bfGlobal = dict[@"backfill.global_workers"];
    if ([bfGlobal respondsToSelector:@selector(integerValue)] && [bfGlobal integerValue] > 0)
        _backfillGlobalWorkers = (NSUInteger)[bfGlobal integerValue];

    id bfHost = dict[@"backfill.per_host_workers"];
    if ([bfHost respondsToSelector:@selector(integerValue)] && [bfHost integerValue] > 0)
        _backfillPerHostWorkers = (NSUInteger)[bfHost integerValue];

    // partial.*
    id partialEnabled = dict[@"partial.enabled"];
    if (partialEnabled) _partialEnabled = [partialEnabled boolValue];

    id seeds = dict[@"partial.seed_dids"];
    if ([seeds isKindOfClass:[NSArray class]]) _partialSeedDIDs = seeds;

    id allow = dict[@"partial.allowlist"];
    if ([allow isKindOfClass:[NSArray class]]) _partialAllowlist = allow;

    id ttl = dict[@"partial.ttl_hours"];
    if ([ttl respondsToSelector:@selector(integerValue)] && [ttl integerValue] > 0)
        _partialTTLHours = (NSUInteger)[ttl integerValue];

    id proxyFallback = dict[@"partial.proxy_fallback"];
    if (proxyFallback) _partialProxyFallback = [proxyFallback boolValue];

    NSString *fallbackURL = dict[@"partial.proxy_fallback_url"];
    if (fallbackURL.length > 0) _partialProxyFallbackURL = fallbackURL;
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
