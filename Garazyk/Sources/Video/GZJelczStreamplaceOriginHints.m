// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Video/GZJelczStreamplaceOriginHints.h"

@implementation GZJelczStreamplaceOriginHints

+ (NSString *)normalizedProviderBaseURL:(NSString *)base {
    if (base.length == 0) {
        return nil;
    }
    NSString *trimmed = [base stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    trimmed = [trimmed stringByTrimmingCharactersInSet:
               [NSCharacterSet characterSetWithCharactersInString:@"/"]];
    if (trimmed.length == 0) {
        return nil;
    }
    NSURL *url = nil;
    if ([trimmed hasPrefix:@"http://"] || [trimmed hasPrefix:@"https://"]) {
        url = [NSURL URLWithString:trimmed];
    } else {
        url = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@", trimmed]];
    }
    if (!url.host) {
        return nil;
    }
    NSString *scheme = url.scheme.length > 0 ? url.scheme : @"https";
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        return nil;
    }
    if (url.port) {
        return [NSString stringWithFormat:@"%@://%@:%@", scheme, url.host, url.port];
    }
    return [NSString stringWithFormat:@"%@://%@", scheme, url.host];
}

+ (NSArray<NSString *> *)providersByMergingStreamplaceBase:(NSString *)streamplaceBase
                                        existingProviders:(NSArray<NSString *> *)existing {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    void (^add)(NSString *) = ^(NSString *raw) {
        NSString *norm = [self normalizedProviderBaseURL:raw];
        if (!norm || [seen containsObject:norm]) {
            return;
        }
        [seen addObject:norm];
        [out addObject:norm];
    };
    add(streamplaceBase);
    for (NSString *p in existing) {
        add(p);
    }
    return [out copy];
}

+ (NSArray<NSString *> *)providersForCIDString:(NSString *)cidString
                                 originRecord:(NSDictionary *)originRecord
                           configuredBaseURL:(NSString *)configuredBaseURL {
    NSString *base = [self normalizedProviderBaseURL:configuredBaseURL];
    if (!base || cidString.length == 0) {
        return nil;
    }
    if (originRecord) {
        id blob = originRecord[@"blob"];
        if (![blob isKindOfClass:[NSString class]] || [(NSString *)blob length] == 0) {
            return nil;
        }
        NSString *blobCID = (NSString *)blob;
        if ([blobCID.lowercaseString hasSuffix:@".m4s"]) {
            blobCID = [blobCID substringToIndex:blobCID.length - 4];
        }
        NSString *want = cidString;
        if ([want.lowercaseString hasSuffix:@".m4s"]) {
            want = [want substringToIndex:want.length - 4];
        }
        if (![blobCID isEqualToString:want]) {
            return nil;
        }
    }
    return @[ base ];
}

+ (NSDictionary *)originRecordForBlobCID:(NSString *)cidString
                                    size:(NSUInteger)size
                                mimeType:(NSString *)mimeType {
    return @{
        @"$type": @"place.stream.media.origin",
        @"blob": cidString ?: @"",
        @"size": @(size),
        @"mimeType": mimeType.length > 0 ? mimeType : @"video/mp4",
    };
}

@end
