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

    config.pdsBaseURL = UIURLFromString(pdsURL, @"http://127.0.0.1:2583");
    config.plcBaseURL = UIURLFromString(plcURL, @"http://127.0.0.1:2582");
    config.relayBaseURL = UIURLFromString(relayURL, @"http://127.0.0.1:2584");
    config.appViewBaseURL = UIURLFromString(appViewURL, @"http://127.0.0.1:3200");
    config.chatBaseURL = UIURLFromString(chatURL, @"http://127.0.0.1:3200");

    config.pdsAdminToken = UIEnvOptionalString(env, @"GARAZYK_UI_PDS_TOKEN");
    config.plcAdminToken = UIEnvOptionalString(env, @"GARAZYK_UI_PLC_TOKEN");
    config.relayAdminToken = UIEnvOptionalString(env, @"GARAZYK_UI_RELAY_TOKEN");
    config.appViewAdminToken = UIEnvOptionalString(env, @"GARAZYK_UI_APPVIEW_TOKEN");
    config.chatAdminToken = UIEnvOptionalString(env, @"GARAZYK_UI_CHAT_TOKEN");

    return config;
}

@end

