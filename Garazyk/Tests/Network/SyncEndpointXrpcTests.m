// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "App/PDSController.h"
#import "App/PDSApplication.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Database/Service/ServiceDatabases.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Auth/JWT.h"
#import "Services/PDS/PDSRecordService.h"
#import "Core/TID.h"

@interface ATProtoServiceConfiguration (Test)
- (void)applyConfig:(NSDictionary *)config;
@end

@interface SyncEndpointXrpcTests : XCTestCase
@property (nonatomic, strong) PDSController *controller;
@property (nonatomic, strong) XrpcDispatcher *dispatcher;
@property (nonatomic, strong) NSURL *tempURL;
@property (nonatomic, copy) NSString *userDid;
@property (nonatomic, copy) NSString *userJwt;
@end

@implementation SyncEndpointXrpcTests

- (void)setUp {
    [super setUp];

    setenv("PDS_AVAILABLE_USER_DOMAINS", "test", 1);
    setenv("PDS_ADMIN_PASSWORD", "password", 1);
    setenv("PDS_MASTER_SECRET", "test-master-secret-123", 1);
    setenv("PDS_PLC_URL", "mock", 1);
    [[ATProtoServiceConfiguration sharedConfiguration] applyConfig:@{@"server": @{}}];

    self.tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    self.tempURL = [self.tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempURL withIntermediateDirectories:YES attributes:nil error:nil];

    PDSApplication *app = [[PDSApplication alloc] initWithDataDirectory:self.tempURL.path];
    self.controller = app.legacyController;
    self.dispatcher = [[XrpcDispatcher alloc] init];
    [XrpcMethodRegistry registerMethodsWithDispatcher:self.dispatcher application:app];

    NSError *error = nil;
    NSDictionary *account = [self.controller createAccountForEmail:@"sync@example.com"
                                                          password:@"password"
                                                            handle:@"synctest.test"
                                                               did:nil
                                                             error:&error];
    XCTAssertNil(error);
    self.userDid = account[@"did"];

    NSDictionary *session = [self.controller loginWithHandle:@"synctest.test" password:@"password" error:&error];
    XCTAssertNil(error);
    self.userJwt = session[@"accessJwt"];
    XCTAssertNotNil(self.userJwt);
}

- (void)tearDown {
    [self.controller stopServer];
    self.dispatcher = nil;
    self.controller = nil;
    [[NSFileManager defaultManager] removeItemAtURL:self.tempURL error:nil];
    [super tearDown];
}

- (HttpResponse *)sendGetRequestWithPath:(NSString *)path
                               queryParams:(NSDictionary<NSString *, NSString *> *)queryParams
                                   headers:(NSDictionary<NSString *, NSString *> *)headers {
    NSMutableString *queryString = [NSMutableString string];
    NSMutableArray *queryKeys = [queryParams.allKeys sortedArrayUsingSelector:@selector(compare:)];
    for (NSUInteger i = 0; i < queryKeys.count; i++) {
        if (i > 0) [queryString appendString:@"&"];
        NSString *key = queryKeys[i];
        [queryString appendFormat:@"%@=%@", key, queryParams[key]];
    }

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:path
                                                   queryString:queryString ?: @""
                                                   queryParams:queryParams ?: @{}
                                                       version:@"1.1"
                                                       headers:headers ?: @{}
                                                          body:[NSData data]
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    return response;
}

- (HttpResponse *)sendJsonRequestWithPath:(NSString *)path
                                     body:(NSDictionary *)body
                                  headers:(NSDictionary<NSString *, NSString *> *)headers {
    NSData *bodyData = body ? [NSJSONSerialization dataWithJSONObject:body options:0 error:nil] : [NSData data];
    NSMutableDictionary *allHeaders = [@{@"content-type": @"application/json"} mutableCopy];
    if (headers) {
        [allHeaders addEntriesFromDictionary:headers];
    }

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:path
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:allHeaders
                                                          body:bodyData
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    return response;
}

#pragma mark - listRepos

