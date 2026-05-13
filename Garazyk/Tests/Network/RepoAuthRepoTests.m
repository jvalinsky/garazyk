// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "RepoAuthXrpcTestBase.h"
#import "Database/Service/ServiceDatabases.h"
#import "Network/RateLimiter.h"
#import "Services/PDS/PDSBlobService.h"
#import "Services/PDS/PDSRepositoryService.h"

@interface RepoAuthRepoTests : RepoAuthXrpcTestBase
@end

@implementation RepoAuthRepoTests

- (void)testDeleteRecordReturns401WithoutAuth {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"delete auth test",
        @"createdAt": [self iso8601String]
    };
    NSDictionary *created = [self.controller createRecordForDid:self.did1
                                                     collection:@"app.bsky.feed.post"
                                                        record:record
                                                validationMode:PDSValidationModeRequired
                                                         error:nil];
    XCTAssertNotNil(created);
    NSString *uri = created[@"uri"];
    NSString *rkey = [[uri componentsSeparatedByString:@"/"] lastObject];

    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.deleteRecord"
                                                      body:@{@"repo": self.did1,
                                                             @"collection": @"app.bsky.feed.post",
                                                             @"rkey": rkey}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testPutRecordReturns401WithoutAuth {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"put auth test",
        @"createdAt": [self iso8601String]
    };
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.putRecord"
                                                      body:@{@"repo": self.did1,
                                                             @"collection": @"app.bsky.feed.post",
                                                             @"rkey": @"auth-test",
                                                             @"record": record}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testUpdateRecordReturns401WithoutAuth {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"update auth test",
        @"createdAt": [self iso8601String]
    };
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.updateRecord"
                                                      body:@{@"repo": self.did1,
                                                             @"collection": @"app.bsky.feed.post",
                                                             @"rkey": @"auth-update-test",
                                                             @"record": record}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testApplyWritesReturns401WithoutAuth {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"apply auth test",
        @"createdAt": [self iso8601String]
    };
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.applyWrites"
                                                      body:@{@"repo": self.did1,
                                                             @"writes": @[@{@"action": @"create",
                                                                            @"collection": @"app.bsky.feed.post",
                                                                            @"record": record}]}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testPutRecordRepoMismatchForbidden {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"put mismatch test",
        @"createdAt": [self iso8601String]
    };
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.putRecord"
                                                      body:@{@"repo": self.did2,
                                                             @"collection": @"app.bsky.feed.post",
                                                             @"rkey": @"auth-mismatch",
                                                             @"record": record}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 403);
}

- (void)testUpdateRecordUpdatesExistingRecord {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"before update",
        @"createdAt": [self iso8601String]
    };
    NSDictionary *created = [self.controller createRecordForDid:self.did1
                                                     collection:@"app.bsky.feed.post"
                                                        record:record
                                                validationMode:PDSValidationModeRequired
                                                         error:nil];
    XCTAssertNotNil(created);
    NSString *uri = created[@"uri"];
    NSString *rkey = [[uri componentsSeparatedByString:@"/"] lastObject];
    XCTAssertTrue(rkey.length > 0);

    NSDictionary *updatedRecord = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"after update",
        @"createdAt": [self iso8601String]
    };
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.updateRecord"
                                                      body:@{@"repo": self.did1,
                                                             @"collection": @"app.bsky.feed.post",
                                                             @"rkey": rkey,
                                                             @"record": updatedRecord}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    NSString *expectedURI = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/%@", self.did1, rkey];
    XCTAssertEqualObjects(response.jsonBody[@"uri"], expectedURI);
    XCTAssertNotNil(response.jsonBody[@"cid"]);

    NSDictionary *fetched = [self.controller getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/%@", self.did1, rkey]
                                                 forDid:self.did1
                                                  error:nil];
    XCTAssertNotNil(fetched);
    XCTAssertEqualObjects(fetched[@"value"][@"text"], @"after update");
}

