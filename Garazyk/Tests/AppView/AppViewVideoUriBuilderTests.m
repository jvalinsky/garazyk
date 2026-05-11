// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "AppView/Services/VideoUriBuilder.h"

@interface AppViewVideoUriBuilderTests : XCTestCase
@property (nonatomic, strong) AppViewVideoUriBuilder *builder;
@end

@implementation AppViewVideoUriBuilderTests

- (void)setUp {
    [super setUp];
    self.builder = [AppViewVideoUriBuilder builderWithVideoServiceURL:@"http://localhost:2586"];
}

#pragma mark - URL Construction

- (void)testPlaylistURL {
    NSString *url = [self.builder playlistURLForDID:@"did:plc:abc123" cid:@"bafyrei456"];
    XCTAssertEqualObjects(url, @"http://localhost:2586/watch/did:plc:abc123/bafyrei456/playlist.m3u8");
}

- (void)testThumbnailURL {
    NSString *url = [self.builder thumbnailURLForDID:@"did:plc:abc123" cid:@"bafyrei456"];
    XCTAssertEqualObjects(url, @"http://localhost:2586/watch/did:plc:abc123/bafyrei456/thumbnail.jpg");
}

- (void)testCustomPlaylistPattern {
    self.builder.playlistUrlPattern = @"{videoServiceURL}/vid/{did}/{cid}/playlist.m3u8";
    NSString *url = [self.builder playlistURLForDID:@"did:plc:abc" cid:@"bafyrei123"];
    XCTAssertEqualObjects(url, @"http://localhost:2586/vid/did:plc:abc/bafyrei123/playlist.m3u8");
}

- (void)testCustomThumbnailPattern {
    self.builder.thumbnailUrlPattern = @"{videoServiceURL}/vid/{did}/{cid}/thumb.jpg";
    NSString *url = [self.builder thumbnailURLForDID:@"did:plc:abc" cid:@"bafyrei123"];
    XCTAssertEqualObjects(url, @"http://localhost:2586/vid/did:plc:abc/bafyrei123/thumb.jpg");
}

#pragma mark - Video View Generation

- (void)testVideoViewFromEmbed {
    NSDictionary *embed = @{
        @"$type": @"app.bsky.embed.video",
        @"video": @{@"ref": @{@"$link": @"bafyrei123"}, @"mimeType": @"video/mp4"},
        @"aspectRatio": @{@"width": @16, @"height": @9}
    };

    NSDictionary *view = [self.builder videoViewFromEmbed:embed did:@"did:plc:abc"];
    XCTAssertNotNil(view);
    XCTAssertEqualObjects(view[@"$type"], @"app.bsky.embed.video#view");
    XCTAssertEqualObjects(view[@"cid"], @"bafyrei123");
    XCTAssertEqualObjects(view[@"playlist"], @"http://localhost:2586/watch/did:plc:abc/bafyrei123/playlist.m3u8");
    XCTAssertNotNil(view[@"aspectRatio"]);
}

- (void)testVideoViewFromEmbedWithThumbnail {
    NSDictionary *embed = @{
        @"$type": @"app.bsky.embed.video",
        @"video": @{@"ref": @{@"$link": @"bafyrei123"}, @"mimeType": @"video/mp4"},
        @"thumbnail": @{@"ref": @{@"$link": @"bafyreithumb"}}
    };

    NSDictionary *view = [self.builder videoViewFromEmbed:embed did:@"did:plc:abc"];
    XCTAssertNotNil(view);
    XCTAssertEqualObjects(view[@"thumbnail"], @"http://localhost:2586/watch/did:plc:abc/bafyreithumb/thumbnail.jpg");
}

- (void)testVideoViewFromEmbedNilReturnsNil {
    NSDictionary *view = [self.builder videoViewFromEmbed:nil did:@"did:plc:abc"];
    XCTAssertNil(view);
}

- (void)testVideoViewFromEmbedNilDIDReturnsNil {
    NSDictionary *embed = @{@"$type": @"app.bsky.embed.video"};
    NSDictionary *view = [self.builder videoViewFromEmbed:embed did:nil];
    XCTAssertNil(view);
}

- (void)testVideoViewFromNonVideoEmbedReturnsNil {
    NSDictionary *embed = @{@"$type": @"app.bsky.embed.images"};
    NSDictionary *view = [self.builder videoViewFromEmbed:embed did:@"did:plc:abc"];
    XCTAssertNil(view);
}

- (void)testVideoViewFromEmbedWithoutVideoReturnsNil {
    NSDictionary *embed = @{@"$type": @"app.bsky.embed.video"};
    NSDictionary *view = [self.builder videoViewFromEmbed:embed did:@"did:plc:abc"];
    XCTAssertNil(view);
}

#pragma mark - Builder Factory

- (void)testBuilderWithVideoServiceURL {
    AppViewVideoUriBuilder *b = [AppViewVideoUriBuilder builderWithVideoServiceURL:@"https://video.example.com"];
    XCTAssertEqualObjects(b.videoServiceURL, @"https://video.example.com");
    XCTAssertNotNil(b.playlistUrlPattern);
    XCTAssertNotNil(b.thumbnailUrlPattern);
}

@end
