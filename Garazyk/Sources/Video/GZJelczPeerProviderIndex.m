// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Video/GZJelczPeerProviderIndex.h"
#import "Video/GZJelczStreamplaceOriginHints.h"

@implementation GZJelczPeerProviderEntry

- (NSDictionary *)allowlistedDictionary {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (self.httpsBase) d[@"httpsBase"] = self.httpsBase;
    if (self.serverDID) d[@"server"] = self.serverDID;
    if (self.streamerDID) d[@"streamer"] = self.streamerDID;
    if (self.broadcasterDID) d[@"broadcaster"] = self.broadcasterDID;
    if (self.irohTicket.length > 0) d[@"hasIrohTicket"] = @YES;
    if (self.manifestCID) d[@"manifestCid"] = self.manifestCID;
    if (self.updatedAt) {
        d[@"updatedAt"] = [GZJelczPeerProviderEntry iso8601StringFromDate:self.updatedAt];
    }
    d[@"source"] = self.source ?: @"unknown";
    return [d copy];
}

+ (NSString *)iso8601StringFromDate:(NSDate *)date {
    static NSISO8601DateFormatter *fmt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSISO8601DateFormatter alloc] init];
        fmt.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    });
    return [fmt stringFromDate:date] ?: @"";
}

@end

@implementation GZJelczPeerProviderIndex

+ (NSSet<NSString *> *)allowlistSetFromCSV:(NSString *)csv {
    if (csv.length == 0) {
        return [NSSet set];
    }
    NSMutableSet *set = [NSMutableSet set];
    for (NSString *part in [csv componentsSeparatedByString:@","]) {
        NSString *t = [part stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (t.length > 0) {
            [set addObject:t];
        }
    }
    return [set copy];
}

+ (BOOL)isDID:(NSString *)did allowedBy:(NSSet<NSString *> *)allowlist {
    if (did.length == 0 || allowlist.count == 0) {
        return NO;
    }
    if ([allowlist containsObject:@"*"]) {
        return YES;
    }
    return [allowlist containsObject:did];
}

+ (BOOL)allowsStreamer:(NSString *)streamer
           broadcaster:(NSString *)broadcaster
      allowedStreamers:(NSSet<NSString *> *)allowedStreamers
   allowedBroadcasters:(NSSet<NSString *> *)allowedBroadcasters {
    if (allowedStreamers.count == 0 && allowedBroadcasters.count == 0) {
        return NO;
    }
    if (allowedStreamers.count > 0) {
        if ([self isDID:streamer allowedBy:allowedStreamers]) {
            return YES;
        }
        // Allow-all streamers short-circuit.
        if ([allowedStreamers containsObject:@"*"]) {
            return YES;
        }
    }
    if (allowedBroadcasters.count > 0) {
        if ([self isDID:broadcaster allowedBy:allowedBroadcasters]) {
            return YES;
        }
        if ([allowedBroadcasters containsObject:@"*"]) {
            return YES;
        }
    }
    return NO;
}

+ (NSDate *)parseDate:(id)value {
    if ([value isKindOfClass:[NSDate class]]) {
        return (NSDate *)value;
    }
    if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] == 0) {
        return nil;
    }
    static NSISO8601DateFormatter *fmt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSISO8601DateFormatter alloc] init];
        fmt.formatOptions = NSISO8601DateFormatWithInternetDateTime
            | NSISO8601DateFormatWithFractionalSeconds;
    });
    NSDate *d = [fmt dateFromString:(NSString *)value];
    if (d) return d;
    static NSISO8601DateFormatter *fmtNoFrac;
    static dispatch_once_t once2;
    dispatch_once(&once2, ^{
        fmtNoFrac = [[NSISO8601DateFormatter alloc] init];
        fmtNoFrac.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    });
    return [fmtNoFrac dateFromString:(NSString *)value];
}

+ (nullable NSString *)httpsBaseFromWebSocketURL:(NSString *)wsURL {
    if (wsURL.length == 0) return nil;
    NSURL *url = [NSURL URLWithString:wsURL];
    if (!url.host) return nil;
    NSString *s = url.scheme.lowercaseString;
    NSString *scheme = ([s isEqualToString:@"ws"] || [s isEqualToString:@"http"]) ? @"http" : @"https";
    NSString *raw = url.port
        ? [NSString stringWithFormat:@"%@://%@:%@", scheme, url.host, url.port]
        : [NSString stringWithFormat:@"%@://%@", scheme, url.host];
    return [GZJelczStreamplaceOriginHints normalizedProviderBaseURL:raw];
}

+ (GZJelczPeerProviderEntry *)entryFromBroadcastOriginRecord:(NSDictionary *)record {
    if (![record isKindOfClass:[NSDictionary class]]) return nil;
    NSString *streamer = record[@"streamer"];
    NSString *server = record[@"server"];
    if (streamer.length == 0 || server.length == 0) return nil;
    GZJelczPeerProviderEntry *e = [[GZJelczPeerProviderEntry alloc] init];
    e.source = @"broadcast.origin";
    e.streamerDID = streamer;
    e.serverDID = server;
    e.broadcasterDID = record[@"broadcaster"];
    e.irohTicket = record[@"irohTicket"];
    e.updatedAt = [self parseDate:record[@"updatedAt"]];
    e.httpsBase = [self httpsBaseFromWebSocketURL:record[@"websocketURL"]];
    return e;
}

