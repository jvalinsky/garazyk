// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Video/VideoTranscoderBackend.h"

NS_ASSUME_NONNULL_BEGIN

@interface AVFoundationTranscoder : NSObject <VideoTranscoderBackend>

@end

NS_ASSUME_NONNULL_END
