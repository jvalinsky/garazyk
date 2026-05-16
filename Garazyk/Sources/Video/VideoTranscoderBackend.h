// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Supported transcoding output qualities.
 */
typedef NS_ENUM(NSInteger, ATProtoVideoTranscoderQuality) {
    ATProtoVideoTranscoderQuality480p = 0,
    ATProtoVideoTranscoderQuality720p = 1,
    ATProtoVideoTranscoderQuality1080p = 2,
    ATProtoVideoTranscoderQualityHEVC = 3,
};

/**
 * @abstract Interface for video transcoding backends.
 */
@protocol VideoTranscoderBackend <NSObject>

/**
 * @abstract Asynchronously transcode a video.
 * @param inputURL Source video URL.
 * @param quality Target transcoding quality.
 * @param outputURL Optional custom output URL.
 * @param progressBlock Progress monitoring block.
 * @param completion Completion handler.
 */
- (void)transcodeVideoAtURL:(NSURL *)inputURL
                  toQuality:(ATProtoVideoTranscoderQuality)quality
                  outputURL:(nullable NSURL *)outputURL
                   progress:(nullable void (^)(float progress))progressBlock
                 completion:(void (^)(NSURL * _Nullable outputURL, NSError * _Nullable error))completion;

/**
 * @abstract Cancels all active transcoding operations.
 */
- (void)cancelAllExports;

@end

NS_ASSUME_NONNULL_END
