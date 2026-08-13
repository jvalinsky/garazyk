// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "MediaCore/ATProtoVODManifestBuilder.h"
#import "MediaCore/ATProtoCAObjectStore.h"
#import "Core/ATProtoMASLDocument.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"

NSErrorDomain const ATProtoVODManifestBuilderErrorDomain = @"com.atproto.vod.manifest";

static NSError *VODManifestError(ATProtoVODManifestBuilderErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ATProtoVODManifestBuilderErrorDomain
                                code:code
                            userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void VODManifestSetError(NSError **error, ATProtoVODManifestBuilderErrorCode code, NSString *message) {
    if (error) {
        *error = VODManifestError(code, message);
    }
}

@interface ATProtoVODManifestBuildResult ()
@property (nonatomic, strong, readwrite) ATProtoMASLDocument *document;
@property (nonatomic, copy, readwrite) NSData *drislData;
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, ATProtoCID *> *resourceCIDs;
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, NSArray<NSDictionary<NSString *, id> *> *> *fragmentTables;
@end

@implementation ATProtoVODManifestBuildResult
@end

@implementation ATProtoVODManifestBuilder

+ (nullable ATProtoVODManifestBuildResult *)buildFromProducedFiles:(NSDictionary<NSString *, NSString *> *)producedFiles
                                                            store:(ATProtoCAObjectStore *)store
                                                            error:(NSError **)error {
    if (![producedFiles isKindOfClass:[NSDictionary class]] || producedFiles.count == 0) {
        VODManifestSetError(error, ATProtoVODManifestBuilderErrorInvalidArgument, @"producedFiles is required");
        return nil;
    }
    if (![store isKindOfClass:[ATProtoCAObjectStore class]]) {
        VODManifestSetError(error, ATProtoVODManifestBuilderErrorInvalidArgument, @"store is required");
        return nil;
    }

    NSMutableDictionary<NSString *, NSData *> *producedData = [NSMutableDictionary dictionaryWithCapacity:producedFiles.count];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in producedFiles) {
        NSString *absolute = producedFiles[path];
        if (![absolute isKindOfClass:[NSString class]] || absolute.length == 0) {
            VODManifestSetError(error, ATProtoVODManifestBuilderErrorMissingAsset,
                                [NSString stringWithFormat:@"Missing absolute path for %@", path]);
            return nil;
        }
        if (![fm fileExistsAtPath:absolute]) {
            VODManifestSetError(error, ATProtoVODManifestBuilderErrorMissingAsset,
                                [NSString stringWithFormat:@"File missing for %@: %@", path, absolute]);
            return nil;
        }
        NSData *data = [NSData dataWithContentsOfFile:absolute options:0 error:error];
        if (!data) {
            VODManifestSetError(error, ATProtoVODManifestBuilderErrorMissingAsset,
                                [NSString stringWithFormat:@"Could not read %@", absolute]);
            return nil;
        }
        producedData[path] = data;
    }
    return [self buildFromProducedData:producedData store:store error:error];
}

