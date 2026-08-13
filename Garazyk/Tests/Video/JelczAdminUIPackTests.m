// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>

#import "AdminUIServer/Packs/JelczAdminSnapshot.h"
#import "AdminUIServer/Packs/GZAdminUIVideoPack.h"
#import "Video/AdminUI/JelczAdminUIPack.h"
#import "Video/JelczDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@interface JelczAdminUIPackTests : XCTestCase
@end

@implementation JelczAdminUIPackTests

- (void)testSidebarIncludesDistribution {
    NSArray *sections = [GZJelczAdminUIPack sidebarSections];
    XCTAssertGreaterThanOrEqual(sections.count, 4u);
    NSMutableSet *ids = [NSMutableSet set];
    for (NSDictionary *section in sections) {
        [ids addObject:section[@"tabIdentifier"]];
    }
    XCTAssertTrue([ids containsObject:@"video-metrics"]);
    XCTAssertTrue([ids containsObject:@"video-jobs"]);
    XCTAssertTrue([ids containsObject:@"video-distribution"]);
    XCTAssertTrue([ids containsObject:@"video-capacity"]);
}

- (void)testJobDTORedactsServiceAuthTokenAndPaths {
    NSDictionary *row = @{
        @"job_id": @"job-1",
        @"did": @"did:plc:alice",
        @"blob_cid": @"bafybeitest",
        @"state": @"FAILED",
        @"progress": @40,
        @"service_auth_token": @"super-secret-jwt",
        @"error_message": @"ffmpeg failed writing /var/lib/jelcz/tmp/out.mp4",
        @"message": @"/secret/stage/path",
        @"manifest_blob_cid": [NSNull null],
        @"created_at": @"2026-08-12T00:00:00Z",
        @"updated_at": @"2026-08-12T00:01:00Z",
    };
    NSDictionary *dto = [GZJelczAdminSnapshot allowlistedJobDTOFromDatabaseRow:row];
    XCTAssertEqualObjects(dto[@"jobId"], @"job-1");
    XCTAssertNil(dto[@"service_auth_token"]);
    XCTAssertNil(dto[@"serviceAuthToken"]);
    XCTAssertEqualObjects(dto[@"errorCategory"], @"transcode");
    XCTAssertEqualObjects(dto[@"stage"], @"processing");
    NSString *html = [GZAdminUIVideoPack renderVideoJobDetailPartial:@{@"job": dto}];
    XCTAssertFalse([html containsString:@"super-secret-jwt"]);
    XCTAssertFalse([html containsString:@"/var/lib/jelcz"]);
    XCTAssertTrue([html containsString:@"transcode"]);
    XCTAssertTrue([html containsString:@"Distribution"]);
}

- (void)testJobDTOMarksCAVODProductFromManifest {
    NSDictionary *row = @{
        @"job_id": @"job-2",
        @"did": @"did:plc:bob",
        @"blob_cid": @"bafybeisource",
        @"state": @"COMPLETED",
        @"progress": @100,
        @"manifest_blob_cid": @"bafyreimanifest",
        @"processed_blob_cid": @"bafyreiprocessed",
        @"created_at": @"2026-08-12T00:00:00Z",
        @"updated_at": @"2026-08-12T00:02:00Z",
    };
    NSDictionary *dto = [GZJelczAdminSnapshot allowlistedJobDTOFromDatabaseRow:row];
    XCTAssertEqualObjects(dto[@"product"], @"CA VOD");
    XCTAssertEqualObjects(dto[@"manifestBlobCid"], @"bafyreimanifest");
    NSString *jobsHTML = [GZAdminUIVideoPack renderVideoJobsPartial:@{@"jobs": @[dto]}];
    XCTAssertTrue([jobsHTML containsString:@"CA VOD"]);
}