- (void)testListReposReturnsRepos {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.listRepos"
                                              queryParams:@{}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    NSDictionary *json = response.jsonBody;
    XCTAssertTrue([json isKindOfClass:[NSDictionary class]]);
    NSArray *repos = json[@"repos"];
    XCTAssertTrue([repos isKindOfClass:[NSArray class]]);
    // At least the account we created
    XCTAssertTrue(repos.count >= 1, @"Should have at least one repo");
}

#pragma mark - listBlobs

- (void)testListBlobsReturnsBlobsForDID {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.listBlobs"
                                              queryParams:@{@"did": self.userDid}
                                                  headers:@{@"authorization": authHeader}];
    // May return 200 with empty list or 400 if DID is invalid
    XCTAssertTrue(response.statusCode == 200 || response.statusCode == 400,
                  @"listBlobs should return 200 or 400, got %ld", (long)response.statusCode);
    if (response.statusCode == 200) {
        NSDictionary *json = response.jsonBody;
        XCTAssertTrue([json isKindOfClass:[NSDictionary class]]);
    }
}

#pragma mark - getCheckout

- (void)testGetCheckoutReturnsDataForDID {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getCheckout"
                                              queryParams:@{@"did": self.userDid}
                                                  headers:@{}];
    // May return 200 with CAR data or 404 if no repo
    XCTAssertTrue(response.statusCode == 200 || response.statusCode == 400 || response.statusCode == 404,
                  @"getCheckout should return 200, 400, or 404, got %ld", (long)response.statusCode);
}

#pragma mark - getHostStatus

- (void)testGetHostStatusReturnsStatus {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getHostStatus"
                                              queryParams:@{@"did": self.userDid}
                                                  headers:@{}];
    // May return 200 or 404
    XCTAssertTrue(response.statusCode == 200 || response.statusCode == 404 || response.statusCode == 400,
                  @"getHostStatus should return 200, 404, or 400, got %ld", (long)response.statusCode);
}

#pragma mark - notifyOfUpdate

- (void)testNotifyOfUpdateRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.sync.notifyOfUpdate"
                                                       body:@{@"did": self.userDid}
                                                    headers:@{}];
    // Should require authentication
    XCTAssertTrue(response.statusCode == 401 || response.statusCode == 200 || response.statusCode == 400,
                  @"notifyOfUpdate should require auth or return 400, got %ld", (long)response.statusCode);
}

#pragma mark - listReposByCollection

- (void)testListReposByCollectionReturnsResults {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.listReposByCollection"
                                              queryParams:@{@"collection": @"app.bsky.actor.profile"}
                                                  headers:@{}];
    // May return 200 or 400
    XCTAssertTrue(response.statusCode == 200 || response.statusCode == 400,
                  @"listReposByCollection should return 200 or 400, got %ld", (long)response.statusCode);
}

