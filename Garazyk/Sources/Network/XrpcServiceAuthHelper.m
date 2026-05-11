// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/XrpcServiceAuthHelper.h"
#import "App/PDSConfiguration.h"

NSString *XrpcDidWebIdentifierFromIssuer(NSString *issuer, NSString *fallbackHost) {
    NSURLComponents *components = [NSURLComponents componentsWithString:issuer];
    NSString *scheme = [components.scheme.lowercaseString copy];
    NSString *host = [components.host.lowercaseString copy];
    if (host.length == 0) {
        host = [fallbackHost.lowercaseString copy];
    }
    if (host.length == 0) {
        host = @"localhost";
    }

    NSUInteger port = components.port != nil ? (NSUInteger)MAX((NSInteger)0, components.port.integerValue) : 0;
    BOOL includePort = NO;
    if (port > 0) {
        BOOL defaultPort = ([scheme isEqualToString:@"https"] && port == 443) ||
                           ([scheme isEqualToString:@"http"] && port == 80);
        includePort = !defaultPort;
    }

    if (includePort) {
        return [NSString stringWithFormat:@"did:web:%@%%3A%lu", host, (unsigned long)port];
    }
    return [NSString stringWithFormat:@"did:web:%@", host];
}

NSArray<NSString *> *XrpcServiceAuthExpectedAudiences(PDSConfiguration *config) {
    NSString *issuer = [config canonicalIssuerWithPortHint:0];
    NSString *canonicalHost = [config canonicalHostname];
    NSMutableOrderedSet<NSString *> *audiences = [NSMutableOrderedSet orderedSet];
    [audiences addObject:XrpcDidWebIdentifierFromIssuer(issuer, canonicalHost)];
    if (canonicalHost.length > 0) {
        [audiences addObject:[NSString stringWithFormat:@"did:web:%@", canonicalHost]];
    }
    return audiences.array;
}
