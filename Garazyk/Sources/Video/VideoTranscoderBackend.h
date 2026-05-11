// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ATProtoVideoTranscoderQuality) {
    ATProtoVideoTranscoderQuality480p = 0,
    ATProtoVideoTranscoderQuality720p = 1,
    ATProtoVideoTranscoderQuality1080p = 2,
    ATProtoVideoTranscoderQualityHEVC = 3,
};

@protocol VideoTranscoderBackend <NSObject>

- (void)transcodeVideoAtURL:(NSURL *)inputURL
                  toQuality:(ATProtoVideoTranscoderQuality)quality
                  outputURL:(nullable NSURL *)outputURL
                   progress:(nullable void (^)(float progress))progressBlock
                 completion:(void (^)(NSURL * _Nullable outputURL, NSError * _Nullable error))completion;

- (void)cancelAllExports;

@end

NS_ASSUME_NONNULL_END
