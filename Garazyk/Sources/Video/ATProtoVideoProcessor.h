// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoVideoProcessor.h

 @abstract Adapter that wraps video processing singletons into @c ATProtoMediaProcessor.
 */

#import <Foundation/Foundation.h>
#import "MediaCore/ATProtoMediaProcessor.h"

@protocol PDSBlobProvider;
@class ATProtoCAObjectStore;
@class ATProtoCAObjectLifecycle;

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Pipeline adapter that conforms to @c ATProtoMediaProcessor for video media.
 *
 * @discussion Wraps the existing video transcoder, thumbnail generator, and HLS
 * generator singletons into the framework's generic processor protocol.
 *
 * The @c did, @c blobCid, and @c blobProvider properties must be set by the
 * caller before invoking @c processMediaAtURL:outputDirectory:progressBlock:completion:
 * — they are needed for HLS output path construction and thumbnail storage.
 */
@interface ATProtoVideoProcessor : NSObject <ATProtoMediaProcessor>

/// DID of the media owner (set by worker before processing).
@property (nonatomic, copy, nullable) NSString *did;

/// ATProtoCID of the original source blob (set by worker before processing).
@property (nonatomic, copy, nullable) NSString *blobCid;

/// Blob provider for thumbnail storage (propagated to video singletons).
@property (nonatomic, strong, nullable) id<PDSBlobProvider> blobProvider;

/// Base URL for HLS playlist URLs (e.g. "http://localhost:2586").
@property (nonatomic, copy, nullable) NSString *outputBaseUrl;

/// Whether to include a 1080p HLS variant (default NO).
@property (nonatomic, assign) BOOL include1080p;

/**
 Whether to build a content-addressed VOD MASL manifest after HLS (WS12 Phase 3).

 Defaults to NO. When YES, @c caObjectStore must be set.
 */
@property (nonatomic, assign) BOOL enableContentAddressedManifest;

/**
 Whether to package each HLS variant into MUXL segments / presentations after
 HLS succeeds (WS10 Phase 9).

 Defaults to NO. When YES, writes a @c muxl/ subdirectory beside each variant's
 CMAF files without altering the HLS playlists or segments.
 */
@property (nonatomic, assign) BOOL enableMUXLPresentation;

/// CA object store used when @c enableContentAddressedManifest is YES.
@property (nonatomic, strong, nullable) ATProtoCAObjectStore *caObjectStore;

/// Optional lifecycle tracker; when set, successful manifests are published for reclaim.
@property (nonatomic, strong, nullable) ATProtoCAObjectLifecycle *caObjectLifecycle;

@end

NS_ASSUME_NONNULL_END
