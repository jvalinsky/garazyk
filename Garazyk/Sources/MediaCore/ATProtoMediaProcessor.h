// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoMediaProcessor.h

 @abstract Domain-specific media processing pipeline protocol.

 @discussion Implementations encapsulate transcoding, thumbnailing, and other
 domain-specific logic. The framework calls @c processMediaAtURL:outputDirectory:
 to run the pipeline and reads @c mediaTypeIdentifier / @c canProcessMimeType:
 for routing.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Protocol for domain-specific media processing pipelines (e.g. video, audio, 3D splats).
 */
@protocol ATProtoMediaProcessor <NSObject>

@required

/**
 * @abstract Unique identifier for this media pipeline (e.g. @"app.bsky.video").
 */
@property (nonatomic, readonly) NSString *mediaTypeIdentifier;

/**
 * @abstract Returns whether this processor can handle the given MIME type.
 */
- (BOOL)canProcessMimeType:(NSString *)mimeType;

/**
 * @abstract Asynchronously processes a local file, writing output assets to the specified directory.
 *
 * @param inputURL        Local source file URL.
 * @param outputDirectory Directory to which assets (transcoded files, playlists, thumbnails) are written.
 * @param progressBlock   Optional block invoked with progress updates (0.0 – 1.0).
 * @param completion      Completion block. The @c results dictionary may contain:
 *                        - @c @"processedCid" : NSString (CID of main output blob)
 *                        - @c @"thumbnailCid" : NSString? (CID of thumbnail blob)
 *                        - @c @"metadata"     : NSDictionary? (arbitrary key-value metadata)
 */
- (void)processMediaAtURL:(NSURL *)inputURL
          outputDirectory:(NSString *)outputDirectory
            progressBlock:(nullable void (^)(float progress))progressBlock
               completion:(void (^)(NSDictionary<NSString *, id> *_Nullable results,
                                    NSError *_Nullable error))completion;

@optional

/**
 * @abstract Security gate: validates that raw data matches the declared media container signatures.
 *
 * @param data          Raw bytes from the upload.
 * @param declaredMime  The MIME type claimed by the client.
 * @return YES if the content passes signature validation.
 */
- (BOOL)validateContentSignature:(NSData *)data declaredMimeType:(NSString *)declaredMime;

@end

NS_ASSUME_NONNULL_END