+ (nullable ATProtoVODManifestBuildResult *)buildFromProducedData:(NSDictionary<NSString *, NSData *> *)producedData
                                                           store:(ATProtoCAObjectStore *)store
                                                           error:(NSError **)error {
    if (![producedData isKindOfClass:[NSDictionary class]] || producedData.count == 0) {
        VODManifestSetError(error, ATProtoVODManifestBuilderErrorInvalidArgument, @"producedData is required");
        return nil;
    }
    if (![store isKindOfClass:[ATProtoCAObjectStore class]]) {
        VODManifestSetError(error, ATProtoVODManifestBuilderErrorInvalidArgument, @"store is required");
        return nil;
    }

    NSData *masterData = producedData[@"/"];
    if (!masterData) {
        VODManifestSetError(error, ATProtoVODManifestBuilderErrorMissingAsset, @"Master playlist path / is required");
        return nil;
    }

    NSMutableSet<NSString *> *variants = [NSMutableSet set];
    for (NSString *path in producedData) {
        if (![path isKindOfClass:[NSString class]] || ![path hasPrefix:@"/"] || path.length < 2) {
            continue;
        }
        NSString *rest = [path substringFromIndex:1];
        NSRange slash = [rest rangeOfString:@"/"];
        if (slash.location == NSNotFound) {
            continue;
        }
        NSString *variant = [rest substringToIndex:slash.location];
        NSString *leaf = [rest substringFromIndex:slash.location + 1];
        if ([leaf isEqualToString:@"init.mp4"] ||
            ([leaf hasPrefix:@"segment_"] && [leaf hasSuffix:@".m4s"]) ||
            [leaf isEqualToString:@"video.m3u8"]) {
            [variants addObject:variant];
        }
    }
    if (variants.count == 0) {
        VODManifestSetError(error, ATProtoVODManifestBuilderErrorMissingAsset, @"No HLS variants found in produced data");
        return nil;
    }

    NSMutableDictionary<NSString *, ATProtoCID *> *resourceCIDs = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSDictionary *> *resources = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSArray<NSDictionary<NSString *, id> *> *> *fragmentTables =
        [NSMutableDictionary dictionary];

    NSArray<NSString *> *sortedVariants = [[variants allObjects] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *variant in sortedVariants) {
        NSString *initPath = [NSString stringWithFormat:@"/%@/init.mp4", variant];
        NSData *initData = producedData[initPath];
        if (!initData) {
            VODManifestSetError(error, ATProtoVODManifestBuilderErrorMissingAsset,
                                [NSString stringWithFormat:@"Missing init segment for variant %@", variant]);
            return nil;
        }

        NSMutableArray<NSString *> *segmentNames = [NSMutableArray array];
        for (NSString *path in producedData) {
            NSString *prefix = [NSString stringWithFormat:@"/%@/", variant];
            if (![path hasPrefix:prefix]) {
                continue;
            }
            NSString *leaf = [path substringFromIndex:prefix.length];
            if ([leaf hasPrefix:@"segment_"] && [leaf hasSuffix:@".m4s"]) {
                [segmentNames addObject:leaf];
            }
        }
        [segmentNames sortUsingSelector:@selector(compare:)];
        if (segmentNames.count == 0) {
            VODManifestSetError(error, ATProtoVODManifestBuilderErrorMissingAsset,
                                [NSString stringWithFormat:@"No media segments for variant %@", variant]);
            return nil;
        }

        NSMutableData *flat = [NSMutableData dataWithData:initData];
        NSMutableArray<NSDictionary<NSString *, id> *> *fragments = [NSMutableArray array];
        [fragments addObject:@{
            @"name": @"init.mp4",
            @"offset": @0,
            @"length": @(initData.length)
        }];
        NSUInteger offset = initData.length;
        for (NSString *segmentName in segmentNames) {
            NSString *segmentPath = [NSString stringWithFormat:@"/%@/%@", variant, segmentName];
            NSData *segmentData = producedData[segmentPath];
            if (!segmentData) {
                VODManifestSetError(error, ATProtoVODManifestBuilderErrorMissingAsset,
                                    [NSString stringWithFormat:@"Missing segment %@", segmentPath]);
                return nil;
            }
            [fragments addObject:@{
                @"name": segmentName,
                @"offset": @(offset),
                @"length": @(segmentData.length)
            }];
            [flat appendData:segmentData];
            offset += segmentData.length;
        }

        NSError *storeError = nil;
        ATProtoCID *mediaCID = [store putData:flat
                                  expectedCID:nil
                                      profile:ATProtoCAObjectDigestProfileBLAKE3
                                        error:&storeError];
        if (!mediaCID) {
            if (error) {
                *error = storeError ?: VODManifestError(ATProtoVODManifestBuilderErrorStore, @"Failed to put flat VOD object");
            }
            return nil;
        }

        NSString *mediaPath = [NSString stringWithFormat:@"/%@/video.fmp4", variant];
        resourceCIDs[mediaPath] = mediaCID;
        fragmentTables[mediaPath] = [fragments copy];
        resources[mediaPath] = @{
            @"src": mediaCID,
            @"content-type": @"video/mp4",
            @"garazyk.vod.v1": @{
                @"profile": @"flat-fmp4",
                @"digest": @"blake3",
                @"fragments": [fragments copy]
            }
        };

        NSString *playlistPath = [NSString stringWithFormat:@"/%@/video.m3u8", variant];
        NSData *sourcePlaylist = producedData[playlistPath];
        NSData *rewritten = [self rewrittenVariantPlaylistFromSource:sourcePlaylist
                                                           fragments:fragments
                                                          mediaURI:@"video.fmp4"];
        if (!rewritten) {
            VODManifestSetError(error, ATProtoVODManifestBuilderErrorMissingAsset,
                                [NSString stringWithFormat:@"Could not rewrite playlist for %@", variant]);
            return nil;
        }

        ATProtoCID *playlistCID = [store putData:rewritten
                                     expectedCID:nil
                                         profile:ATProtoCAObjectDigestProfileSHA256
                                           error:&storeError];
        if (!playlistCID) {
            if (error) {
                *error = storeError ?: VODManifestError(ATProtoVODManifestBuilderErrorStore, @"Failed to put variant playlist");
            }
            return nil;
        }
        resourceCIDs[playlistPath] = playlistCID;
        resources[playlistPath] = @{
            @"src": playlistCID,
            @"content-type": @"application/vnd.apple.mpegurl"
        };
    }

    NSError *storeError = nil;
    ATProtoCID *masterCID = [store putData:masterData
                               expectedCID:nil
                                   profile:ATProtoCAObjectDigestProfileSHA256
                                     error:&storeError];
    if (!masterCID) {
        if (error) {
            *error = storeError ?: VODManifestError(ATProtoVODManifestBuilderErrorStore, @"Failed to put master playlist");
        }
        return nil;
    }
    resourceCIDs[@"/"] = masterCID;
    resources[@"/"] = @{
        @"src": masterCID,
        @"content-type": @"application/vnd.apple.mpegurl"
    };

    NSDictionary *object = @{
        @"$type": @"ing.dasl.masl",
        @"name": @"garazyk.vod",
        @"garazyk.vod.v1": @{
            @"packaging": @"flat-rendition",
            @"mediaDigest": @"blake3",
            @"playlistDigest": @"sha256"
        },
        @"resources": [resources copy]
    };

    NSError *maslError = nil;
    ATProtoMASLDocument *document = [ATProtoMASLDocument documentWithObject:object error:&maslError];
    if (!document) {
        if (error) {
            *error = maslError ?: VODManifestError(ATProtoVODManifestBuilderErrorManifest, @"MASL validation failed");
        }
        return nil;
    }

    NSData *drisl = [document DRISLDataWithError:&maslError];
    if (!drisl) {
        if (error) {
            *error = maslError ?: VODManifestError(ATProtoVODManifestBuilderErrorManifest, @"DRISL encode failed");
        }
        return nil;
    }

    ATProtoVODManifestBuildResult *result = [[ATProtoVODManifestBuildResult alloc] init];
    result.document = document;
    result.drislData = drisl;
    result.resourceCIDs = [resourceCIDs copy];
    result.fragmentTables = [fragmentTables copy];
    return result;
}

