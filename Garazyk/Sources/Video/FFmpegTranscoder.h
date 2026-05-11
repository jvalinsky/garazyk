// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Video/VideoTranscoderBackend.h"

NS_ASSUME_NONNULL_BEGIN

@interface FFmpegTranscoder : NSObject <VideoTranscoderBackend>

/// Path to the ffmpeg binary. Defaults to "ffmpeg" (looked up via PATH).
@property (nonatomic, copy) NSString *ffmpegPath;

/// Path to the ffprobe binary. Defaults to "ffprobe" (looked up via PATH).
@property (nonatomic, copy) NSString *ffprobePath;

- (instancetype)initWithFFmpegPath:(nullable NSString *)ffmpegPath
                      ffprobePath:(nullable NSString *)ffprobePath;

/// Probe the duration of a video file in seconds. Returns 0 on failure.
- (float)probeDurationForVideoAtURL:(NSURL *)videoURL;

/// Probe the dimensions of a video file. Returns CGSizeZero on failure.
- (CGSize)probeDimensionsForVideoAtURL:(NSURL *)videoURL;

/// Probe the framerate of a video file. Returns 0 on failure.
- (float)probeFramerateForVideoAtURL:(NSURL *)videoURL;

@end

NS_ASSUME_NONNULL_END
