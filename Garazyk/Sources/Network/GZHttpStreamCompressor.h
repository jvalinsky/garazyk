// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZHttpStreamCompressor.h

 @abstract Opaque streaming compressor for one HTTP response body.
 */

#import <Foundation/Foundation.h>
#import "Network/GZHttpContentEncoding.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @class GZHttpStreamCompressor

 @abstract Owns one zstd or gzip stream context for incremental compression.

 @discussion Pull-thread only: create, then compressChunk:/finish: from a
 single response send path. Default compression level is 3 for both backends.
 */
@interface GZHttpStreamCompressor : NSObject

- (nullable instancetype)initWithEncoding:(GZHttpContentEncoding)encoding
                                    error:(NSError * _Nullable * _Nullable)error NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly, assign) GZHttpContentEncoding encoding;

/*! Compress one input chunk. May return empty NSData if the backend buffered. */
- (nullable NSData *)compressChunk:(NSData *)input
                             error:(NSError * _Nullable * _Nullable)error;

/*! Flush end-of-stream trailer. Call once after the last input chunk. */
- (nullable NSData *)finishWithError:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