- (void)testDistributionPartialOmitsPathsAndShowsFlags {
    NSDictionary *snapshot = @{
        @"distribution": @{
            @"caManifestEnabled": @YES,
            @"caStoreConfigured": @YES,
            @"muxlPresentationEnabled": @NO,
            @"watchMode": @"masl-ca",
            @"sweepEnabled": @NO,
            @"mirrorFetchEnabled": @YES,
            @"mirrorProviderCount": @2,
            @"streamplaceMirrorConfigured": @YES,
            @"streamplaceAttributionDIDConfigured": @YES,
            @"streamplaceServeCompat": @NO,
            @"streamplaceFetchSuccessCount": @3,
            @"streamplaceBlobNotFoundCount": @1,
            @"streamplaceFetchFailureCount": @0,
            @"summary": @"Content-addressed VOD: MASL /watch + optional Bao proofs",
            @"rootDirectory": @"/should/never/render",
        },
    };
    NSString *html = [GZAdminUIVideoPack renderVideoDistributionPartial:snapshot];
    XCTAssertTrue([html containsString:@"masl-ca"]);
    XCTAssertTrue([html containsString:@"Feature flags"]);
    XCTAssertTrue([html containsString:@"Streamplace"]);
    XCTAssertTrue([html containsString:@"3 / 1 / 0"]);
    XCTAssertFalse([html containsString:@"/should/never/render"]);
}

- (void)testEmbeddedSnapshotIncludesDistributionFromConfig {
    id worker = [[NSObject alloc] init]; // no KVC flags
    GZJelczAdminSnapshot *snap =
        [[GZJelczAdminSnapshot alloc] initWithWorker:worker
                                            jobStore:nil
                                              config:@{
                                                  @"enableContentAddressedManifest": @YES,
                                                  @"caObjectStoreConfigured": @YES,
                                                  @"enableMUXLPresentation": @YES,
                                                  @"enableCAMirrorFetch": @NO,
                                                  @"caMirrorProviderCount": @0,
                                                  @"caObjectSweepEnabled": @NO,
                                                  @"streamplaceMirrorConfigured": @YES,
                                                  @"streamplaceAttributionDIDConfigured": @NO,
                                                  @"streamplaceServeCompat": @NO,
                                                  @"maxUploadSize": @(1024),
                                                  @"maxDuration": @60,
                                              }
                                        uptimeSeconds:12];
    NSDictionary *dist = snap.snapshot[@"distribution"];
    XCTAssertTrue([dist[@"caManifestEnabled"] boolValue]);
    XCTAssertTrue([dist[@"muxlPresentationEnabled"] boolValue]);
    XCTAssertTrue([dist[@"streamplaceMirrorConfigured"] boolValue]);
    XCTAssertFalse([dist[@"streamplaceAttributionDIDConfigured"] boolValue]);
    XCTAssertEqualObjects(dist[@"watchMode"], @"masl-ca");
    NSString *overview = [GZAdminUIVideoPack renderVideoOverviewPartial:snap.snapshot];
    XCTAssertTrue([overview containsString:@"Distribution posture"]);
    XCTAssertTrue([overview containsString:@"masl-ca"]);
    XCTAssertTrue([overview containsString:@"Streamplace"]);
}

- (void)testJobCountsByStateAreCheap {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [[NSUUID UUID] UUIDString]];
    NSError *error = nil;
    GZJelczDatabase *db = [[GZJelczDatabase alloc] initWithDatabasePath:path error:&error];
    XCTAssertNotNil(db, @"%@", error);
    XCTAssertTrue([db createVideoJobWithId:@"a" did:@"did:plc:a" blobCid:@"b1" mimeType:@"video/mp4"
                                  fileSize:@1 serviceAuthToken:@"tok" error:&error], @"%@", error);
    XCTAssertTrue([db createVideoJobWithId:@"b" did:@"did:plc:b" blobCid:@"b2" mimeType:@"video/mp4"
                                  fileSize:@1 serviceAuthToken:nil error:&error], @"%@", error);
    XCTAssertTrue([db updateVideoJobState:@"b" state:@"COMPLETED" progress:@100 message:nil error:&error], @"%@", error);

    NSDictionary *counts = [db jobCountsByStateWithError:&error];
    XCTAssertNil(error);
    XCTAssertEqual([counts[@"PENDING"] unsignedIntegerValue], 1u);
    XCTAssertEqual([counts[@"COMPLETED"] unsignedIntegerValue], 1u);
    [db closeDatabase];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

@end

NS_ASSUME_NONNULL_END
