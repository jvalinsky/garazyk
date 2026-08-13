// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoVideoPrefetchBootstrap.h

 @abstract Short-form feed prefetch bootstrap contract (WS12 Phase 8 / ADR 0037).

 @discussion Collapses the per-item record → manifest → first-segment discovery
 chain into one response of playbackBootstrap items. Tracks a prefetch-waste
 ceiling alongside startup-stall (discovery RTT) savings.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** Default next-N window for short-form feed prefetch. */
FOUNDATION_EXPORT NSInteger const ATProtoVideoPrefetchDefaultWindowSize;

/** Per-item first-segment byte budget used when callers omit firstSegmentBytes. */
FOUNDATION_EXPORT NSUInteger const ATProtoVideoPrefetchDefaultFirstSegmentBytes;

/**
 Hard ceiling on bytes a client may prefetch for the whole window when every
 item is swiped past unplayed. Equals default window × default first-segment
 budget (2 × 512 KiB = 1 MiB).
 */
FOUNDATION_EXPORT NSUInteger const ATProtoVideoPrefetchWasteCeilingBytes;

/** Discovery RTTs in the naive per-item chain (record, manifest, first-seg meta). */
FOUNDATION_EXPORT NSInteger const ATProtoVideoPrefetchNaiveDiscoveryRTTsPerItem;

FOUNDATION_EXPORT NSErrorDomain const ATProtoVideoPrefetchBootstrapErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoVideoPrefetchBootstrapErrorCode) {
    ATProtoVideoPrefetchBootstrapErrorInvalidArgument = 1,
    ATProtoVideoPrefetchBootstrapErrorWindowExceeded = 2,
};

/**
 Builds @c xyz.garazyk.video.getPrefetchBootstrap response dictionaries from
 already-resolved bootstrap item dictionaries (AppView / edge hydrates inputs).
 */
@interface ATProtoVideoPrefetchBootstrap : NSObject

/**
 Builds a getPrefetchBootstrap output object.

 @param items Ordered dictionaries matching
        @c tools.garazyk.video.defs#playbackBootstrap required fields
        (@c uri, @c cid, @c manifestCid). Optional prefetch fields are passed through.
 @param maxWindow Maximum items to include (clamped to
        @c ATProtoVideoPrefetchDefaultWindowSize when ≤0). Hard max is 10.
 @param error On failure, set to a domain error.
 @return Response dictionary with @c items, @c windowSize, @c wasteCeilingBytes,
         or nil.
 */
+ (nullable NSDictionary *)responseForItems:(NSArray<NSDictionary *> *)items
                                  maxWindow:(NSInteger)maxWindow
                                      error:(NSError **)error;

/**
 Bytes that would be wasted if @c playedCount of the window's items are actually
 watched (rest swiped past after prefetching each item's firstSegmentBytes).
 */
+ (NSUInteger)prefetchWasteBytesForItems:(NSArray<NSDictionary *> *)items
                             playedCount:(NSUInteger)playedCount;

/**
 Discovery RTT count for playing @c playCount consecutive items.

 Naive path: @c playCount × @c ATProtoVideoPrefetchNaiveDiscoveryRTTsPerItem.
 Bootstrap path: 1 (bootstrap query) + 0 additional discovery RTTs per item
 (bytes still need fetch RTTs; this models only the discovery chain).
 */
+ (NSInteger)discoveryRTTCountForPlayCount:(NSInteger)playCount
                            usingBootstrap:(BOOL)usingBootstrap;

@end

NS_ASSUME_NONNULL_END
