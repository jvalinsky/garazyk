// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Core/ATProtoRASLURL.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"

NSErrorDomain const ATProtoRASLURLErrorDomain = @"com.atproto.rasl.url";

/** Defensive cap on hint count; the spec does not bound this. */
static const NSUInteger kATProtoRASLMaxHints = 20;

static NSError *ATProtoRASLURLMakeError(ATProtoRASLURLErrorCode code, NSString *description) {
    return [NSError errorWithDomain:ATProtoRASLURLErrorDomain
                                code:code
                            userInfo:@{NSLocalizedDescriptionKey: description}];
}

/**
 Validates that `hint` is syntactically a bare HTTPS host (optionally with a
 port), with no scheme, path, query, userinfo, or fragment of its own.
 Delegates the actual grammar to NSURL against the well-supported `https`
 scheme rather than hand-rolling host/IPv6-literal parsing; `rasl://` itself
 is still parsed by hand below because custom URL schemes are not reliably
 handled by NSURL across platforms.
 */
static BOOL ATProtoRASLIsValidHTTPSHost(NSString *hint, NSString **normalizedOut) {
    if (hint.length == 0 || hint.length > 255) {
        return NO;
    }
    if ([hint rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound) {
        return NO;
    }
    NSCharacterSet *disallowed = [NSCharacterSet characterSetWithCharactersInString:@"/?#@\\"];
    if ([hint rangeOfCharacterFromSet:disallowed].location != NSNotFound) {
        return NO;
    }

    NSString *candidate = [NSString stringWithFormat:@"https://%@/", hint];
    NSURL *url = [NSURL URLWithString:candidate];
    if (!url || url.host.length == 0) {
        return NO;
    }
    if (![url.scheme isEqualToString:@"https"]) {
        return NO;
    }
    if (url.user != nil || url.password != nil) {
        return NO;
    }
    NSString *path = url.path ?: @"";
    if (path.length > 1) {
        // Anything beyond the trailing "/" we appended means the hint smuggled
        // extra path content that NSURL folded in some other way.
        return NO;
    }
    NSNumber *port = url.port;
    if (port != nil && (port.integerValue < 1 || port.integerValue > 65535)) {
        return NO;
    }

    if (normalizedOut) {
        *normalizedOut = port ? [NSString stringWithFormat:@"%@:%@", url.host, port] : url.host;
    }
    return YES;
}

@interface ATProtoRASLURL ()
@property (nonatomic, strong, readwrite) CID *cid;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *hints;
@end

@implementation ATProtoRASLURL

+ (nullable instancetype)raslURLFromString:(NSString *)string error:(NSError **)error {
    static NSString *const kScheme = @"rasl://";

    if (string.length < kScheme.length ||
        [[string substringToIndex:kScheme.length] caseInsensitiveCompare:kScheme] != NSOrderedSame) {
        if (error) {
            *error = ATProtoRASLURLMakeError(ATProtoRASLURLErrorInvalidScheme,
                                              @"URL does not start with rasl://");
        }
        return nil;
    }

    NSString *remainder = [string substringFromIndex:kScheme.length];

    NSCharacterSet *authorityTerminators = [NSCharacterSet characterSetWithCharactersInString:@"/?"];
    NSRange terminatorRange = [remainder rangeOfCharacterFromSet:authorityTerminators];
    NSString *authority = (terminatorRange.location == NSNotFound)
        ? remainder
        : [remainder substringToIndex:terminatorRange.location];

    if (authority.length == 0) {
        if (error) {
            *error = ATProtoRASLURLMakeError(ATProtoRASLURLErrorMissingCID,
                                              @"rasl:// URL has an empty authority");
        }
        return nil;
    }

    CID *cid = [CID daslCIDFromString:authority profile:ATProtoDASLCIDProfileBig];
    if (!cid) {
        if (error) {
            *error = ATProtoRASLURLMakeError(ATProtoRASLURLErrorInvalidCID,
                                              @"rasl:// authority is not a valid DASL CID");
        }
        return nil;
    }

    NSMutableArray<NSString *> *hints = [NSMutableArray array];
    NSRange queryMarker = [remainder rangeOfString:@"?"];
    if (queryMarker.location != NSNotFound) {
        NSString *queryString = [remainder substringFromIndex:queryMarker.location + 1];
        for (NSString *pair in [queryString componentsSeparatedByString:@"&"]) {
            if (pair.length == 0) {
                continue;
            }
            NSRange equalsRange = [pair rangeOfString:@"="];
            NSString *key = (equalsRange.location == NSNotFound) ? pair : [pair substringToIndex:equalsRange.location];
            if (![key isEqualToString:@"hint"]) {
                continue;
            }
            NSString *rawValue = (equalsRange.location == NSNotFound)
                ? @""
                : [pair substringFromIndex:equalsRange.location + 1];
            NSString *decoded = [rawValue stringByRemovingPercentEncoding];
            if (decoded.length == 0) {
                continue;
            }
            NSString *normalized = nil;
            if (!ATProtoRASLIsValidHTTPSHost(decoded, &normalized)) {
                continue;
            }
            if (![hints containsObject:normalized]) {
                [hints addObject:normalized];
            }
            if (hints.count >= kATProtoRASLMaxHints) {
                break;
            }
        }
    }

    ATProtoRASLURL *url = [[ATProtoRASLURL alloc] init];
    url.cid = cid;
    url.hints = hints;
    return url;
}

- (NSString *)wellKnownPath {
    return ATProtoRASLWellKnownPathForCID(self.cid);
}

@end

NSString *ATProtoRASLWellKnownPathForCID(CID *cid) {
    return [NSString stringWithFormat:@"/.well-known/rasl/%@", cid.stringValue];
}