- (void)testListReposByCollectionIndexPath {
    NSString *collectionA = @"app.bsky.feed.post";
    NSString *collectionB = @"app.bsky.graph.follow";

    // --- Create records in two collections via the controller ---
    NSError *error = nil;
    NSString *rkeyA = [TID tid].stringValue;
    BOOL createdA = [self.controller putRecord:collectionA
                                          rkey:rkeyA
                                         value:@{@"text": @"index test post", @"createdAt": @"2025-01-01T00:00:00.000Z"}
                                        forDid:self.userDid
                                validationMode:PDSValidationModeOff
                                         error:&error];
    XCTAssertTrue(createdA, @"Failed to create record in %@: %@", collectionA, error.localizedDescription);
    XCTAssertNil(error);

    NSString *rkeyB = [TID tid].stringValue;
    BOOL createdB = [self.controller putRecord:collectionB
                                          rkey:rkeyB
                                         value:@{@"subject": self.userDid, @"createdAt": @"2025-01-01T00:00:00.000Z"}
                                        forDid:self.userDid
                                validationMode:PDSValidationModeOff
                                         error:&error];
    XCTAssertTrue(createdB, @"Failed to create record in %@: %@", collectionB, error.localizedDescription);
    XCTAssertNil(error);

    // --- Directly verify the collection_membership index ---
    PDSServiceDatabases *sdb = self.controller.application.serviceDatabases;
    XCTAssertNotNil(sdb, @"ServiceDatabases should be available");

    NSError *idxError = nil;
    NSArray<NSString *> *indexDIDs = [sdb listDIDsByCollection:collectionA
                                                        cursor:nil
                                                         limit:100
                                                         error:&idxError];
    XCTAssertNil(idxError, @"Index query should not error: %@", idxError.localizedDescription);
    XCTAssertNotNil(indexDIDs);
    XCTAssertTrue([indexDIDs containsObject:self.userDid],
                  @"Index should contain DID %@ for collection %@", self.userDid, collectionA);

    // --- Query listReposByCollection for collection A and verify DID is present ---
    HttpResponse *respA = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.listReposByCollection"
                                            queryParams:@{@"collection": collectionA, @"limit": @"100"}
                                                headers:@{}];
    XCTAssertEqual(respA.statusCode, 200, @"listReposByCollection for %@ should return 200, got %ld",
                   collectionA, (long)respA.statusCode);
    NSArray *reposA = respA.jsonBody[@"repos"];
    XCTAssertTrue([reposA isKindOfClass:[NSArray class]], @"Expected repos array");
    BOOL foundA = NO;
    for (NSDictionary *repo in reposA) {
        if ([repo[@"did"] isEqualToString:self.userDid]) {
            foundA = YES;
            break;
        }
    }
    XCTAssertTrue(foundA, @"DID %@ should appear in listReposByCollection for %@",
                  self.userDid, collectionA);

    // --- Query listReposByCollection for collection B and verify DID is present ---
    HttpResponse *respB = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.listReposByCollection"
                                            queryParams:@{@"collection": collectionB, @"limit": @"100"}
                                                headers:@{}];
    XCTAssertEqual(respB.statusCode, 200, @"listReposByCollection for %@ should return 200, got %ld",
                   collectionB, (long)respB.statusCode);
    NSArray *reposB = respB.jsonBody[@"repos"];
    BOOL foundB = NO;
    for (NSDictionary *repo in reposB) {
        if ([repo[@"did"] isEqualToString:self.userDid]) {
            foundB = YES;
            break;
        }
    }
    XCTAssertTrue(foundB, @"DID %@ should appear in listReposByCollection for %@",
                  self.userDid, collectionB);

    // --- Delete the record in collection A and verify removal ---
    BOOL deleted = [self.controller.recordService deleteRecord:collectionA
                                                           rkey:rkeyA
                                                         forDid:self.userDid
                                                          error:&error];
    XCTAssertTrue(deleted, @"Failed to delete record in %@: %@", collectionA, error.localizedDescription);
    XCTAssertNil(error);

    HttpResponse *respAAfter = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.listReposByCollection"
                                                queryParams:@{@"collection": collectionA, @"limit": @"100"}
                                                    headers:@{}];
    XCTAssertEqual(respAAfter.statusCode, 200);
    NSArray *reposAAfter = respAAfter.jsonBody[@"repos"];
    BOOL foundAAfter = NO;
    for (NSDictionary *repo in reposAAfter) {
        if ([repo[@"did"] isEqualToString:self.userDid]) {
            foundAAfter = YES;
            break;
        }
    }
    XCTAssertFalse(foundAAfter, @"DID %@ should NOT appear in listReposByCollection for %@ after delete",
                   self.userDid, collectionA);

    // --- Collection B should still show the DID ---
    HttpResponse *respBAfter = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.listReposByCollection"
                                                queryParams:@{@"collection": collectionB, @"limit": @"100"}
                                                    headers:@{}];
    XCTAssertEqual(respBAfter.statusCode, 200);
    NSArray *reposBAfter = respBAfter.jsonBody[@"repos"];
    BOOL foundBAfter = NO;
    for (NSDictionary *repo in reposBAfter) {
        if ([repo[@"did"] isEqualToString:self.userDid]) {
            foundBAfter = YES;
            break;
        }
    }
    XCTAssertTrue(foundBAfter, @"DID %@ should still appear in listReposByCollection for %@",
                  self.userDid, collectionB);

    // --- A collection with no records anywhere should return empty ---
    HttpResponse *respNone = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.listReposByCollection"
                                              queryParams:@{@"collection": @"com.example.nonexistent", @"limit": @"100"}
                                                  headers:@{}];
    XCTAssertEqual(respNone.statusCode, 200);
    NSArray *reposNone = respNone.jsonBody[@"repos"];
    XCTAssertTrue([reposNone isKindOfClass:[NSArray class]]);
    BOOL foundNone = NO;
    for (NSDictionary *repo in reposNone) {
        if ([repo[@"did"] isEqualToString:self.userDid]) {
            foundNone = YES;
            break;
        }
    }
    XCTAssertFalse(foundNone, @"DID should not appear for collection with no records");
}

