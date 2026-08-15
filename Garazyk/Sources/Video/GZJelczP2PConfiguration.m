// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Video/GZJelczP2PConfiguration.h"

#import "Video/GZJelczIrohSidecarURL.h"

static BOOL GZJelczEnvTruthy(NSString * _Nullable value) {
    if (value.length == 0) {
        return NO;
    }
    static NSSet<NSString *> *truthy;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        truthy = [NSSet setWithObjects:@"1", @"true", @"yes", @"on", nil];
    });
    return [truthy containsObject:[value lowercaseString]];
}

@implementation GZJelczP2PConfiguration

+ (BOOL)isP2PEnabledInEnvironment:(NSDictionary *)env {
    return GZJelczEnvTruthy(env[@"JELCZ_P2P"]);
}

+ (BOOL)trustLanInEnvironment:(NSDictionary *)env {
    return GZJelczEnvTruthy(env[@"JELCZ_IROH_SIDECAR_TRUST_LAN"]);
}

+ (NSString *)irohSidecarHTTPBaseURLFromEnvironment:(NSDictionary *)env {
    return [GZJelczIrohSidecarURL normalizedHTTPBase:env[@"JELCZ_IROH_SIDECAR_URL"]
                                            trustLan:[self trustLanInEnvironment:env]];
}

+ (BOOL)shouldWireIrohSidecarMirrorFetcherInEnvironment:(NSDictionary *)env {
    NSString *capability = [env[@"JELCZ_IROH_SIDECAR_CAPABILITY"]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [self isP2PEnabledInEnvironment:env] &&
        [self irohSidecarHTTPBaseURLFromEnvironment:env].length > 0 &&
        capability.length > 0;
}

@end
