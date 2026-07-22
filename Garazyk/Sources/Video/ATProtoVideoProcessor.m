// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Video/ATProtoVideoProcessor.h"
#import "Video/VideoTranscoder.h"
#import "Video/VideoThumbnailGenerator.h"
#import "Video/VideoHLSGenerator.h"
#import "Video/VideoTranscoderBackend.h"
#import "Core/CID.h"
#import "Blob/PDSBlobProvider.h"
#import "Debug/GZLogger.h"

#if TARGET_OS_MAC
#import <AVFoundation/AVFoundation.h>
#else
#import "Video/FFmpegTranscoder.h"
#endif

@implementation ATProtoVideoProcessor

- (instancetype)init {
    self = [super init];
    if (self) {
        _include1080p = NO;
    }
    return self;
}

#pragma mark - ATProtoMediaProcessor

- (NSString *)mediaTypeIdentifier {
    return @"app.bsky.video";
}

- (BOOL)canProcessMimeType:(NSString *)mimeType {
    static NSSet<NSString *> *supportedTypes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        supportedTypes = [NSSet setWithObjects:
            @"video/mp4",
            @"video/quicktime",
            @"video/x-m4v",
            @"video/webm",
            @"video/x-msvideo",
            @"video/3gpp",
            @"video/mpeg",
            @"video/ogg",
            nil];
    });
    return [supportedTypes containsObject:mimeType.lowercaseString] ||
           [mimeType hasPrefix:@"video/"];
}

- (BOOL)validateContentSignature:(NSData *)data declaredMimeType:(NSString *)declaredMime {
    // Each format check below gates on its own minimum length before indexing
    // (e.g. MPEG/WebM/Ogg only need 4 bytes) - a blanket 12-byte minimum here
    // would reject those shorter-but-valid signatures before ever checking them.
    if (data.length == 0) return NO;

    const uint8_t *bytes = (const uint8_t *)data.bytes;

    // MP4 / QuickTime family: ftyp box at offset 4
    //   bytes 4-7 = "ftyp"
    //   known brands: "isom", "mp42", "avc1", "mov ", "qt  "
    BOOL isMP4Family = (data.length >= 8 &&
                        bytes[4] == 'f' && bytes[5] == 't' && bytes[6] == 'y' && bytes[7] == 'p');

    // WebM / Matroska: 0x1A 0x45 0xDF 0xA3 (EBML header)
    BOOL isWebM = (data.length >= 4 &&
                   bytes[0] == 0x1A && bytes[1] == 0x45 &&
                   bytes[2] == 0xDF && bytes[3] == 0xA3);

    // AVI: "RIFF" at 0, "AVI " at 8
    BOOL isAVI = (data.length >= 12 &&
                  bytes[0] == 'R' && bytes[1] == 'I' && bytes[2] == 'F' && bytes[3] == 'F' &&
                  bytes[8] == 'A' && bytes[9] == 'V' && bytes[10] == 'I' && bytes[11] == ' ');

    // MPEG-1/2: 0x00 0x00 0x01 0xBA (or 0xB3)
    BOOL isMPEG = (data.length >= 4 &&
                   bytes[0] == 0x00 && bytes[1] == 0x00 && bytes[2] == 0x01 &&
                   (bytes[3] == 0xBA || bytes[3] == 0xB3));

    // 3GPP family — also starts with ftyp
    // Ogg: "OggS" at 0
    BOOL isOgg = (data.length >= 4 &&
                  bytes[0] == 'O' && bytes[1] == 'g' && bytes[2] == 'g' && bytes[3] == 'S');

    BOOL validSignature = isMP4Family || isWebM || isAVI || isMPEG || isOgg;

    if (!validSignature) {
        GZ_LOG_WARN(@"ATProtoVideoProcessor: content signature rejection for MIME %@ "
                     @"(first 12 bytes: %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x)",
                     declaredMime,
                     data.length > 0  ? bytes[0] : 0,
                     data.length > 1  ? bytes[1] : 0,
                     data.length > 2  ? bytes[2] : 0,
                     data.length > 3  ? bytes[3] : 0,
                     data.length > 4  ? bytes[4] : 0,
                     data.length > 5  ? bytes[5] : 0,
                     data.length > 6  ? bytes[6] : 0,
                     data.length > 7  ? bytes[7] : 0,
                     data.length > 8  ? bytes[8] : 0,
                     data.length > 9  ? bytes[9] : 0,
                     data.length > 10 ? bytes[10] : 0,
                     data.length > 11 ? bytes[11] : 0);
    }

    return validSignature;
}

