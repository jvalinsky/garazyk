// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Constructs video playlist and thumbnail URLs for the AppView.
/// Mirrors Bluesky's VideoUriBuilder which constructs URLs pointing to the CDN.
/// For self-hosted PDSes, URLs point to the Jelcz video service.
@interface AppViewVideoUriBuilder : NSObject

/// Base URL of the video service (e.g. "http://localhost:2586" for Jelcz)
@property (nonatomic, copy) NSString *videoServiceURL;

/// Pattern for playlist URLs. Defaults to "{videoServiceURL}/watch/{did}/{cid}/playlist.m3u8"
/// Supports placeholders: {videoServiceURL}, {did}, {cid}
@property (nonatomic, copy) NSString *playlistUrlPattern;

/// Pattern for thumbnail URLs. Defaults to "{videoServiceURL}/watch/{did}/{cid}/thumbnail.jpg"
/// Supports placeholders: {videoServiceURL}, {did}, {cid}
@property (nonatomic, copy) NSString *thumbnailUrlPattern;

+ (instancetype)builderWithVideoServiceURL:(NSString *)videoServiceURL;

/// Construct the playlist URL for a video.
/// @param did DID of the video owner
/// @param cid CID of the video blob
/// @return Full URL to the HLS master playlist
- (NSString *)playlistURLForDID:(NSString *)did cid:(NSString *)cid;

/// Construct the thumbnail URL for a video.
/// @param did DID of the video owner
/// @param cid CID of the video blob
/// @return Full URL to the thumbnail image
- (NSString *)thumbnailURLForDID:(NSString *)did cid:(NSString *)cid;

/// Transform an app.bsky.embed.video record into a view by adding playlist and thumbnail URLs.
/// @param embedRecord The raw embed record from the PDS
/// @param did DID of the video owner
/// @return The view dictionary with playlist and thumbnail URLs added
- (nullable NSDictionary *)videoViewFromEmbed:(NSDictionary *)embedRecord did:(NSString *)did;

@end

NS_ASSUME_NONNULL_END
