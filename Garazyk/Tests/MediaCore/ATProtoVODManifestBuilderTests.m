// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "MediaCore/ATProtoVODManifestBuilder.h"
#import "MediaCore/ATProtoCAObjectStore.h"
#import "Core/ATProtoMASLDocument.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"

@interface ATProtoVODManifestBuilderTests : XCTestCase
@property (nonatomic, copy) NSString *tempRoot;
@end

@implementation ATProtoVODManifestBuilderTests

- (void)setUp {
    [super setUp];
    self.tempRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"vod-manifest-%@", NSUUID.UUID.UUIDString]];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.tempRoot error:nil];
    [super tearDown];
}

- (NSData *)bytesFilledWith:(uint8_t)byte length:(NSUInteger)length {
    NSMutableData *data = [NSMutableData dataWithLength:length];
    memset(data.mutableBytes, byte, length);
    return data;
}

- (NSDictionary<NSString *, NSData *> *)fixtureWithVariants:(NSArray<NSString *> *)variants
                                           segmentsPerVariant:(NSUInteger)segmentsPerVariant
                                               segmentLength:(NSUInteger)segmentLength {
    NSMutableDictionary<NSString *, NSData *> *produced = [NSMutableDictionary dictionary];
    NSMutableString *master = [NSMutableString stringWithString:@"#EXTM3U\n#EXT-X-VERSION:3\n"];
    uint8_t fill = 1;
    for (NSString *variant in variants) {
        [master appendFormat:@"#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=1280x720\n%@/video.m3u8\n", variant];

        NSData *initData = [self bytesFilledWith:fill++ length:64];
        produced[[NSString stringWithFormat:@"/%@/init.mp4", variant]] = initData;

        NSMutableString *playlist = [NSMutableString string];
        [playlist appendString:@"#EXTM3U\n"];
        [playlist appendString:@"#EXT-X-VERSION:7\n"];
        [playlist appendString:@"#EXT-X-TARGETDURATION:6\n"];
        [playlist appendString:@"#EXT-X-MEDIA-SEQUENCE:0\n"];
        [playlist appendString:@"#EXT-X-PLAYLIST-TYPE:VOD\n"];
        [playlist appendString:@"#EXT-X-MAP:URI=\"init.mp4\"\n"];
        for (NSUInteger i = 0; i < segmentsPerVariant; i++) {
            NSString *name = [NSString stringWithFormat:@"segment_%05lu.m4s", (unsigned long)i];
            produced[[NSString stringWithFormat:@"/%@/%@", variant, name]] =
                [self bytesFilledWith:fill++ length:segmentLength];
            [playlist appendString:@"#EXTINF:6.000000,\n"];
            [playlist appendFormat:@"%@\n", name];
        }
        [playlist appendString:@"#EXT-X-ENDLIST\n"];
        produced[[NSString stringWithFormat:@"/%@/video.m3u8", variant]] =
            [playlist dataUsingEncoding:NSUTF8StringEncoding];
    }
    produced[@"/"] = [master dataUsingEncoding:NSUTF8StringEncoding];
    return produced;
}

- (void)testFlatVODRoundTripResolvesBLAKE3MediaCIDs {
    NSError *error = nil;
    ATProtoCAObjectStore *store = [[ATProtoCAObjectStore alloc] initWithRootDirectory:self.tempRoot error:&error];
    XCTAssertNotNil(store);

    NSDictionary *produced = [self fixtureWithVariants:@[ @"360p", @"720p" ]
                                    segmentsPerVariant:3
                                        segmentLength:128];
    ATProtoVODManifestBuildResult *result =
        [ATProtoVODManifestBuilder buildFromProducedData:produced store:store error:&error];
    XCTAssertNotNil(result);
    XCTAssertNil(error);
    XCTAssertTrue(result.document.isBundle);

    ATProtoMASLDocument *decoded = [ATProtoMASLDocument documentWithDRISLData:result.drislData error:&error];
    XCTAssertNotNil(decoded);
    XCTAssertNil(error);

    for (NSString *path in result.resourceCIDs) {
        ATProtoCID *expected = result.resourceCIDs[path];
        ATProtoCID *fromDoc = [decoded resourceCIDForPath:path error:&error];
        XCTAssertEqualObjects(fromDoc, expected);
        XCTAssertNil(error);

        NSData *stored = [store dataForCID:expected error:&error];
        XCTAssertNotNil(stored);
        XCTAssertNil(error);

        if ([path hasSuffix:@".fmp4"]) {
            XCTAssertTrue([expected isDASLConformantForProfile:ATProtoDASLCIDProfileBig]);
            ATProtoCID *recomputed =
                [ATProtoCAObjectStore cidForData:stored profile:ATProtoCAObjectDigestProfileBLAKE3 error:&error];
            XCTAssertEqualObjects(recomputed, expected);
            NSDictionary *stat = [store statCID:expected error:&error];
            XCTAssertEqualObjects(stat[@"hasProof"], @YES);
            NSArray *frags = result.fragmentTables[path];
            XCTAssertGreaterThanOrEqual(frags.count, 2u);
        } else {
            XCTAssertTrue([expected isDASLConformantForProfile:ATProtoDASLCIDProfileBase]);
            ATProtoCID *recomputed =
                [ATProtoCAObjectStore cidForData:stored profile:ATProtoCAObjectDigestProfileSHA256 error:&error];
            XCTAssertEqualObjects(recomputed, expected);
        }
    }

    NSData *playlist720 = [store dataForCID:result.resourceCIDs[@"/720p/video.m3u8"] error:&error];
    NSString *playlistText = [[NSString alloc] initWithData:playlist720 encoding:NSUTF8StringEncoding];
    XCTAssertTrue([playlistText containsString:@"#EXT-X-BYTERANGE:"]);
    XCTAssertTrue([playlistText containsString:@"URI=\"video.fmp4\""]);
}

- (void)testOneHourThreeRenditionManifestUnderOneMiB {
    NSError *error = nil;
    ATProtoCAObjectStore *store = [[ATProtoCAObjectStore alloc] initWithRootDirectory:self.tempRoot error:&error];
    XCTAssertNotNil(store);

    // 1 hour @ 6s segments × 3 renditions = 600 segments each; flat packaging
    // keeps MASL resources to master + 3 playlists + 3 media objects.
    NSDictionary *produced = [self fixtureWithVariants:@[ @"360p", @"720p", @"1080p" ]
                                    segmentsPerVariant:600
                                        segmentLength:16];
    ATProtoVODManifestBuildResult *result =
        [ATProtoVODManifestBuilder buildFromProducedData:produced store:store error:&error];
    XCTAssertNotNil(result);
    XCTAssertNil(error);
    XCTAssertEqual(result.resourceCIDs.count, 7u);
    XCTAssertLessThan(result.drislData.length, (NSUInteger)(1024 * 1024));
}

- (void)testMissingInitFailsCleanly {
    NSError *error = nil;
    ATProtoCAObjectStore *store = [[ATProtoCAObjectStore alloc] initWithRootDirectory:self.tempRoot error:&error];
    NSMutableDictionary *produced = [[self fixtureWithVariants:@[ @"360p" ]
                                            segmentsPerVariant:1
                                                segmentLength:8] mutableCopy];
    [produced removeObjectForKey:@"/360p/init.mp4"];
    ATProtoVODManifestBuildResult *result =
        [ATProtoVODManifestBuilder buildFromProducedData:produced store:store error:&error];
    XCTAssertNil(result);
    XCTAssertEqual(error.code, ATProtoVODManifestBuilderErrorMissingAsset);
}

@end