- (void)processMediaAtURL:(NSURL *)inputURL
          outputDirectory:(NSString *)outputDirectory
            progressBlock:(nullable void (^)(float progress))progressBlock
               completion:(void (^)(NSDictionary<NSString *, id> *_Nullable results,
                                    NSError *_Nullable error))completion {

    if (!inputURL) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"ATProtoVideoProcessor"
                                                code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"Missing input URL"}]);
        }
        return;
    }

    // Propagate blob provider to video singletons so thumbnail/blob storage works
    if (self.blobProvider) {
        [ATProtoVideoThumbnailGenerator sharedGenerator].blobProvider = self.blobProvider;
        [ATProtoVideoTranscoder sharedTranscoder].blobProvider = self.blobProvider;
    }

    NSString *tempDir = NSTemporaryDirectory();
    NSString *tempOutputPath = [tempDir stringByAppendingFormat:@"/video_out_%@.mp4",
                                  [[NSUUID UUID] UUIDString]];
    NSURL *outputURL = [NSURL fileURLWithPath:tempOutputPath];

    __block NSMutableDictionary *metadata = [NSMutableDictionary dictionary];

    // ── Step 1: Extract metadata (dimensions, duration) ──────────
    if (progressBlock) progressBlock(0.05);

    NSDictionary *videoInfo = [self extractVideoMetadataFromURL:inputURL];
    if (videoInfo) {
        [metadata addEntriesFromDictionary:videoInfo];
    }

    // Validate duration
    NSNumber *durationNum = metadata[@"duration"];
    if (durationNum) {
        double durationSeconds = durationNum.doubleValue;
        if (durationSeconds < 1.0) {
            if (completion) {
                completion(nil, [NSError errorWithDomain:@"ATProtoVideoProcessor"
                                                    code:2
                                                userInfo:@{NSLocalizedDescriptionKey: @"Video must be at least 1 second long"}]);
            }
            return;
        }
        if (durationSeconds > 180.0) {
            if (completion) {
                completion(nil, [NSError errorWithDomain:@"ATProtoVideoProcessor"
                                                    code:3
                                                userInfo:@{NSLocalizedDescriptionKey: @"Video must be at most 180 seconds long"}]);
            }
            return;
        }
    }

    // ── Step 2: Transcode ────────────────────────────────────────
    if (progressBlock) progressBlock(0.10);

    [[ATProtoVideoTranscoder sharedTranscoder] transcodeVideoAtURL:inputURL
                                                         toQuality:ATProtoVideoTranscoderQuality720p
                                                         outputURL:outputURL
                                                          progress:^(float transcodeProgress) {
        if (progressBlock) progressBlock(0.10 + transcodeProgress * 0.40);
    }
                                                        completion:^(NSURL *transcodedURL, NSError *transcodeError) {
        if (!transcodedURL) {
            GZ_LOG_ERROR(@"ATProtoVideoProcessor: transcoding failed: %@", transcodeError);
            if (completion) completion(nil, transcodeError);
            return;
        }

        // Read transcoded data for CID computation
        NSData *transcodedData = [NSData dataWithContentsOfURL:transcodedURL
                                                       options:NSDataReadingMappedIfSafe
                                                         error:nil];
        if (!transcodedData) {
            GZ_LOG_ERROR(@"ATProtoVideoProcessor: failed to read transcoded output");
            if (completion) {
                completion(nil, [NSError errorWithDomain:@"ATProtoVideoProcessor"
                                                    code:4
                                                userInfo:@{NSLocalizedDescriptionKey: @"Failed to read transcoded output"}]);
            }
            return;
        }

        CID *processedCid = [CID sha256:transcodedData];
        NSString *processedCidStr = processedCid.stringValue;

        // ── Step 3: Generate thumbnail ──────────────────────────────
        if (progressBlock) progressBlock(0.55);

        [[ATProtoVideoThumbnailGenerator sharedGenerator] generateThumbnailAtTime:1.0
                                                                    fromVideoURL:transcodedURL
                                                                      maxWidth:640
                                                                     maxHeight:360
                                                                   completion:^(NSData *thumbnailData, NSError *thumbError) {

            NSString *thumbnailCidStr = nil;
            if (thumbnailData) {
                CID *thumbnailCid = [[ATProtoVideoThumbnailGenerator sharedGenerator] storeThumbnailData:thumbnailData
                                                                                                  forJob:@""
                                                                                                  error:nil];
                thumbnailCidStr = thumbnailCid.stringValue;
            } else {
                GZ_LOG_WARN(@"ATProtoVideoProcessor: thumbnail generation failed: %@", thumbError);
            }

            // ── Step 4: Generate HLS ────────────────────────────────
            if (progressBlock) progressBlock(0.70);

            NSString *hlsDirectory = nil;
            if (outputDirectory.length > 0) {
                ATProtoVideoHLSGenerator *hlsGenerator = [ATProtoVideoHLSGenerator sharedGenerator];
                hlsGenerator.outputBaseDirectory = outputDirectory;
                hlsGenerator.include1080p = self.include1080p;

                // HLS generation requires DID and blob CID for path construction
                NSString *hlsDid = self.did ?: @"did:plc:unknown";
                NSString *hlsCid = self.blobCid ?: processedCidStr;

                NSError *hlsError = nil;
                VideoHLSResult *hlsResult = [hlsGenerator generateHLSFromVideoAtURL:transcodedURL
                                                                                 did:hlsDid
                                                                                 cid:hlsCid
                                                                       thumbnailData:thumbnailData
                                                                               error:&hlsError];
                if (hlsResult) {
                    hlsDirectory = [hlsGenerator hlsDirectoryForDID:hlsDid cid:hlsCid];
                    metadata[@"hlsMasterPlaylist"] = hlsResult.masterPlaylistPath;
                    metadata[@"hlsVariants"] = hlsResult.variants;
                    if (self.outputBaseUrl) {
                        metadata[@"hlsBaseUrl"] = self.outputBaseUrl;
                    }
                    GZ_LOG_INFO(@"ATProtoVideoProcessor: HLS generation complete for %@/%@ (%lu variants)",
                                 hlsDid, hlsCid, (unsigned long)hlsResult.variants.count);
                } else {
                    GZ_LOG_WARN(@"ATProtoVideoProcessor: HLS generation failed (non-fatal): %@", hlsError);
                }
            }

            // ── Step 5: Clean up temp transcoded file ───────────────
            [[NSFileManager defaultManager] removeItemAtURL:transcodedURL error:nil];

            // ── Step 6: Build results ───────────────────────────────
            if (progressBlock) progressBlock(1.0);

            if (completion) {
                NSMutableDictionary *results = [NSMutableDictionary dictionary];
                results[@"processedCid"] = processedCidStr;
                if (thumbnailCidStr) {
                    results[@"thumbnailCid"] = thumbnailCidStr;
                }
                if (metadata.count > 0) {
                    results[@"metadata"] = [metadata copy];
                }
                completion([results copy], nil);
            }
        }];
    }];
}

