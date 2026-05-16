// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Video/VideoBlobUploader.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Implementation of VideoBlobUploader for remote PDS blob services.
 */
@interface VideoRemoteBlobUploader : NSObject <VideoBlobUploader>

/**
 * @abstract The base URL of the remote PDS blob service.
 */
@property (nonatomic, copy, readonly) NSString *pdsURL;

/**
 * @abstract Initializes a new remote blob uploader.
 * @param pdsURL The base URL for the PDS blob service.
 */
- (instancetype)initWithPDSURL:(NSString *)pdsURL;

@end

NS_ASSUME_NONNULL_END
