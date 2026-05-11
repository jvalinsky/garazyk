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

@implementation UIServiceConfig

+ (instancetype)configurationFromEnvironment {
    NSDictionary<NSString *, NSString *> *env = [[NSProcessInfo processInfo] environment];

    UIServiceConfig *config = [[UIServiceConfig alloc] init];
    config.host = UIEnvString(env, @"GARAZYK_UI_HOST", @"127.0.0.1");
    config.port = UIEnvUnsigned(env, @"GARAZYK_UI_PORT", 2590);
    config.adminPassword = UIEnvString(env, @"GARAZYK_UI_ADMIN_PASSWORD", @"changeme");

    NSString *pdsURL = UIEnvString(env, @"GARAZYK_UI_PDS_URL", @"http://127.0.0.1:2583");
    NSString *plcURL = UIEnvString(env, @"GARAZYK_UI_PLC_URL", @"http://127.0.0.1:2582");
    NSString *relayURL = UIEnvString(env, @"GARAZYK_UI_RELAY_URL", @"http://127.0.0.1:2584");
    NSString *appViewURL = UIEnvString(env, @"GARAZYK_UI_APPVIEW_URL", @"http://127.0.0.1:3200");
    NSString *chatURL = UIEnvString(env, @"GARAZYK_UI_CHAT_URL", appViewURL);
    NSString *videoURL = UIEnvString(env, @"GARAZYK_UI_VIDEO_URL", @"http://127.0.0.1:2586");

    config.pdsBaseURL = UIURLFromString(pdsURL, @"http://127.0.0.1:2583");
    config.plcBaseURL = UIURLFromString(plcURL, @"http://127.0.0.1:2582");
    config.relayBaseURL = UIURLFromString(relayURL, @"http://127.0.0.1:2584");
    config.appViewBaseURL = UIURLFromString(appViewURL, @"http://127.0.0.1:3200");
    config.chatBaseURL = UIURLFromString(chatURL, @"http://127.0.0.1:3200");
    config.videoBaseURL = UIURLFromString(videoURL, @"http://127.0.0.1:2586");

    config.pdsAdminToken = UIEnvOptionalString(env, @"GARAZYK_UI_PDS_TOKEN");
    config.pdsAdminPassword = UIEnvOptionalString(env, @"GARAZYK_UI_PDS_PASSWORD");
    config.plcAdminToken = UIEnvOptionalString(env, @"GARAZYK_UI_PLC_TOKEN");
    config.relayAdminToken = UIEnvOptionalString(env, @"GARAZYK_UI_RELAY_TOKEN");
    config.appViewAdminToken = UIEnvOptionalString(env, @"GARAZYK_UI_APPVIEW_TOKEN");
    config.chatAdminToken = UIEnvOptionalString(env, @"GARAZYK_UI_CHAT_TOKEN");
    config.videoAdminToken = UIEnvOptionalString(env, @"GARAZYK_UI_VIDEO_TOKEN");

    // Assets directory: env override, or auto-detect next to binary
    NSString *assetsDir = UIEnvOptionalString(env, @"GARAZYK_UI_ASSETS_DIR");
    if (!assetsDir) {
        // Default: look for Assets/ next to the running binary
        NSString *binaryPath = [[NSBundle mainBundle] executablePath] ?: [[NSProcessInfo processInfo] arguments][0];
        if (binaryPath) {
            NSString *binaryDir = [binaryPath stringByDeletingLastPathComponent];
            assetsDir = [binaryDir stringByAppendingPathComponent:@"Assets"];
        }
    }
    config.assetsDirectory = assetsDir;

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
        @"videoURL": @"videoBaseURL"
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

    return allValid;
}

@end
