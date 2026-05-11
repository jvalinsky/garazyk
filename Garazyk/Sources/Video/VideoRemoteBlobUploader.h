// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Video/VideoBlobUploader.h"

NS_ASSUME_NONNULL_BEGIN

@interface VideoRemoteBlobUploader : NSObject <VideoBlobUploader>

@property (nonatomic, copy, readonly) NSString *pdsURL;

- (instancetype)initWithPDSURL:(NSString *)pdsURL;

@end

NS_ASSUME_NONNULL_END
