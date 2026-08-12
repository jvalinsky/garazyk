// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "RepoAuthXrpcTestBase.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Services/PDS/PDSRepositoryService.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Pool/DatabasePool.h"

@interface ATProtoServiceConfiguration (Test)
- (void)applyConfig:(NSDictionary *)config;
@end

// importRepo scaling (ADR 0035 / B1): the endpoint's size cap is driven by a
// single configurable value (maxImportSize) instead of a hardcoded 16 MB
// constant, and an acceptingImports kill switch can disable the endpoint
// entirely — both mirroring the reference PDS. These tests pin that behavior
// through the XRPC layer.
@interface ImportRepoScalingTests : RepoAuthXrpcTestBase
@end

@implementation ImportRepoScalingTests

- (void)tearDown {
    // The configuration singleton is process-global; restore the default
    // service posture so later suites (e.g. under --shuffle) never observe
    // a small cap or a disabled-imports flag left behind by these tests.
    [[ATProtoServiceConfiguration sharedConfiguration] applyConfig:@{
        @"server": @{},
        @"service": @{
            @"max_import_size": @(1ULL * 1024ULL * 1024ULL * 1024ULL),
            @"accepting_imports": @YES,
        },
    }];
    [super tearDown];
}

// Re-apply configuration exactly as the base setUp did, plus the service
// section override. applyConfig: re-reads env vars, so the canonical issuer
// used to mint access tokens in setUp is unchanged.
- (void)applyConfigWithService:(NSDictionary *)service {
    [[ATProtoServiceConfiguration sharedConfiguration] applyConfig:@{
        @"server": @{},
        @"service": service ?: @{},
    }];
}

- (ATProtoHttpResponse *)postImportRepoWithBody:(NSData *)body {
    return [self sendRawPostRequestWithPath:@"/xrpc/com.atproto.repo.importRepo"
                                   bodyData:body
                                    headers:@{
                                        @"authorization": [@"Bearer " stringByAppendingString:self.accessJwt1],
                                        @"content-type": @"application/vnd.ipld.car",
                                        @"content-length": [NSString stringWithFormat:@"%lu", (unsigned long)body.length],
                                    }];
}

- (void)testImportRepoBodyOverMaxImportSizeRejectedWith413 {
    // The configuration singleton is process-global, so every test restates
    // both service keys explicitly to be independent of prior test state.
    [self applyConfigWithService:@{
        @"max_import_size": @(2048),
        @"accepting_imports": @YES,
    }];
    XCTAssertEqual([ATProtoServiceConfiguration sharedConfiguration].maxImportSize, 2048);

    NSData *oversized = [NSMutableData dataWithLength:4096];
    ATProtoHttpResponse *response = [self postImportRepoWithBody:oversized];
    XCTAssertEqual(response.statusCode, HttpStatusPayloadTooLarge);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"PayloadTooLarge");
}

