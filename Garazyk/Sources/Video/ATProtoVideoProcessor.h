// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoVideoProcessor.h

 @abstract Adapter that wraps video processing singletons into @c ATProtoMediaProcessor.
 */

#import <Foundation/Foundation.h>
#import "MediaCore/ATProtoMediaProcessor.h"

@protocol PDSBlobProvider;

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

/// CID of the original source blob (set by worker before processing).
@property (nonatomic, copy, nullable) NSString *blobCid;

/// Blob provider for thumbnail storage (propagated to video singletons).
@property (nonatomic, strong, nullable) id<PDSBlobProvider> blobProvider;

/// Base URL for HLS playlist URLs (e.g. "http://localhost:2586").
@property (nonatomic, copy, nullable) NSString *outputBaseUrl;

/// Whether to include a 1080p HLS variant (default NO).
@property (nonatomic, assign) BOOL include1080p;

@end

NS_ASSUME_NONNULL_END
