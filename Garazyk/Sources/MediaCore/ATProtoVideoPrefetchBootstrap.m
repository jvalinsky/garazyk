// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "MediaCore/ATProtoVideoPrefetchBootstrap.h"

NSInteger const ATProtoVideoPrefetchDefaultWindowSize = 2;
NSUInteger const ATProtoVideoPrefetchDefaultFirstSegmentBytes = 512ULL * 1024ULL;
NSUInteger const ATProtoVideoPrefetchWasteCeilingBytes =
    2ULL * 512ULL * 1024ULL; // window × first-segment budget
NSInteger const ATProtoVideoPrefetchNaiveDiscoveryRTTsPerItem = 3;

NSErrorDomain const ATProtoVideoPrefetchBootstrapErrorDomain =
    @"ATProtoVideoPrefetchBootstrapErrorDomain";

@implementation ATProtoVideoPrefetchBootstrap

+ (NSUInteger)firstSegmentBytesForItem:(NSDictionary *)item {
    id value = item[@"firstSegmentBytes"];
    if ([value isKindOfClass:[NSNumber class]]) {
        NSInteger n = [(NSNumber *)value integerValue];
        if (n > 0) {
            return (NSUInteger)n;
        }
    }
    return ATProtoVideoPrefetchDefaultFirstSegmentBytes;
}

+ (nullable NSDictionary *)responseForItems:(NSArray<NSDictionary *> *)items
                                  maxWindow:(NSInteger)maxWindow
                                      error:(NSError **)error {
    if (![items isKindOfClass:[NSArray class]] || items.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoVideoPrefetchBootstrapErrorDomain
                                         code:ATProtoVideoPrefetchBootstrapErrorInvalidArgument
                                     userInfo:@{
                                         NSLocalizedDescriptionKey:
                                             @"uris/items must be a non-empty array"
                                     }];
        }
        return nil;
    }

    NSInteger window = maxWindow;
    if (window <= 0) {
        window = ATProtoVideoPrefetchDefaultWindowSize;
    }
    if (window > 10) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoVideoPrefetchBootstrapErrorDomain
                                         code:ATProtoVideoPrefetchBootstrapErrorWindowExceeded
                                     userInfo:@{
                                         NSLocalizedDescriptionKey:
                                             @"maxWindow cannot exceed 10"
                                     }];
        }
        return nil;
    }

    NSUInteger take = MIN((NSUInteger)window, items.count);
    NSMutableArray<NSDictionary *> *outItems =
        [NSMutableArray arrayWithCapacity:take];
    NSUInteger wasteCeiling = 0;

    for (NSUInteger i = 0; i < take; i++) {
        NSDictionary *raw = items[i];
        if (![raw isKindOfClass:[NSDictionary class]]) {
            if (error) {
                *error = [NSError errorWithDomain:ATProtoVideoPrefetchBootstrapErrorDomain
                                             code:ATProtoVideoPrefetchBootstrapErrorInvalidArgument
                                         userInfo:@{
                                             NSLocalizedDescriptionKey:
                                                 @"each item must be a dictionary"
                                         }];
            }
            return nil;
        }
        NSString *uri = raw[@"uri"];
        NSString *cid = raw[@"cid"];
        NSString *manifestCid = raw[@"manifestCid"];
        if (![uri isKindOfClass:[NSString class]] || uri.length == 0 ||
            ![cid isKindOfClass:[NSString class]] || cid.length == 0 ||
            ![manifestCid isKindOfClass:[NSString class]] ||
            manifestCid.length == 0) {
            if (error) {
                *error = [NSError errorWithDomain:ATProtoVideoPrefetchBootstrapErrorDomain
                                             code:ATProtoVideoPrefetchBootstrapErrorInvalidArgument
                                         userInfo:@{
                                             NSLocalizedDescriptionKey:
                                                 @"uri, cid, and manifestCid are required"
                                         }];
            }
            return nil;
        }

        NSMutableDictionary *item = [NSMutableDictionary dictionaryWithDictionary:raw];
        NSUInteger segBytes = [self firstSegmentBytesForItem:raw];
        item[@"firstSegmentBytes"] = @(segBytes);
        // Clamp per-item contribution so a single oversized declaration cannot
        // blow the window waste ceiling.
        NSUInteger clamped = MIN(segBytes, ATProtoVideoPrefetchDefaultFirstSegmentBytes);
        wasteCeiling += clamped;
        [outItems addObject:[item copy]];
    }

    if (wasteCeiling > ATProtoVideoPrefetchWasteCeilingBytes) {
        wasteCeiling = ATProtoVideoPrefetchWasteCeilingBytes;
    }

    return @{
        @"items": [outItems copy],
        @"windowSize": @(outItems.count),
        @"wasteCeilingBytes": @(wasteCeiling)
    };
}

+ (NSUInteger)prefetchWasteBytesForItems:(NSArray<NSDictionary *> *)items
                             playedCount:(NSUInteger)playedCount {
    if (![items isKindOfClass:[NSArray class]] || items.count == 0) {
        return 0;
    }
    NSUInteger waste = 0;
    for (NSUInteger i = 0; i < items.count; i++) {
        if (i < playedCount) {
            continue;
        }
        NSDictionary *item = items[i];
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        waste += [self firstSegmentBytesForItem:item];
    }
    return waste;
}

+ (NSInteger)discoveryRTTCountForPlayCount:(NSInteger)playCount
                            usingBootstrap:(BOOL)usingBootstrap {
    if (playCount <= 0) {
        return 0;
    }
    if (usingBootstrap) {
        // One bootstrap query covers the window; no further discovery RTTs.
        return 1;
    }
    return playCount * ATProtoVideoPrefetchNaiveDiscoveryRTTsPerItem;
}

@end
