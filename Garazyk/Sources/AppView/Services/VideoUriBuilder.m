// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AppView/Services/VideoUriBuilder.h"

@implementation AppViewVideoUriBuilder

+ (instancetype)builderWithVideoServiceURL:(NSString *)videoServiceURL {
    AppViewVideoUriBuilder *builder = [[AppViewVideoUriBuilder alloc] init];
    builder.videoServiceURL = videoServiceURL;
    builder.playlistUrlPattern = @"{videoServiceURL}/watch/{did}/{cid}/playlist.m3u8";
    builder.thumbnailUrlPattern = @"{videoServiceURL}/watch/{did}/{cid}/thumbnail.jpg";
    return builder;
}

- (NSString *)playlistURLForDID:(NSString *)did cid:(NSString *)cid {
    NSString *url = [self.playlistUrlPattern copy];
    url = [url stringByReplacingOccurrencesOfString:@"{videoServiceURL}" withString:self.videoServiceURL];
    url = [url stringByReplacingOccurrencesOfString:@"{did}" withString:did];
    url = [url stringByReplacingOccurrencesOfString:@"{cid}" withString:cid];
    return url;
}

- (NSString *)thumbnailURLForDID:(NSString *)did cid:(NSString *)cid {
    NSString *url = [self.thumbnailUrlPattern copy];
    url = [url stringByReplacingOccurrencesOfString:@"{videoServiceURL}" withString:self.videoServiceURL];
    url = [url stringByReplacingOccurrencesOfString:@"{did}" withString:did];
    url = [url stringByReplacingOccurrencesOfString:@"{cid}" withString:cid];
    return url;
}

- (nullable NSDictionary *)videoViewFromEmbed:(NSDictionary *)embedRecord did:(NSString *)did {
    if (!embedRecord || !did) return nil;

    NSString *embedType = embedRecord[@"$type"];
    if (![embedType isEqualToString:@"app.bsky.embed.video"]) return nil;

    // Extract the video blob CID from the embed record
    NSDictionary *video = embedRecord[@"video"];
    if (!video) return nil;

    NSDictionary *blobRef = video[@"ref"];
    NSString *cid = blobRef[@"$link"];
    if (!cid) {
        // Try alternate format
        cid = video[@"cid"];
    }
    if (!cid) return nil;

    // Extract aspect ratio if present
    NSDictionary *aspectRatio = embedRecord[@"aspectRatio"];
    NSNumber *width = aspectRatio[@"width"];
    NSNumber *height = aspectRatio[@"height"];

    // Construct the view
    NSMutableDictionary *view = [NSMutableDictionary dictionary];
    view[@"$type"] = @"app.bsky.embed.video#view";

    // Add the CID reference
    view[@"cid"] = cid;

    // Add playlist URL
    view[@"playlist"] = [self playlistURLForDID:did cid:cid];

    // Add thumbnail URL
    NSString *thumbnailCid = embedRecord[@"thumbnail"][@"ref"][@"$link"];
    if (thumbnailCid) {
        view[@"thumbnail"] = [self thumbnailURLForDID:did cid:thumbnailCid];
    }

    // Add aspect ratio if present
    if (width && height) {
        view[@"aspectRatio"] = @{@"width": width, @"height": height};
    }

    return [view copy];
}

@end