#pragma mark - Playlist rewrite

+ (nullable NSData *)rewrittenVariantPlaylistFromSource:(nullable NSData *)sourcePlaylist
                                              fragments:(NSArray<NSDictionary<NSString *, id> *> *)fragments
                                               mediaURI:(NSString *)mediaURI {
    if (fragments.count < 2 || mediaURI.length == 0) {
        return nil;
    }

    NSUInteger initLength = [fragments[0][@"length"] unsignedIntegerValue];
    NSMutableArray<NSNumber *> *extinfDurations = [NSMutableArray array];
    NSInteger targetDuration = 6;
    if (sourcePlaylist.length > 0) {
        NSString *source = [[NSString alloc] initWithData:sourcePlaylist encoding:NSUTF8StringEncoding];
        for (NSString *rawLine in [source componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
            NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([line hasPrefix:@"#EXT-X-TARGETDURATION:"]) {
                targetDuration = MAX(1, [[line substringFromIndex:22] integerValue]);
            } else if ([line hasPrefix:@"#EXTINF:"]) {
                NSString *payload = [line substringFromIndex:8];
                NSRange comma = [payload rangeOfString:@","];
                NSString *durationText = comma.location == NSNotFound ? payload : [payload substringToIndex:comma.location];
                [extinfDurations addObject:@([durationText doubleValue])];
            }
        }
    }

    NSUInteger mediaFragmentCount = fragments.count - 1;
    while (extinfDurations.count < mediaFragmentCount) {
        [extinfDurations addObject:@(targetDuration)];
    }

    NSMutableString *out = [NSMutableString string];
    [out appendString:@"#EXTM3U\n"];
    [out appendString:@"#EXT-X-VERSION:7\n"];
    [out appendFormat:@"#EXT-X-TARGETDURATION:%ld\n", (long)targetDuration];
    [out appendString:@"#EXT-X-MEDIA-SEQUENCE:0\n"];
    [out appendString:@"#EXT-X-PLAYLIST-TYPE:VOD\n"];
    [out appendFormat:@"#EXT-X-MAP:URI=\"%@\",BYTERANGE=\"%lu@0\"\n", mediaURI, (unsigned long)initLength];

    for (NSUInteger i = 0; i < mediaFragmentCount; i++) {
        NSDictionary *frag = fragments[i + 1];
        NSUInteger fragOffset = [frag[@"offset"] unsignedIntegerValue];
        NSUInteger fragLength = [frag[@"length"] unsignedIntegerValue];
        double duration = [extinfDurations[i] doubleValue];
        [out appendFormat:@"#EXTINF:%.6f,\n", duration];
        [out appendFormat:@"#EXT-X-BYTERANGE:%lu@%lu\n", (unsigned long)fragLength, (unsigned long)fragOffset];
        [out appendFormat:@"%@\n", mediaURI];
    }
    [out appendString:@"#EXT-X-ENDLIST\n"];
    return [out dataUsingEncoding:NSUTF8StringEncoding];
}

@end