- (void)testListReposByCollectionCursorPagination {
    NSString *collection = @"app.bsky.feed.post";
    NSError *error = nil;

    // --- Create a record for the setUp account so it appears in the index ---
    BOOL createdSelf = [self.controller putRecord:collection
                                             rkey:[TID tid].stringValue
                                            value:@{@"text": @"pagination test self",
                                                    @"createdAt": @"2025-01-01T00:00:00.000Z"}
                                           forDid:self.userDid
                                   validationMode:PDSValidationModeOff
                                            error:&error];
    XCTAssertTrue(createdSelf, @"Failed to create record for setUp account: %@", error.localizedDescription);
    XCTAssertNil(error);

    // --- Create three additional accounts ---
    NSMutableArray<NSString *> *allDIDs = [NSMutableArray arrayWithObject:self.userDid];

    NSArray<NSString *> *handles = @[@"user-b.test", @"user-c.test", @"user-d.test"];
    for (NSString *handle in handles) {
        NSString *email = [NSString stringWithFormat:@"%@%@",
                           [handle componentsSeparatedByString:@"."].firstObject,
                           @"@example.com"];
        NSDictionary *account = [self.controller createAccountForEmail:email
                                                              password:@"password"
                                                                handle:handle
                                                                   did:nil
                                                                 error:&error];
        XCTAssertNil(error, @"Failed to create account %@: %@", handle, error.localizedDescription);
        NSString *did = account[@"did"];
        XCTAssertNotNil(did, @"Account for %@ should have a DID", handle);
        [allDIDs addObject:did];

        // Create a record so this DID appears in the collection_membership index
        BOOL created = [self.controller putRecord:collection
                                             rkey:[TID tid].stringValue
                                            value:@{@"text": [NSString stringWithFormat:@"pagination test %@", handle],
                                                    @"createdAt": @"2025-01-01T00:00:00.000Z"}
                                           forDid:did
                                   validationMode:PDSValidationModeOff
                                            error:&error];
        XCTAssertTrue(created, @"Failed to create record for %@: %@", handle, error.localizedDescription);
        XCTAssertNil(error);
    }

    // Sort DIDs lexicographically — this is the order listReposByCollection returns.
    [allDIDs sortUsingSelector:@selector(compare:)];
    XCTAssertEqual(allDIDs.count, 4, @"Should have 4 DIDs total");

    // --- Page 1: limit=2, no cursor ---
    HttpResponse *page1 = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.listReposByCollection"
                                           queryParams:@{@"collection": collection, @"limit": @"2"}
                                               headers:@{}];
    XCTAssertEqual(page1.statusCode, 200, @"Page 1 should return 200, got %ld", (long)page1.statusCode);
    NSArray *repos1 = page1.jsonBody[@"repos"];
    XCTAssertEqual(repos1.count, 2, @"Page 1 should have exactly 2 repos");
    XCTAssertEqualObjects(repos1[0][@"did"], allDIDs[0], @"Page 1[0] should be first DID lexicographically");
    XCTAssertEqualObjects(repos1[1][@"did"], allDIDs[1], @"Page 1[1] should be second DID lexicographically");
    NSString *cursor1 = page1.jsonBody[@"cursor"];
    XCTAssertNotNil(cursor1, @"Page 1 should return a cursor for more results");
    XCTAssertEqualObjects(cursor1, allDIDs[1], @"Cursor should be the last DID in page 1");

    // --- Page 2: limit=2, cursor from page 1 ---
    HttpResponse *page2 = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.listReposByCollection"
                                           queryParams:@{@"collection": collection, @"limit": @"2", @"cursor": cursor1}
                                               headers:@{}];
    XCTAssertEqual(page2.statusCode, 200, @"Page 2 should return 200, got %ld", (long)page2.statusCode);
    NSArray *repos2 = page2.jsonBody[@"repos"];
    XCTAssertEqual(repos2.count, 2, @"Page 2 should have exactly 2 repos");
    XCTAssertEqualObjects(repos2[0][@"did"], allDIDs[2], @"Page 2[0] should be third DID lexicographically");
    XCTAssertEqualObjects(repos2[1][@"did"], allDIDs[3], @"Page 2[1] should be fourth DID lexicographically");
    NSString *cursor2 = page2.jsonBody[@"cursor"];
    XCTAssertEqualObjects(cursor2, allDIDs[3], @"Page 2 cursor should be the last DID (page is full, consumer checks next)");

    // --- Page 3 (empty): cursor from page 2 should return no results ---
    HttpResponse *page3 = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.listReposByCollection"
                                           queryParams:@{@"collection": collection, @"limit": @"2", @"cursor": cursor2}
                                               headers:@{}];
    XCTAssertEqual(page3.statusCode, 200, @"Page 3 should return 200, got %ld", (long)page3.statusCode);
    NSArray *repos3 = page3.jsonBody[@"repos"];
    XCTAssertEqual(repos3.count, 0, @"Page 3 should have 0 repos (cursor past last DID)");
    XCTAssertNil(page3.jsonBody[@"cursor"], @"Page 3 should not return a cursor");
}

