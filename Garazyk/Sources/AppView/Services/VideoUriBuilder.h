// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Constructs AppView playlist and thumbnail URLs for video embeds.
 * @discussion Self-hosted deployments typically point these URLs at the configured Jelcz video service.
 */
@interface AppViewVideoUriBuilder : NSObject

/** Base URL of the video service, such as http://localhost:2586 for Jelcz. */
@property (nonatomic, copy) NSString *videoServiceURL;

/** Pattern for playlist URLs. Supports {videoServiceURL}, {did}, and {cid}. */
@property (nonatomic, copy) NSString *playlistUrlPattern;

/** Pattern for thumbnail URLs. Supports {videoServiceURL}, {did}, and {cid}. */
@property (nonatomic, copy) NSString *thumbnailUrlPattern;

/**
 * @abstract Creates a builder for the supplied video service base URL.
 */
+ (instancetype)builderWithVideoServiceURL:(NSString *)videoServiceURL;

/**
 * @abstract Constructs the HLS playlist URL for a video blob.
 */
- (NSString *)playlistURLForDID:(NSString *)did cid:(NSString *)cid;

/**
 * @abstract Constructs the thumbnail URL for a video blob.
 */
- (NSString *)thumbnailURLForDID:(NSString *)did cid:(NSString *)cid;

/**
 * @abstract Converts an app.bsky.embed.video record into a view with media URLs.
 */
- (nullable NSDictionary *)videoViewFromEmbed:(NSDictionary *)embedRecord did:(NSString *)did;

@end

NS_ASSUME_NONNULL_END