- (void)testGetBlobReturns401WithoutAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.repo.getBlob"
                                               queryParams:@{@"cid": @"bafkqaaa"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testGetBlobReturnsBlobForAuthorizedOwner {
    NSData *blobData = [@"hello-repo-getBlob" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *uploadError = nil;
    NSDictionary *uploadResult = [self.controller.blobService uploadBlob:blobData
                                                                   forDid:self.did1
                                                                  mimeType:@"text/plain"
                                                                    error:&uploadError];
    XCTAssertNotNil(uploadResult);
    XCTAssertNil(uploadError);
    NSString *cid = uploadResult[@"blob"][@"ref"][@"$link"];
    XCTAssertTrue(cid.length > 0);

    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.repo.getBlob"
                                               queryParams:@{@"cid": cid, @"did": self.did1}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);

    NSError *readError = nil;
    NSData *responseData = [self drainResponseBody:response error:&readError];
    XCTAssertNil(readError);
    XCTAssertEqualObjects(responseData, blobData);
}

- (void)testGetBlobRepoMismatchForbidden {
    NSData *blobData = [@"hello-repo-getBlob-forbidden" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *uploadResult = [self.controller.blobService uploadBlob:blobData
                                                                   forDid:self.did1
                                                                  mimeType:@"text/plain"
                                                                    error:nil];
    NSString *cid = uploadResult[@"blob"][@"ref"][@"$link"];
    XCTAssertTrue(cid.length > 0);

    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.repo.getBlob"
                                               queryParams:@{@"cid": cid, @"did": self.did2}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 403);
}

- (void)testUploadBlobReturns429WhenBlobQuotaExceeded {
    RateLimiter *limiter = [RateLimiter sharedLimiter];
    BOOL oldEnabled = limiter.enabled;
    NSInteger oldBlobLimit = limiter.blobLimit;
    NSTimeInterval oldBlobWindow = limiter.blobWindowSeconds;
    NSString *rateLimitPath = [self.tempURL.path stringByAppendingPathComponent:@"upload_blob_rate_limit.sqlite"];

    RateLimiterSetDisabledGlobally(NO);
    [limiter reconfigureDatabasePath:rateLimitPath];
    limiter.enabled = YES;
    limiter.blobLimit = 1;
    limiter.blobWindowSeconds = 3600;

    @try {
        NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
        NSData *firstBlob = [@"first blob" dataUsingEncoding:NSUTF8StringEncoding];
        HttpResponse *firstResponse = [self sendRawPostRequestWithPath:@"/xrpc/com.atproto.repo.uploadBlob"
                                                               bodyData:firstBlob
                                                                headers:@{
                                                                    @"authorization": authHeader,
                                                                    @"content-type": @"text/plain"
                                                                }];
        XCTAssertEqual(firstResponse.statusCode, 200);

        NSData *secondBlob = [@"second blob" dataUsingEncoding:NSUTF8StringEncoding];
        HttpResponse *secondResponse = [self sendRawPostRequestWithPath:@"/xrpc/com.atproto.repo.uploadBlob"
                                                                bodyData:secondBlob
                                                                 headers:@{
                                                                     @"authorization": authHeader,
                                                                     @"content-type": @"text/plain"
                                                                 }];
        XCTAssertEqual(secondResponse.statusCode, 429);
        XCTAssertEqualObjects(secondResponse.jsonBody[@"error"], @"RateLimitExceeded");
        XCTAssertNotNil([secondResponse headerForKey:@"Retry-After"]);
    } @finally {
        limiter.blobLimit = oldBlobLimit;
        limiter.blobWindowSeconds = oldBlobWindow;
        limiter.enabled = oldEnabled;
        [limiter reconfigureDatabasePath:nil];
        [[NSFileManager defaultManager] removeItemAtPath:rateLimitPath error:nil];
        RateLimiterSetDisabledGlobally(YES);
    }
}

- (void)testCreateReplyReturnsReplyNotAllowedForClosedThreadgate {
    NSError *loginError = nil;
    NSDictionary *session2 = [self.controller loginWithHandle:@"repoauth2.test" password:@"password" error:&loginError];
    XCTAssertNil(loginError);
    NSString *auth1 = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    NSString *auth2 = [NSString stringWithFormat:@"Bearer %@", session2[@"accessJwt"]];

    HttpResponse *postResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.createRecord"
                                                          body:@{@"repo": self.did1,
                                                                 @"collection": @"app.bsky.feed.post",
                                                                 @"rkey": @"closed-root",
                                                                 @"record": @{@"$type": @"app.bsky.feed.post",
                                                                              @"text": @"closed root",
                                                                              @"createdAt": [self iso8601String]}}
                                                       headers:@{@"authorization": auth1}];
    XCTAssertEqual(postResponse.statusCode, 200);
    NSString *rootURI = postResponse.jsonBody[@"uri"];
    NSString *rootCID = postResponse.jsonBody[@"cid"];
    XCTAssertTrue(rootURI.length > 0);

    HttpResponse *gateResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.createRecord"
                                                          body:@{@"repo": self.did1,
                                                                 @"collection": @"app.bsky.feed.threadgate",
                                                                 @"rkey": @"closed-gate",
                                                                 @"record": @{@"$type": @"app.bsky.feed.threadgate",
                                                                              @"post": rootURI,
                                                                              @"allow": @[],
                                                                              @"createdAt": [self iso8601String]}}
                                                       headers:@{@"authorization": auth1}];
    XCTAssertEqual(gateResponse.statusCode, 200);

    NSDictionary *reply = @{@"$type": @"app.bsky.feed.post",
                            @"text": @"denied reply",
                            @"createdAt": [self iso8601String],
                            @"reply": @{@"root": @{@"uri": rootURI, @"cid": rootCID ?: @""},
                                        @"parent": @{@"uri": rootURI, @"cid": rootCID ?: @""}}};
    HttpResponse *replyResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.createRecord"
                                                           body:@{@"repo": self.did2,
                                                                  @"collection": @"app.bsky.feed.post",
                                                                  @"rkey": @"denied-reply",
                                                                  @"record": reply}
                                                        headers:@{@"authorization": auth2}];
    XCTAssertEqual(replyResponse.statusCode, 400);
    XCTAssertEqualObjects(replyResponse.jsonBody[@"error"], @"ReplyNotAllowed");
}

