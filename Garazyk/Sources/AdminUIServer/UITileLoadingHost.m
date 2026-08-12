// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/UITileLoadingHost.h"
#import "AdminUIServer/UITileExecutionPolicy.h"
#include <stdlib.h>
#include <string.h>

static NSString *GZAdminUITileNormalizedBaseHost(NSString *baseHost) {
    NSString *trimmed = [[baseHost lowercaseString]
                         stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([trimmed hasPrefix:@"."]) {
        trimmed = [trimmed substringFromIndex:1];
    }
    return trimmed;
}

BOOL GZAdminUITileIsLoadHost(NSString *hostname, NSString *baseHost) {
    if (hostname.length == 0 || baseHost.length == 0) return NO;
    NSString *base = GZAdminUITileNormalizedBaseHost(baseHost);
    NSString *expected = [@"load." stringByAppendingString:base];
    return [[hostname lowercaseString] isEqualToString:expected];
}

BOOL GZAdminUITileIsUniqueOriginHost(NSString *hostname, NSString *baseHost) {
    if (hostname.length == 0 || baseHost.length == 0) return NO;
    NSString *host = [hostname lowercaseString];
    NSString *base = GZAdminUITileNormalizedBaseHost(baseHost);
    NSString *suffix = [@"." stringByAppendingString:base];
    if (host.length <= suffix.length || ![host hasSuffix:suffix]) return NO;
    NSString *label = [host substringToIndex:host.length - suffix.length];
    if (label.length != 20) return NO;
    static NSCharacterSet *allowed = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz"];
    });
    return [label rangeOfCharacterFromSet:[allowed invertedSet]].location == NSNotFound;
}

NSString *GZAdminUITileMakeUniqueOriginLabel(void) {
    static const char alphabet[] = "abcdefghijklmnopqrstuvwxyz";
    char label[21];
    for (int i = 0; i < 20; i++) {
        label[i] = alphabet[arc4random_uniform(26)];
    }
    label[20] = '\0';
    return [[NSString alloc] initWithBytes:label length:20 encoding:NSASCIIStringEncoding];
}

NSString *GZAdminUITileUniqueOriginRedirectURL(NSString *scheme,
                                               NSString *baseHost,
                                               NSString *pathAndQuery) {
    NSString *safeScheme = scheme.length > 0 ? [scheme lowercaseString] : @"https";
    NSString *base = GZAdminUITileNormalizedBaseHost(baseHost);
    NSString *path = pathAndQuery.length > 0 ? pathAndQuery : @"/";
    if (![path hasPrefix:@"/"]) {
        path = [@"/" stringByAppendingString:path];
    }
    NSString *label = GZAdminUITileMakeUniqueOriginLabel();
    return [NSString stringWithFormat:@"%@://%@.%@%@", safeScheme, label, base, path];
}

NSString *GZAdminUITileShuttleHTML(void) {
    return @"<!DOCTYPE html>\n"
           "<html lang=\"en\">\n"
           "<head>\n"
           "<meta charset=\"utf-8\">\n"
           "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
           "<title>Web Tile Shuttle</title>\n"
           "<style>\n"
           "* { box-sizing: border-box; }\n"
           "html, body { margin: 0; padding: 0; width: 100%; height: 100%; }\n"
           "</style>\n"
           "</head>\n"
           "<body>\n"
           "<!-- Unique-origin shuttle shell. CAR/MASL tile loading is not wired yet. -->\n"
           "</body>\n"
           "</html>\n";
}

void GZAdminUITileApplyUniqueOriginHeaders(ATProtoHttpResponse *response) {
    if (![response isKindOfClass:[ATProtoHttpResponse class]]) return;
    NSDictionary *headers = GZAdminUITileExecutionSecurityHeaders();
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        [response setHeader:value forKey:key];
    }];
    [response setHeader:@"/" forKey:@"service-worker-allowed"];
    [response setHeader:@"N" forKey:@"tk"];
    [response setHeader:@"noai, noimageai" forKey:@"x-robots-tag"];
}