+ (GZJelczPeerProviderEntry *)entryFromGarazykVideoOriginRecord:(NSDictionary *)record {
    if (![record isKindOfClass:[NSDictionary class]]) return nil;
    NSString *watch = record[@"watchBaseUrl"];
    NSString *server = record[@"server"];
    NSString *manifest = record[@"manifestCid"];
    if (watch.length == 0 || server.length == 0) return nil;
    GZJelczPeerProviderEntry *e = [[GZJelczPeerProviderEntry alloc] init];
    e.source = @"video.origin";
    e.serverDID = server;
    e.manifestCID = manifest;
    e.httpsBase = [GZJelczStreamplaceOriginHints normalizedProviderBaseURL:watch];
    e.updatedAt = [self parseDate:record[@"lastSeenAt"]] ?: [self parseDate:record[@"createdAt"]];
    return e;
}

+ (GZJelczPeerProviderEntry *)entryFromMediaOriginRecord:(NSDictionary *)record
                                      configuredBaseURL:(NSString *)configuredBaseURL {
    if (![record isKindOfClass:[NSDictionary class]]) return nil;
    NSString *blob = record[@"blob"];
    if (blob.length == 0) return nil;
    NSString *base = [GZJelczStreamplaceOriginHints normalizedProviderBaseURL:configuredBaseURL];
    if (!base) return nil;
    GZJelczPeerProviderEntry *e = [[GZJelczPeerProviderEntry alloc] init];
    e.source = @"media.origin";
    e.manifestCID = blob;
    e.httpsBase = base;
    return e;
}

+ (NSArray<GZJelczPeerProviderEntry *> *)rankEntries:(NSArray<GZJelczPeerProviderEntry *> *)entries {
    return [entries sortedArrayUsingComparator:^NSComparisonResult(GZJelczPeerProviderEntry *a,
                                                                   GZJelczPeerProviderEntry *b) {
        if (a.updatedAt && b.updatedAt) {
            return [b.updatedAt compare:a.updatedAt];
        }
        if (a.updatedAt) return NSOrderedAscending;
        if (b.updatedAt) return NSOrderedDescending;
        return NSOrderedSame;
    }];
}

+ (NSArray<NSString *> *)httpsProviderBasesWithBootstrap:(NSString *)bootstrap
                                           envPeerBases:(NSArray<NSString *> *)envPeerBases
                                          originEntries:(NSArray<GZJelczPeerProviderEntry *> *)originEntries
                                       allowedStreamers:(NSSet<NSString *> *)allowedStreamers
                                    allowedBroadcasters:(NSSet<NSString *> *)allowedBroadcasters {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    void (^add)(NSString *) = ^(NSString *raw) {
        NSString *norm = [GZJelczStreamplaceOriginHints normalizedProviderBaseURL:raw];
        if (!norm || [seen containsObject:norm]) return;
        [seen addObject:norm];
        [out addObject:norm];
    };
    add(bootstrap);
    for (NSString *p in envPeerBases) {
        add(p);
    }
    NSArray *ranked = [self rankEntries:originEntries ?: @[]];
    for (GZJelczPeerProviderEntry *e in ranked) {
        if (e.httpsBase.length == 0) continue;
        BOOL trustedSource = [e.source isEqualToString:@"env"]
            || [e.source isEqualToString:@"media.origin"];
        if (!trustedSource) {
            if (![self allowsStreamer:e.streamerDID
                          broadcaster:e.broadcasterDID ?: e.serverDID
                     allowedStreamers:allowedStreamers
                  allowedBroadcasters:allowedBroadcasters]) {
                continue;
            }
        }
        add(e.httpsBase);
    }
    return [out copy];
}

+ (NSArray<GZJelczPeerProviderEntry *> *)entriesFromOriginsJSONObject:(id)json
                                                   configuredBaseURL:(NSString *)configuredBaseURL {
    NSArray *arr = nil;
    if ([json isKindOfClass:[NSArray class]]) {
        arr = (NSArray *)json;
    } else if ([json isKindOfClass:[NSDictionary class]]) {
        id origins = ((NSDictionary *)json)[@"origins"];
        if ([origins isKindOfClass:[NSArray class]]) {
            arr = origins;
        }
    }
    if (!arr) return @[];
    NSMutableArray<GZJelczPeerProviderEntry *> *out = [NSMutableArray array];
    for (id item in arr) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *rec = (NSDictionary *)item;
        NSString *type = rec[@"$type"];
        GZJelczPeerProviderEntry *e = nil;
        if ([type isEqualToString:@"place.stream.broadcast.origin"]
            || (rec[@"streamer"] && rec[@"server"] && rec[@"updatedAt"])) {
            e = [self entryFromBroadcastOriginRecord:rec];
        } else if ([type isEqualToString:@"tools.garazyk.video.origin"]
                   || (rec[@"watchBaseUrl"] && rec[@"manifestCid"])) {
            e = [self entryFromGarazykVideoOriginRecord:rec];
        } else if ([type isEqualToString:@"place.stream.media.origin"]
                   || rec[@"blob"]) {
            e = [self entryFromMediaOriginRecord:rec configuredBaseURL:configuredBaseURL];
        }
        if (e) [out addObject:e];
    }
    return [out copy];
}

+ (NSArray<NSString *> *)parseCSVBases:(NSString *)csv {
    if (csv.length == 0) return nil;
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *part in [csv componentsSeparatedByString:@","]) {
        NSString *t = [part stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *norm = [GZJelczStreamplaceOriginHints normalizedProviderBaseURL:t];
        if (norm) [out addObject:norm];
    }
    return out.count > 0 ? [out copy] : nil;
}

@end
