// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Video/VideoTranscoderBackend.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract FFmpeg-based video transcoder implementation.
 */
@interface FFmpegTranscoder : NSObject <VideoTranscoderBackend>

/**
 * @abstract Path to the ffmpeg binary.
 * @discussion Defaults to "ffmpeg" (looked up via PATH).
 */
@property (nonatomic, copy) NSString *ffmpegPath;

/**
 * @abstract Path to the ffprobe binary.
 * @discussion Defaults to "ffprobe" (looked up via PATH).
 */
@property (nonatomic, copy) NSString *ffprobePath;

/**
 * @abstract Initializes the transcoder with custom binary paths.
 * @param ffmpegPath Path to the ffmpeg binary.
 * @param ffprobePath Path to the ffprobe binary.
 */
- (instancetype)initWithFFmpegPath:(nullable NSString *)ffmpegPath
                      ffprobePath:(nullable NSString *)ffprobePath;

/**
 * @abstract Probes the duration of a video file.
 * @param videoURL URL to the source video.
 * @return Duration in seconds, or 0.0 on failure.
 */
- (float)probeDurationForVideoAtURL:(NSURL *)videoURL;

/**
 * @abstract Probes the dimensions of a video file.
 * @param videoURL URL to the source video.
 * @return Dimensions as CGSize, or CGSizeZero on failure.
 */
- (CGSize)probeDimensionsForVideoAtURL:(NSURL *)videoURL;

/**
 * @abstract Probes the frame rate of a video file.
 * @param videoURL URL to the source video.
 * @return Frames per second, or 0.0 on failure.
 */
- (float)probeFramerateForVideoAtURL:(NSURL *)videoURL;

@end

NS_ASSUME_NONNULL_END
