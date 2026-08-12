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
@interface GZVideoHLSResult : NSObject

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

/**
 * @abstract Every file this generation run produced, keyed by its bundle-relative
 * path and mapped to the file's absolute on-disk location.
 * @discussion Keys mirror the MASL bundle root convention a later phase will use to
 * content-address this tree: @"/" is the master playlist, @"/{variant}/video.m3u8"
 * is a variant playlist, @"/{variant}/init.mp4" is that variant's fMP4 init
 * segment, and @"/{variant}/segment_NNNNN.m4s" is each media segment actually
 * written to disk. The dictionary is fully populated by the time
 * -generateHLSFromVideoAtURL:did:cid:thumbnailData:error: returns, so a caller can
 * enumerate every produced file directly from this property without re-scanning
 * the output directory (e.g. to walk the tree for content-addressing). Segment
 * entries reflect what ffmpeg actually wrote, not a computed count, so the map is
 * accurate even if generation stops early.
 */
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *producedFiles;

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
 * @param cid ATProtoCID of the original video blob.
 * @param thumbnailData Optional thumbnail JPEG data to store alongside HLS.
 * @param error On failure, contains the error.
 * @return GZVideoHLSResult with paths to generated files, or nil on failure.
 */
- (nullable GZVideoHLSResult *)generateHLSFromVideoAtURL:(NSURL *)inputURL
                                                    did:(NSString *)did
                                                    cid:(NSString *)cid
                                          thumbnailData:(nullable NSData *)thumbnailData
                                                  error:(NSError **)error;

/**
 * @abstract Remove all HLS files for a given DID+ATProtoCID.
 */
- (void)removeHLSForDID:(NSString *)did cid:(NSString *)cid;

/**
 * @abstract Get the file system path for the HLS directory of a DID+ATProtoCID.
 */
- (NSString *)hlsDirectoryForDID:(NSString *)did cid:(NSString *)cid;

/**
 * @abstract Get the file system path for the master playlist of a DID+ATProtoCID.
 */
- (NSString *)masterPlaylistPathForDID:(NSString *)did cid:(NSString *)cid;

/**
 * @abstract Get the file system path for the thumbnail of a DID+ATProtoCID.
 */
- (NSString *)thumbnailPathForDID:(NSString *)did cid:(NSString *)cid;

@end

NS_ASSUME_NONNULL_END
