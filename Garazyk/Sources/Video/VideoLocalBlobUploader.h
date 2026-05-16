// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Video/VideoBlobUploader.h"
#import "Blob/PDSBlobProvider.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Implementation of VideoBlobUploader for local PDS blob storage.
 */
@interface VideoLocalBlobUploader : NSObject <VideoBlobUploader>

/**
 * @abstract The local blob provider instance.
 */
@property (nonatomic, strong, readonly) id<PDSBlobProvider> blobProvider;

/**
 * @abstract Initializes a new local blob uploader.
 * @param blobProvider The local PDS blob provider.
 */
- (instancetype)initWithBlobProvider:(id<PDSBlobProvider>)blobProvider;

@end

NS_ASSUME_NONNULL_END
