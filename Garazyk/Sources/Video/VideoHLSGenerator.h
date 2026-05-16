// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Error domain for HLS generation operations.
 */
extern NSString * const ATProtoVideoHLSGeneratorErrorDomain;

/**
 * @abstract Error codes for HLS generation.
 */
typedef NS_ENUM(NSInteger, ATProtoVideoHLSError) {
    ATProtoVideoHLSErrorFFmpegNotFound = 1,
    ATProtoVideoHLSErrorFFmpegLaunchFailed = 2,
    ATProtoVideoHLSErrorFFmpegFailed = 3,
    ATProtoVideoHLSErrorOutputDirectoryFailed = 4,
    ATProtoVideoHLSErrorInvalidInput = 5,
};

/**
 * @abstract Result of HLS generation.
 * @discussion Contains paths to the master playlist and all variant assets.
 */
@interface VideoHLSResult : NSObject

/**
 * @abstract Path to the master playlist (e.g. /hls/{did}/{cid}/playlist.m3u8).
 */
@property (nonatomic, copy) NSString *masterPlaylistPath;

/**
 * @abstract Relative URL path for the master playlist (e.g. /watch/{did}/{cid}/playlist.m3u8).
 */
@property (nonatomic, copy) NSString *masterPlaylistRelativePath;

/**
 * @abstract Array of variant info dictionaries.
 * @discussion Keys: @"resolution", @"bandwidth", @"playlistPath".
 */
@property (nonatomic, copy) NSArray<NSDictionary *> *variants;

/**
 * @abstract Path to the thumbnail JPEG file, if generated.
 */
@property (nonatomic, copy, nullable) NSString *thumbnailPath;

@end

/**
 * @abstract Generates HLS (HTTP Live Streaming) segments and playlists from a video file.
 * @discussion Produces multi-variant HLS with 360p and 720p (and optionally 1080p) resolutions.
 */
@interface ATProtoVideoHLSGenerator : NSObject

/**
 * @abstract Path to the ffmpeg binary.
 * @discussion Defaults to "ffmpeg" (looked up via PATH).
 */
@property (nonatomic, copy) NSString *ffmpegPath;

/**
 * @abstract Base directory for HLS output.
 * @discussion Defaults to a subdirectory of the system temp dir.
 */
@property (nonatomic, copy) NSString *outputBaseDirectory;

/**
 * @abstract Whether to include a 1080p variant.
 * @discussion Default: NO, matching Bluesky reference CDN.
 */
@property (nonatomic, assign) BOOL include1080p;

/**
 * @abstract Returns the singleton instance of the HLS generator.
 */
+ (instancetype)sharedGenerator;

/**
 * @abstract Generate HLS segments and playlists from a video file.
 * @param inputURL URL to the source video file (typically the transcoded MP4).
 * @param did DID of the video owner.
 * @param cid CID of the original video blob.
 * @param thumbnailData Optional thumbnail JPEG data to store alongside HLS.
 * @param error On failure, contains the error.
 * @return VideoHLSResult with paths to generated files, or nil on failure.
 */
- (nullable VideoHLSResult *)generateHLSFromVideoAtURL:(NSURL *)inputURL
                                                    did:(NSString *)did
                                                    cid:(NSString *)cid
                                          thumbnailData:(nullable NSData *)thumbnailData
                                                  error:(NSError **)error;

/**
 * @abstract Remove all HLS files for a given DID+CID.
 */
- (void)removeHLSForDID:(NSString *)did cid:(NSString *)cid;

/**
 * @abstract Get the file system path for the HLS directory of a DID+CID.
 */
- (NSString *)hlsDirectoryForDID:(NSString *)did cid:(NSString *)cid;

/**
 * @abstract Get the file system path for the master playlist of a DID+CID.
 */
- (NSString *)masterPlaylistPathForDID:(NSString *)did cid:(NSString *)cid;

/**
 * @abstract Get the file system path for the thumbnail of a DID+CID.
 */
- (NSString *)thumbnailPathForDID:(NSString *)did cid:(NSString *)cid;

@end

NS_ASSUME_NONNULL_END