- (void)testCreateReplyAllowedForFollowerThreadgate {
    NSError *loginError = nil;
    NSDictionary *session2 = [self.controller loginWithHandle:@"repoauth2.test" password:@"password" error:&loginError];
    XCTAssertNil(loginError);
    NSString *auth1 = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    NSString *auth2 = [NSString stringWithFormat:@"Bearer %@", session2[@"accessJwt"]];

    HttpResponse *followResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.createRecord"
                                                            body:@{@"repo": self.did2,
                                                                   @"collection": @"app.bsky.graph.follow",
                                                                   @"rkey": @"follow-root-author",
                                                                   @"record": @{@"$type": @"app.bsky.graph.follow",
                                                                                @"subject": self.did1,
                                                                                @"createdAt": [self iso8601String]}}
                                                         headers:@{@"authorization": auth2}];
    XCTAssertEqual(followResponse.statusCode, 200);

    HttpResponse *postResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.createRecord"
                                                          body:@{@"repo": self.did1,
                                                                 @"collection": @"app.bsky.feed.post",
                                                                 @"rkey": @"followers-root",
                                                                 @"record": @{@"$type": @"app.bsky.feed.post",
                                                                              @"text": @"followers root",
                                                                              @"createdAt": [self iso8601String]}}
                                                       headers:@{@"authorization": auth1}];
    XCTAssertEqual(postResponse.statusCode, 200);
    NSString *rootURI = postResponse.jsonBody[@"uri"];
    NSString *rootCID = postResponse.jsonBody[@"cid"];

    HttpResponse *gateResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.createRecord"
                                                          body:@{@"repo": self.did1,
                                                                 @"collection": @"app.bsky.feed.threadgate",
                                                                 @"rkey": @"followers-gate",
                                                                 @"record": @{@"$type": @"app.bsky.feed.threadgate",
                                                                              @"post": rootURI,
                                                                              @"allow": @[@{@"$type": @"app.bsky.feed.threadgate#followerRule"}],
                                                                              @"createdAt": [self iso8601String]}}
                                                       headers:@{@"authorization": auth1}];
    XCTAssertEqual(gateResponse.statusCode, 200);

    NSDictionary *reply = @{@"$type": @"app.bsky.feed.post",
                            @"text": @"allowed follower reply",
                            @"createdAt": [self iso8601String],
                            @"reply": @{@"root": @{@"uri": rootURI, @"cid": rootCID ?: @""},
                                        @"parent": @{@"uri": rootURI, @"cid": rootCID ?: @""}}};
    HttpResponse *replyResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.createRecord"
                                                           body:@{@"repo": self.did2,
                                                                  @"collection": @"app.bsky.feed.post",
                                                                  @"rkey": @"allowed-follower-reply",
                                                                  @"record": reply}
                                                        headers:@{@"authorization": auth2}];
    XCTAssertEqual(replyResponse.statusCode, 200);
}

