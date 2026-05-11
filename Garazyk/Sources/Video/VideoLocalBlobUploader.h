// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Video/VideoBlobUploader.h"
#import "Blob/PDSBlobProvider.h"

NS_ASSUME_NONNULL_BEGIN

@interface VideoLocalBlobUploader : NSObject <VideoBlobUploader>

@property (nonatomic, strong, readonly) id<PDSBlobProvider> blobProvider;

- (instancetype)initWithBlobProvider:(id<PDSBlobProvider>)blobProvider;

@end

NS_ASSUME_NONNULL_END