#pragma mark - Metadata Extraction

- (nullable NSDictionary *)extractVideoMetadataFromURL:(NSURL *)videoURL {
#if TARGET_OS_MAC
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:videoURL options:nil];
    if (!asset) return nil;

    NSMutableDictionary *info = [NSMutableDictionary dictionary];

    NSArray<AVAssetTrack *> *videoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    if (videoTracks.count > 0) {
        AVAssetTrack *videoTrack = videoTracks.firstObject;
        CGSize naturalSize = videoTrack.naturalSize;
        if (naturalSize.width > 0 && naturalSize.height > 0) {
            info[@"width"]   = @((NSInteger)naturalSize.width);
            info[@"height"]  = @((NSInteger)naturalSize.height);
        }
    }

    Float64 durationSeconds = CMTimeGetSeconds(asset.duration);
    if (durationSeconds > 0) {
        info[@"duration"] = @((NSInteger)round(durationSeconds));
        info[@"durationSeconds"] = @(durationSeconds);
    }

    return info.count > 0 ? info : nil;
#else
    FFmpegTranscoder *probe = [[FFmpegTranscoder alloc] initWithFFmpegPath:nil ffprobePath:nil];
    NSMutableDictionary *info = [NSMutableDictionary dictionary];

    CGSize dims = [probe probeDimensionsForVideoAtURL:videoURL];
    if (dims.width > 0 && dims.height > 0) {
        info[@"width"]  = @((NSInteger)dims.width);
        info[@"height"] = @((NSInteger)dims.height);
    }

    float duration = [probe probeDurationForVideoAtURL:videoURL];
    if (duration > 0) {
        info[@"duration"] = @((NSInteger)roundf(duration));
        info[@"durationSeconds"] = @(duration);
    }

    return info.count > 0 ? info : nil;
#endif
}

@end