- (void)testRepoListMissingBlobsReturns401WithoutAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.repo.listMissingBlobs"
                                               queryParams:@{}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testRepoListMissingBlobsReturnsEmptyList {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.repo.listMissingBlobs"
                                               queryParams:@{@"limit": @"10"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"blobs"]);
    XCTAssertTrue([response.jsonBody[@"blobs"] isKindOfClass:[NSArray class]]);
}

- (void)testRepoImportRepoReturns401WithoutAuth {
    NSData *carData = [@"fakecar" dataUsingEncoding:NSUTF8StringEncoding];
    HttpResponse *response = [self sendRawPostRequestWithPath:@"/xrpc/com.atproto.repo.importRepo"
                                                     bodyData:carData
                                                      headers:@{
                                                          @"content-type": @"application/vnd.ipld.car",
                                                          @"content-length": [NSString stringWithFormat:@"%lu", (unsigned long)carData.length]
                                                      }];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testRepoImportRepoReturnsBadRequestWithoutContentLengthHeader {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    NSData *carData = [@"fakecar" dataUsingEncoding:NSUTF8StringEncoding];
    HttpResponse *response = [self sendRawPostRequestWithPath:@"/xrpc/com.atproto.repo.importRepo"
                                                     bodyData:carData
                                                      headers:@{
                                                          @"authorization": authHeader,
                                                          @"content-type": @"application/vnd.ipld.car"
                                                      }];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testRepoImportRepoReturnsBadRequestForInvalidCAR {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    NSData *carData = [@"fakecar" dataUsingEncoding:NSUTF8StringEncoding];
    HttpResponse *response = [self sendRawPostRequestWithPath:@"/xrpc/com.atproto.repo.importRepo"
                                                     bodyData:carData
                                                      headers:@{
                                                          @"authorization": authHeader,
                                                          @"content-type": @"application/vnd.ipld.car",
                                                          @"content-length": [NSString stringWithFormat:@"%lu", (unsigned long)carData.length]
                                                      }];
    XCTAssertEqual(response.statusCode, 400);
    NSDictionary *body = (NSDictionary *)response.jsonBody;
    XCTAssertEqualObjects(body[@"error"], @"InvalidRequest");
}

- (void)testRepoImportRepoSucceedsForValidExportedCAR {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"import repo test",
        @"createdAt": [self iso8601String]
    };
    NSError *createError = nil;
    NSDictionary *created = [self.controller createRecordForDid:self.did1
                                                     collection:@"app.bsky.feed.post"
                                                        record:record
                                                validationMode:PDSValidationModeRequired
                                                         error:&createError];
    XCTAssertNotNil(created);
    XCTAssertNil(createError);

    NSError *exportError = nil;
    NSData *carData = [self.controller.repositoryService getRepoContents:self.did1
                                                                   since:nil
                                                                   error:&exportError];
    XCTAssertNotNil(carData);
    XCTAssertNil(exportError);

    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *response = [self sendRawPostRequestWithPath:@"/xrpc/com.atproto.repo.importRepo"
                                                     bodyData:carData
                                                      headers:@{
                                                          @"authorization": authHeader,
                                                          @"content-type": @"application/vnd.ipld.car",
                                                          @"content-length": [NSString stringWithFormat:@"%lu", (unsigned long)carData.length]
                                                      }];
    XCTAssertEqual(response.statusCode, 200);
    NSDictionary *body = (NSDictionary *)response.jsonBody;
    XCTAssertNotNil(body[@"rootCid"]);
    XCTAssertNotNil(body[@"rev"]);
    XCTAssertTrue([body[@"recordCount"] integerValue] >= 1);
}

@end
