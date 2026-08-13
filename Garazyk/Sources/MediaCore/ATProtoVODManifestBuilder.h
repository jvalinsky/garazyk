// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoVODManifestBuilder.h

 @abstract Assembles flat-VOD CA objects + MASL/DRISL manifest (WS12 Phase 3 / ADR 0036).

 @discussion Consumes an HLS generator @c producedFiles map (or in-memory
 path→data fixture), concatenates each variant's init+segments into one
 range-addressable fMP4, stores media under BLAKE3 CIDs with outboard proofs,
 stores playlists under SHA-256 CIDs, and encodes a MASL bundle whose resources
 name those objects. Fragment offset tables are retained in application
 metadata for HLS @c EXT-X-BYTERANGE emission.
 */

#import <Foundation/Foundation.h>

@class ATProtoCID;
@class ATProtoMASLDocument;
@class ATProtoCAObjectStore;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const ATProtoVODManifestBuilderErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoVODManifestBuilderErrorCode) {
    ATProtoVODManifestBuilderErrorInvalidArgument = 1,
    ATProtoVODManifestBuilderErrorMissingAsset = 2,
    ATProtoVODManifestBuilderErrorStore = 3,
    ATProtoVODManifestBuilderErrorManifest = 4,
};

/** Result of a successful VOD manifest build. */
@interface ATProtoVODManifestBuildResult : NSObject

/** Validated MASL bundle document. */
@property (nonatomic, strong, readonly) ATProtoMASLDocument *document;
/** DRISL-encoded manifest bytes (the future atproto blob payload). */
@property (nonatomic, copy, readonly) NSData *drislData;
/** Bundle path → stored object CID. */
@property (nonatomic, copy, readonly) NSDictionary<NSString *, ATProtoCID *> *resourceCIDs;
/**
 Per flat media path, ordered fragment descriptors:
 each entry is @{ @"name", @"offset", @"length" }.
 */
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSArray<NSDictionary<NSString *, id> *> *> *fragmentTables;

@end

/**
 Builds content-addressed VOD objects and a MASL manifest from an HLS tree.
 */
@interface ATProtoVODManifestBuilder : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/**
 Builds from absolute on-disk paths (as produced by @c GZVideoHLSResult.producedFiles).
 */
+ (nullable ATProtoVODManifestBuildResult *)buildFromProducedFiles:(NSDictionary<NSString *, NSString *> *)producedFiles
                                                            store:(ATProtoCAObjectStore *)store
                                                            error:(NSError **)error;

/**
 Builds from in-memory path→bytes (unit fixtures; no filesystem walk).
 */
+ (nullable ATProtoVODManifestBuildResult *)buildFromProducedData:(NSDictionary<NSString *, NSData *> *)producedData
                                                           store:(ATProtoCAObjectStore *)store
                                                           error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
