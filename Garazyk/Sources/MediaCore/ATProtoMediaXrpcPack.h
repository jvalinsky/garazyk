// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoMediaXrpcPack.h

 @abstract Parameterized XRPC route pack for media CDN services.
 */

#import <Foundation/Foundation.h>
#import "Network/XrpcRoutePack.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Registers standard media service XRPC routes (upload, job status, limits).
 *
 * @discussion This route pack is parameterized with a method-mapping dictionary
 * so that a single class can serve video (app.bsky.video.*), audio
 * (app.bsky.audio.*), or other media lexicons without subclassing.
 *
 * Method mapping example:
 * @code
 * @{
 *   @"upload":      @"app.bsky.video.uploadVideo",
 *   @"getJobStatus": @"app.bsky.video.getJobStatus",
 *   @"getUploadLimits": @"app.bsky.video.getUploadLimits",
 * }
 * @endcode
 */
@interface ATProtoMediaXrpcPack : NSObject <XrpcRoutePack>

/// Dictionary mapping endpoint keys (@"upload", @"getJobStatus", @"getUploadLimits") to NSID strings.
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *methodMappings;

/// Validates that raw data matches the declared media container signature.
@property (nonatomic, copy, nullable) BOOL (^contentValidator)(NSData *data, NSString *mimeType);

- (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                      services:(id<XrpcRoutePackServices>)services;

- (NSDictionary *)formatJobResponse:(NSDictionary *)job;

@end

NS_ASSUME_NONNULL_END