- (void)testImportRepoBodyUnderMaxImportSizeNotRejectedByCap {
    [self applyConfigWithService:@{
        @"max_import_size": @(2048),
        @"accepting_imports": @YES,
    }];

    // A small, structurally invalid body passes the size gate and fails
    // downstream as an invalid CAR — proving the 413 above is the cap doing
    // its job, not a generic rejection.
    NSData *small = [@"not-a-real-car" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoHttpResponse *response = [self postImportRepoWithBody:small];
    XCTAssertEqual(response.statusCode, HttpStatusBadRequest);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidRequest");
}

- (void)testImportRepoRejectedWhenAcceptingImportsDisabled {
    [self applyConfigWithService:@{
        @"accepting_imports": @NO,
        @"max_import_size": @(1024 * 1024),
    }];
    XCTAssertFalse([ATProtoServiceConfiguration sharedConfiguration].acceptingImports);

    NSData *body = [@"any-body" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoHttpResponse *response = [self postImportRepoWithBody:body];
    XCTAssertEqual(response.statusCode, HttpStatusBadRequest);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidRequest");
    XCTAssertTrue([response.jsonBody[@"message"] containsString:@"not currently accepted"]);
}

- (void)testReimportOlderCarAppliesDeletes {
    // ADR 0035 B4 (diffing, matching upstream): re-importing a CAR whose
    // root differs from the current store state applies only the deltas —
    // records absent from the incoming export are deleted (with the root
    // rewound), unchanged records are left alone. Here the local store
    // diverges from an older CAR by adding a record, and re-importing the
    // older CAR must delete it.
    [self applyConfigWithService:@{
        @"max_import_size": @(1ULL * 1024ULL * 1024ULL * 1024ULL),
        @"accepting_imports": @YES,
    }];

    NSError *createError = nil;
    BOOL seededA = [self.controller putRecord:@"app.bsky.feed.post"
                                         rkey:@"diff-a"
                                        value:@{
                                            @"$type": @"app.bsky.feed.post",
                                            @"text": @"a",
                                            @"createdAt": [self iso8601String],
                                        }
                                       forDid:self.did1
                               validationMode:PDSValidationModeRequired
                                        error:&createError];
    XCTAssertTrue(seededA, @"%@", createError);
    BOOL seededB = [self.controller putRecord:@"app.bsky.feed.post"
                                         rkey:@"diff-b"
                                        value:@{
                                            @"$type": @"app.bsky.feed.post",
                                            @"text": @"b",
                                            @"createdAt": [self iso8601String],
                                        }
                                       forDid:self.did1
                               validationMode:PDSValidationModeRequired
                                        error:&createError];
    XCTAssertTrue(seededB, @"%@", createError);

    NSError *exportError = nil;
    NSData *carV1 = [self.controller.repositoryService getRepoContents:self.did1
                                                                   since:nil
                                                                   error:&exportError];
    XCTAssertNotNil(carV1);
    XCTAssertNil(exportError);

    // Re-importing an identical export is a no-op diff: the store already
    // holds these exact records, so nothing is added, updated, or deleted.
    ATProtoHttpResponse *first = [self postImportRepoWithBody:carV1];
    XCTAssertEqual(first.statusCode, HttpStatusOK, @"%@", first.jsonBody);
    XCTAssertEqual([first.jsonBody[@"addedCount"] integerValue], 0);
    XCTAssertEqual([first.jsonBody[@"deletedCount"] integerValue], 0);

    // Local divergence on top of the imported state.
    BOOL seededC = [self.controller putRecord:@"app.bsky.feed.post"
                                         rkey:@"diff-c"
                                        value:@{
                                            @"$type": @"app.bsky.feed.post",
                                            @"text": @"c",
                                            @"createdAt": [self iso8601String],
                                        }
                                       forDid:self.did1
                               validationMode:PDSValidationModeRequired
                                        error:&createError];
    XCTAssertTrue(seededC, @"%@", createError);

    // Re-importing the older CAR must apply the delta: diff-c is absent from
    // the incoming export, so it is deleted and the root rewinds to v1.
    ATProtoHttpResponse *second = [self postImportRepoWithBody:carV1];
    XCTAssertEqual(second.statusCode, HttpStatusOK, @"%@", second.jsonBody);
    XCTAssertEqual([second.jsonBody[@"deletedCount"] integerValue], 1,
                   @"Diff re-import must delete records absent from the incoming CAR");
    XCTAssertEqual([second.jsonBody[@"addedCount"] integerValue], 0);
    XCTAssertEqualObjects(second.jsonBody[@"rootCid"], first.jsonBody[@"rootCid"],
                          @"The store root must rewind to the imported CAR's root");

    // The actor store's signed head must rewind to the imported CAR's root.
    // (headInfoForDid: reads the same actor-store repo_root table that the
    // import transaction updates; getRepoRoot: reads a separate repo table.)
    NSError *headError = nil;
    NSDictionary *head = [self.controller.repositoryService headInfoForDid:self.did1 error:&headError];
    XCTAssertNotNil(head, @"%@", headError);
    XCTAssertNil(headError);
    XCTAssertEqualObjects(head[@"cid"], first.jsonBody[@"rootCid"]);

    // The deleted record must no longer resolve from the repo.
    NSString *deletedURI = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/diff-c", self.did1];
    NSError *recordError = nil;
    NSDictionary *deletedRecord = [self.controller getRecord:deletedURI forDid:self.did1 error:&recordError];
    XCTAssertNil(deletedRecord, @"Record absent from the re-imported CAR must be gone from the store");
}

- (void)testImportIntoRepoLessAccountAddsAllRecords {
    // ADR 0035 fresh-store path (the actual migration scenario): a BYO-DID
    // account is created deactivated with no repo, and the first importRepo
    // must add every record from the CAR (addedCount > 0), not treat the
    // store as already in sync. Simulated by seeding + exporting, then
    // clearing the repo root before the import.
    [self applyConfigWithService:@{
        @"max_import_size": @(1ULL * 1024ULL * 1024ULL * 1024ULL),
        @"accepting_imports": @YES,
    }];

    NSError *createError = nil;
    BOOL seeded = [self.controller putRecord:@"app.bsky.feed.post"
                                         rkey:@"fresh-a"
                                        value:@{
                                            @"$type": @"app.bsky.feed.post",
                                            @"text": @"fresh",
                                            @"createdAt": [self iso8601String],
                                        }
                                       forDid:self.did1
                               validationMode:PDSValidationModeRequired
                                        error:&createError];
    XCTAssertTrue(seeded, @"%@", createError);

    NSError *exportError = nil;
    NSData *carData = [self.controller.repositoryService getRepoContents:self.did1
                                                                   since:nil
                                                                   error:&exportError];
    XCTAssertNotNil(carData);
    XCTAssertNil(exportError);

    // Rewind the store to the pre-repo state the migration flow starts from.
    NSError *storeError = nil;
    PDSActorStore *store = [self.controller.recordService.databasePool storeForDid:self.did1 error:&storeError];
    XCTAssertNotNil(store, @"%@", storeError);
    XCTAssertTrue([store clearRepoRootWithError:&storeError], @"%@", storeError);
    NSData *noRoot = [store getRepoRootForDid:self.did1 error:nil];
    XCTAssertNil(noRoot, @"The actor store must have no repo root before the import");

    ATProtoHttpResponse *response = [self postImportRepoWithBody:carData];
    XCTAssertEqual(response.statusCode, HttpStatusOK, @"%@", response.jsonBody);
    XCTAssertGreaterThanOrEqual([response.jsonBody[@"addedCount"] integerValue], 1,
                                @"A repo-less store must add all records from the imported CAR");
    XCTAssertEqual([response.jsonBody[@"deletedCount"] integerValue], 0);

    // The imported record must resolve after the import.
    NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/fresh-a", self.did1];
    NSError *recordError = nil;
    NSDictionary *record = [self.controller getRecord:uri forDid:self.did1 error:&recordError];
    XCTAssertNotNil(record, @"%@", recordError);
    XCTAssertEqualObjects(record[@"uri"], uri);
}

- (void)testImportRepoDefaultsToAcceptingWithLargeCap {
    // Default posture: imports accepted, cap well above the old 16 MB
    // hardcoded constant (1 GiB upstream default). Restated explicitly so the
    // test does not depend on state left by earlier tests in the process.
    [self applyConfigWithService:@{
        @"max_import_size": @(1ULL * 1024ULL * 1024ULL * 1024ULL),
        @"accepting_imports": @YES,
    }];
    XCTAssertTrue([ATProtoServiceConfiguration sharedConfiguration].acceptingImports);
    XCTAssertGreaterThan([ATProtoServiceConfiguration sharedConfiguration].maxImportSize,
                         (NSUInteger)(16 * 1024 * 1024));

    // A valid repo export round-trips through the reworked streaming import.
    NSError *createError = nil;
    BOOL created = [self.controller putRecord:@"app.bsky.feed.post"
                                         rkey:@"import-scaling"
                                        value:@{
                                            @"$type": @"app.bsky.feed.post",
                                            @"text": @"import scaling test",
                                            @"createdAt": [self iso8601String],
                                        }
                                       forDid:self.did1
                               validationMode:PDSValidationModeRequired
                                        error:&createError];
    XCTAssertTrue(created, @"%@", createError);
    XCTAssertNil(createError);

    NSError *exportError = nil;
    NSData *carData = [self.controller.repositoryService getRepoContents:self.did1
                                                                   since:nil
                                                                   error:&exportError];
    XCTAssertNotNil(carData);
    XCTAssertNil(exportError);

    ATProtoHttpResponse *response = [self postImportRepoWithBody:carData];
    XCTAssertEqual(response.statusCode, HttpStatusOK, @"%@", response.jsonBody);
    XCTAssertNotNil(response.jsonBody[@"rootCid"]);
    XCTAssertGreaterThanOrEqual([response.jsonBody[@"recordCount"] integerValue], 1);
}

@end
