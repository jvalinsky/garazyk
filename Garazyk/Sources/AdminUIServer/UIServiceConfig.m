// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/UIServiceConfig.h"

static NSString *UIEnvString(NSDictionary<NSString *, NSString *> *env,
                             NSString *key,
                             NSString *fallback) {
    NSString *value = [env[key] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return value.length > 0 ? value : fallback;
}

static NSUInteger UIEnvUnsigned(NSDictionary<NSString *, NSString *> *env,
                                NSString *key,
                                NSUInteger fallback) {
    NSString *value = [env[key] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (value.length == 0) {
        return fallback;
    }
    NSInteger parsed = [value integerValue];
    return parsed > 0 ? (NSUInteger)parsed : fallback;
}

static NSString *UIEnvOptionalString(NSDictionary<NSString *, NSString *> *env,
                                     NSString *key) {
    NSString *value = [env[key] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return value.length > 0 ? value : nil;
}

static NSURL *UIURLFromString(NSString *value, NSString *fallback) {
    NSURL *url = [NSURL URLWithString:value ?: @""];
    if (url.scheme.length == 0 || url.host.length == 0) {
        url = [NSURL URLWithString:fallback];
    }
    return url;
}

/** Parse "Relay=http://127.0.0.1:2591,PLC=http://127.0.0.1:2592" into peer link dicts. */
static NSArray<NSDictionary<NSString *, NSString *> *> *UIPeerLinksFromString(NSString *raw) {
    if (raw.length == 0) {
        return @[];
    }
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *links = [NSMutableArray array];
    NSArray<NSString *> *entries = [raw componentsSeparatedByString:@","];
    for (NSString *entry in entries) {
        NSString *trimmed = [entry stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) {
            continue;
        }
        NSRange sep = [trimmed rangeOfString:@"="];
        if (sep.location == NSNotFound || sep.location == 0) {
            continue;
        }
        NSString *name = [[trimmed substringToIndex:sep.location]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *urlString = [[trimmed substringFromIndex:NSMaxRange(sep)]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSURL *url = [NSURL URLWithString:urlString ?: @""];
        if (name.length == 0 || url.scheme.length == 0 || url.host.length == 0) {
            continue;
        }
        if (![url.scheme isEqualToString:@"http"] && ![url.scheme isEqualToString:@"https"]) {
            continue;
        }
        [links addObject:@{@"displayName": name, @"url": url.absoluteString}];
    }
    return [links copy];
}

@implementation GZAdminUIServiceConfig

- (instancetype)init {
    self = [super init];
    if (self) {
        _peerLinks = @[];
        // Auto-detect Assets/ directory next to the binary so embedded
        // admin hosts (PLC, Beskid, Mikrus, relay, etc.) that create
        // the config with plain -init still find their static assets.
        // configurationFromEnvironment can override with the env var.
        NSString *binaryPath = [[NSBundle mainBundle] executablePath];
        if (!binaryPath || binaryPath.length == 0) {
            binaryPath = [[NSProcessInfo processInfo] arguments][0];
        }
        if (binaryPath) {
            NSString *binaryDir = [binaryPath stringByDeletingLastPathComponent];
            NSString *candidate = [binaryDir stringByAppendingPathComponent:@"Assets"];
            if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
                _assetsDirectory = [candidate copy];
            }
        }
    }
    return self;
}

+ (instancetype)configurationFromEnvironment {
    NSDictionary<NSString *, NSString *> *env = [[NSProcessInfo processInfo] environment];

    GZAdminUIServiceConfig *config = [[GZAdminUIServiceConfig alloc] init];
    config.host = UIEnvString(env, @"GARAZYK_ADMIN_UI_HOST", @"127.0.0.1");
    config.port = UIEnvUnsigned(env, @"GARAZYK_ADMIN_UI_PORT", 2590);
    config.adminPassword = UIEnvString(env, @"GARAZYK_ADMIN_UI_ADMIN_PASSWORD", @"changeme");

    NSString *pdsURL = UIEnvString(env, @"GARAZYK_ADMIN_UI_PDS_URL", @"http://127.0.0.1:2583");
    NSString *plcURL = UIEnvString(env, @"GARAZYK_ADMIN_UI_PLC_URL", @"http://127.0.0.1:2582");
    NSString *relayURL = UIEnvString(env, @"GARAZYK_ADMIN_UI_RELAY_URL", @"http://127.0.0.1:2584");
    NSString *appViewURL = UIEnvString(env, @"GARAZYK_ADMIN_UI_APPVIEW_URL", @"http://127.0.0.1:3200");
    NSString *chatURL = UIEnvString(env, @"GARAZYK_ADMIN_UI_CHAT_URL", appViewURL);
    NSString *videoURL = UIEnvString(env, @"GARAZYK_ADMIN_UI_VIDEO_URL", @"http://127.0.0.1:2586");
    NSString *germURL = UIEnvString(env, @"GARAZYK_ADMIN_UI_GERM_URL", @"http://127.0.0.1:8082");

    config.pdsBaseURL = UIURLFromString(pdsURL, @"http://127.0.0.1:2583");
    config.plcBaseURL = UIURLFromString(plcURL, @"http://127.0.0.1:2582");
    config.relayBaseURL = UIURLFromString(relayURL, @"http://127.0.0.1:2584");
    config.appViewBaseURL = UIURLFromString(appViewURL, @"http://127.0.0.1:3200");
    config.chatBaseURL = UIURLFromString(chatURL, @"http://127.0.0.1:3200");
    config.videoBaseURL = UIURLFromString(videoURL, @"http://127.0.0.1:2586");
    config.germBaseURL = UIURLFromString(germURL, @"http://127.0.0.1:8082");

    config.pdsAdminToken = UIEnvOptionalString(env, @"GARAZYK_ADMIN_UI_PDS_TOKEN");
    config.pdsAdminPassword = UIEnvOptionalString(env, @"GARAZYK_ADMIN_UI_PDS_PASSWORD");
    config.plcAdminToken = UIEnvOptionalString(env, @"GARAZYK_ADMIN_UI_PLC_TOKEN");
    config.relayAdminToken = UIEnvOptionalString(env, @"GARAZYK_ADMIN_UI_RELAY_TOKEN");
    config.appViewAdminToken = UIEnvOptionalString(env, @"GARAZYK_ADMIN_UI_APPVIEW_TOKEN");
    config.chatAdminToken = UIEnvOptionalString(env, @"GARAZYK_ADMIN_UI_CHAT_TOKEN");
    config.videoAdminToken = UIEnvOptionalString(env, @"GARAZYK_ADMIN_UI_VIDEO_TOKEN");
    config.germAdminToken = UIEnvOptionalString(env, @"GARAZYK_ADMIN_UI_GERM_TOKEN");

    // Assets directory: env var overrides the auto-detected default from -init
    NSString *assetsDir = UIEnvOptionalString(env, @"GARAZYK_ADMIN_UI_ASSETS_DIR");
    if (assetsDir) {
        config.assetsDirectory = assetsDir;
    }

    NSString *peers = UIEnvOptionalString(env, @"GARAZYK_ADMIN_UI_PEERS");
    if (!peers) {
        peers = UIEnvOptionalString(env, @"PDS_ADMIN_UI_PEERS");
    }
    config.peerLinks = UIPeerLinksFromString(peers);

    NSString *tilesHost = UIEnvOptionalString(env, @"GARAZYK_ADMIN_UI_TILES_BASE_HOST");
    if (!tilesHost) {
        tilesHost = UIEnvOptionalString(env, @"PDS_ADMIN_UI_TILES_BASE_HOST");
    }
    config.tilesBaseHost = tilesHost;

    return config;
}

- (BOOL)updateWithDictionary:(NSDictionary<NSString *, NSString *> *)updates {
    if (!updates) return NO;

    BOOL allValid = YES;

    // Update URLs — validate each one before applying
    NSDictionary<NSString *, NSString *> *urlMappings = @{
        @"pdsURL": @"pdsBaseURL",
        @"plcURL": @"plcBaseURL",
        @"relayURL": @"relayBaseURL",
        @"appViewURL": @"appViewBaseURL",
        @"appviewURL": @"appViewBaseURL",
        @"chatURL": @"chatBaseURL",
        @"videoURL": @"videoBaseURL",
        @"germURL": @"germBaseURL"
    };

    for (NSString *key in urlMappings) {
        NSString *value = updates[key];
        if (value.length > 0) {
            NSURL *url = [NSURL URLWithString:value];
            if (url.scheme.length > 0 && url.host.length > 0) {
                NSString *propName = urlMappings[key];
                [self setValue:url forKey:propName];
            } else {
                allValid = NO;
            }
        }
    }

    // Update tokens (no validation needed — empty string clears, nil leaves unchanged)
    if (updates[@"pdsToken"] != nil) {
        self.pdsAdminToken = updates[@"pdsToken"].length > 0 ? updates[@"pdsToken"] : nil;
    }
    if (updates[@"plcToken"] != nil) {
        self.plcAdminToken = updates[@"plcToken"].length > 0 ? updates[@"plcToken"] : nil;
    }
    if (updates[@"relayToken"] != nil) {
        self.relayAdminToken = updates[@"relayToken"].length > 0 ? updates[@"relayToken"] : nil;
    }
    if (updates[@"appviewToken"] != nil) {
        self.appViewAdminToken = updates[@"appviewToken"].length > 0 ? updates[@"appviewToken"] : nil;
    }
    if (updates[@"appViewToken"] != nil) {
        self.appViewAdminToken = updates[@"appViewToken"].length > 0 ? updates[@"appViewToken"] : nil;
    }
    if (updates[@"chatToken"] != nil) {
        self.chatAdminToken = updates[@"chatToken"].length > 0 ? updates[@"chatToken"] : nil;
    }
    if (updates[@"videoToken"] != nil) {
        self.videoAdminToken = updates[@"videoToken"].length > 0 ? updates[@"videoToken"] : nil;
    }
    if (updates[@"germToken"] != nil) {
        self.germAdminToken = updates[@"germToken"].length > 0 ? updates[@"germToken"] : nil;
    }

    return allValid;
}

@end