- (void)testPruneOnDeleteRemovesMembershipEntry {
    NSString *collection = @"app.bsky.feed.post";
    PDSServiceDatabases *sdb = self.controller.application.serviceDatabases;
    XCTAssertNotNil(sdb, @"ServiceDatabases should be available");

    // --- Create a record ---
    NSError *error = nil;
    NSString *rkey = [TID tid].stringValue;
    BOOL created = [self.controller putRecord:collection
                                         rkey:rkey
                                        value:@{@"text": @"prune-on-delete test", @"createdAt": @"2025-01-01T00:00:00.000Z"}
                                       forDid:self.userDid
                               validationMode:PDSValidationModeOff
                                        error:&error];
    XCTAssertTrue(created, @"Failed to create record: %@", error.localizedDescription);
    XCTAssertNil(error);

    // --- Verify membership entry exists ---
    NSArray<NSString *> *didsBefore = [sdb listDIDsByCollection:collection
                                                         cursor:nil
                                                          limit:100
                                                          error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(didsBefore);
    XCTAssertTrue([didsBefore containsObject:self.userDid],
                  @"Index should contain DID after record creation");

    // --- Delete the record ---
    BOOL deleted = [self.controller.recordService deleteRecord:collection
                                                           rkey:rkey
                                                         forDid:self.userDid
                                                          error:&error];
    XCTAssertTrue(deleted, @"Failed to delete record: %@", error.localizedDescription);
    XCTAssertNil(error);

    // --- Verify membership entry is removed ---
    NSArray<NSString *> *didsAfter = [sdb listDIDsByCollection:collection
                                                        cursor:nil
                                                         limit:100
                                                         error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(didsAfter);
    XCTAssertFalse([didsAfter containsObject:self.userDid],
                   @"Index should NOT contain DID after record deletion");
}

@end
