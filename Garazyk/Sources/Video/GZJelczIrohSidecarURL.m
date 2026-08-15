// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Video/GZJelczIrohSidecarURL.h"

static BOOL GZJelczHostAllowed(NSString *host, BOOL trustLan) {
    if ([host isEqualToString:@"127.0.0.1"] ||
        [host isEqualToString:@"localhost"] ||
        [host isEqualToString:@"::1"]) {
        return YES;
    }
    if (!trustLan) {
        return NO;
    }
    // Track A only needs the named sidecars from docker-compose.yml.  Do not
    // turn trustLan into a general DNS escape hatch: public names, link-local
    // addresses, IPv6 literals, and DNS rebinding aliases must never reach
    // the HTTP client.
    static NSSet<NSString *> *composeSidecars;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        composeSidecars = [NSSet setWithObjects:@"iroh-a", @"iroh-b", @"iroh-c", nil];
    });
    return [composeSidecars containsObject:host.lowercaseString];
}

@implementation GZJelczIrohSidecarURL

+ (NSString *)normalizedHTTPBase:(NSString *)raw trustLan:(BOOL)trustLan {
    if (raw.length == 0) {
        return nil;
    }
    NSString *trimmed = [raw stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    trimmed = [trimmed stringByTrimmingCharactersInSet:
               [NSCharacterSet characterSetWithCharactersInString:@"/"]];
    if ([trimmed hasPrefix:@"unix://"] || [trimmed hasPrefix:@"/"]) {
        return nil;
    }
    NSURL *base = [NSURL URLWithString:trimmed];
    if (!base.host.length) {
        return nil;
    }
    if (![base.scheme isEqualToString:@"http"]) {
        return nil;
    }
    if (!GZJelczHostAllowed(base.host, trustLan)) {
        return nil;
    }
    if (base.port) {
        return [NSString stringWithFormat:@"http://%@:%@", base.host, base.port];
    }
    return [NSString stringWithFormat:@"http://%@", base.host];
}

@end
