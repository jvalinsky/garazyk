#import <XCTest/XCTest.h>
#import "App/PDSApplication.h"
#import "App/PDSController.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Pool/DatabasePool.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Repository/CAR.h"
#import "Repository/CBOR.h"

@interface AdminAuthApplicationXrpcTests : XCTestCase
@property (nonatomic, strong) PDSApplication *application;
@property (nonatomic, strong) XrpcDispatcher *dispatcher;
@property (nonatomic, strong) NSURL *tempURL;
@property (nonatomic, copy) NSString *adminJwt;
@property (nonatomic, copy) NSString *userDid;
@property (nonatomic, copy) NSString *userJwt;
@end

@implementation AdminAuthApplicationXrpcTests

- (void)setUp {
    [super setUp];

    self.tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    self.tempURL = [self.tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempURL
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];

    self.application = [[PDSApplication alloc] initWithDataDirectory:self.tempURL.path];
    self.dispatcher = [[XrpcDispatcher alloc] init];
    [XrpcMethodRegistry registerMethodsWithDispatcher:self.dispatcher application:self.application];

    NSError *error = nil;
    NSDictionary *adminAccount = [self.application.legacyController createAccountForEmail:@"admin-app@example.com"
                                                                                  password:@"password"
                                                                                    handle:@"admin.app.test"
                                                                                       did:nil
                                                                                     error:&error];
    XCTAssertNil(error);
    self.adminJwt = adminAccount[@"accessJwt"];
    XCTAssertTrue(self.adminJwt.length > 0);

    NSDictionary *userAccount = [self.application.legacyController createAccountForEmail:@"user-app@example.com"
                                                                                 password:@"password"
                                                                                   handle:@"user.app.test"
                                                                                      did:nil
                                                                                    error:&error];
    XCTAssertNil(error);
    self.userDid = userAccount[@"did"];
    self.userJwt = userAccount[@"accessJwt"];
    XCTAssertTrue(self.userDid.length > 0);
    XCTAssertTrue(self.userJwt.length > 0);
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtURL:self.tempURL error:nil];
    [super tearDown];
}

- (HttpResponse *)sendJsonRequestWithPath:(NSString *)path
                                     body:(NSDictionary *)body
                                  headers:(NSDictionary<NSString *, NSString *> *)headers {
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body ?: @{} options:0 error:nil];
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

- (HttpResponse *)sendGetRequestWithPath:(NSString *)path
                              queryString:(NSString *)queryString
                              queryParams:(NSDictionary<NSString *, NSString *> *)queryParams
                                  headers:(NSDictionary<NSString *, NSString *> *)headers {
    NSMutableDictionary *allHeaders = [NSMutableDictionary dictionary];
    if (headers) {
        [allHeaders addEntriesFromDictionary:headers];
    }

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:path
                                                   queryString:queryString ?: @""
                                                   queryParams:queryParams ?: @{}
                                                       version:@"1.1"
                                                       headers:allHeaders
                                                          body:[NSData data]
                                                 remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    return response;
}

- (NSString *)iso8601String {
    if (@available(macOS 10.12, iOS 10.0, *)) {
        NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
        return [formatter stringFromDate:[NSDate date]];
    }
    return [[NSDate date] description];
}

- (void)testApplicationGetSubjectStatusRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.admin.getSubjectStatus"
                                              queryString:[NSString stringWithFormat:@"did=%@", self.userDid]
                                              queryParams:@{@"did": self.userDid}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"AuthRequired");
}

- (void)testApplicationGetSubjectStatusNonAdminForbidden {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.admin.getSubjectStatus"
                                              queryString:[NSString stringWithFormat:@"did=%@", self.userDid]
                                              queryParams:@{@"did": self.userDid}
                                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 403);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"Forbidden");
}

- (void)testApplicationGetSubjectStatusAdminSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.admin.getSubjectStatus"
                                              queryString:[NSString stringWithFormat:@"did=%@", self.userDid]
                                              queryParams:@{@"did": self.userDid}
                                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.jsonBody[@"subject"][@"did"], self.userDid);
}

- (void)testApplicationUpdateSubjectStatusRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.updateSubjectStatus"
                                                      body:@{
                                                          @"subject": @{@"did": self.userDid},
                                                          @"reason": @"test"
                                                      }
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"AuthRequired");
}

- (void)testApplicationModerateAccountRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.moderateAccount"
                                                      body:@{
                                                          @"did": self.userDid,
                                                          @"reason": @"test"
                                                      }
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"AuthRequired");
}

- (void)testApplicationModerateRecordRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.moderateRecord"
                                                      body:@{
                                                          @"uri": [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/1", self.userDid],
                                                          @"reason": @"test"
                                                      }
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"AuthRequired");
}

- (void)testApplicationCreateLabelRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.label.createLabel"
                                                      body:@{
                                                          @"src": self.userDid,
                                                          @"uri": [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/1", self.userDid],
                                                          @"val": @"spam"
                                                      }
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"AuthRequired");
}

- (void)testApplicationGetLabelsRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.label.getLabels"
                                              queryString:@"limit=10"
                                              queryParams:@{@"limit": @"10"}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"AuthRequired");
}

- (nullable NSString *)commitRevFromCARData:(NSData *)carData {
    NSError *carError = nil;
    CARReader *reader = [CARReader readFromData:carData error:&carError];
    XCTAssertNil(carError);
    XCTAssertNotNil(reader);
    if (!reader) {
        return nil;
    }

    CARBlock *commitBlock = [reader blockWithCID:reader.rootCID];
    XCTAssertNotNil(commitBlock);
    if (!commitBlock) {
        return nil;
    }

    CBORValue *commitValue = [CBORValue decode:commitBlock.data];
    XCTAssertNotNil(commitValue);
    XCTAssertEqual(commitValue.type, CBORTypeMap);
    if (!commitValue || commitValue.type != CBORTypeMap) {
        return nil;
    }

    CBORValue *revValue = commitValue.map[[CBORValue textString:@"rev"]];
    XCTAssertNotNil(revValue);
    XCTAssertEqual(revValue.type, CBORTypeTextString);
    return revValue.textString;
}

- (void)testApplicationSyncGetRepoReturnsCARWithoutAuth {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"application sync getRepo",
        @"createdAt": [self iso8601String]
    };
    NSDictionary *created = [self.application.legacyController createRecordForDid:self.userDid
                                                                        collection:@"app.bsky.feed.post"
                                                                            record:record
                                                                    validationMode:PDSValidationModeOff
                                                                             error:nil];
    XCTAssertNotNil(created);

    NSString *query = [NSString stringWithFormat:@"did=%@", self.userDid];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                                              queryString:query
                                              queryParams:@{@"did": self.userDid}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.contentType, @"application/vnd.ipld.car");
    XCTAssertNotNil(response.body);
    XCTAssertTrue(response.body.length > 0);
    if (response.bodyFilePath.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:response.bodyFilePath error:nil];
    }
}

- (void)testApplicationSyncGetRepoSinceCurrentRevReturnsEmptyDelta {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"application sync since",
        @"createdAt": [self iso8601String]
    };
    NSDictionary *created = [self.application.legacyController createRecordForDid:self.userDid
                                                                        collection:@"app.bsky.feed.post"
                                                                            record:record
                                                                    validationMode:PDSValidationModeOff
                                                                             error:nil];
    XCTAssertNotNil(created);

    NSString *query = [NSString stringWithFormat:@"did=%@", self.userDid];
    HttpResponse *fullResponse = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                                                  queryString:query
                                                  queryParams:@{@"did": self.userDid}
                                                      headers:@{}];
    XCTAssertEqual(fullResponse.statusCode, 200);
    NSString *rev = [self commitRevFromCARData:fullResponse.body];
    XCTAssertNotNil(rev);
    if (fullResponse.bodyFilePath.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:fullResponse.bodyFilePath error:nil];
    }

    NSString *deltaQuery = [NSString stringWithFormat:@"did=%@&since=%@", self.userDid, rev];
    HttpResponse *deltaResponse = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                                                   queryString:deltaQuery
                                                   queryParams:@{@"did": self.userDid, @"since": rev}
                                                       headers:@{}];
    XCTAssertEqual(deltaResponse.statusCode, 200);
    XCTAssertEqualObjects(deltaResponse.contentType, @"application/vnd.ipld.car");

    NSError *parseError = nil;
    CARReader *reader = [CARReader readFromData:deltaResponse.body error:&parseError];
    XCTAssertNil(parseError);
    XCTAssertNotNil(reader);
    XCTAssertEqual(reader.blocks.count, 0U);
    if (deltaResponse.bodyFilePath.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:deltaResponse.bodyFilePath error:nil];
    }
}

- (void)testApplicationSyncGetRepoUnknownSinceFallsBackToFull {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"application unknown since",
        @"createdAt": [self iso8601String]
    };
    NSDictionary *created = [self.application.legacyController createRecordForDid:self.userDid
                                                                        collection:@"app.bsky.feed.post"
                                                                            record:record
                                                                    validationMode:PDSValidationModeOff
                                                                             error:nil];
    XCTAssertNotNil(created);

    NSString *query = [NSString stringWithFormat:@"did=%@", self.userDid];
    HttpResponse *fullResponse = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                                                  queryString:query
                                                  queryParams:@{@"did": self.userDid}
                                                      headers:@{}];
    XCTAssertEqual(fullResponse.statusCode, 200);

    NSError *fullParseError = nil;
    CARReader *fullReader = [CARReader readFromData:fullResponse.body error:&fullParseError];
    XCTAssertNil(fullParseError);
    XCTAssertNotNil(fullReader);
    if (fullResponse.bodyFilePath.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:fullResponse.bodyFilePath error:nil];
    }

    NSString *unknownSinceQuery = [NSString stringWithFormat:@"did=%@&since=%@", self.userDid, @"3jzfcijpj2z2a"];
    HttpResponse *unknownResponse = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                                                     queryString:unknownSinceQuery
                                                     queryParams:@{@"did": self.userDid, @"since": @"3jzfcijpj2z2a"}
                                                         headers:@{}];
    XCTAssertEqual(unknownResponse.statusCode, 200);
    XCTAssertEqualObjects(unknownResponse.contentType, @"application/vnd.ipld.car");

    NSError *unknownParseError = nil;
    CARReader *unknownReader = [CARReader readFromData:unknownResponse.body error:&unknownParseError];
    XCTAssertNil(unknownParseError);
    XCTAssertNotNil(unknownReader);
    XCTAssertEqual(unknownReader.blocks.count, fullReader.blocks.count);
    if (unknownResponse.bodyFilePath.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:unknownResponse.bodyFilePath error:nil];
    }
}

- (void)testApplicationSyncGetRepoSinceApplyWritesCreateRevReturnsEmptyDelta {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    NSDictionary *createWrite = @{
        @"action": @"create",
        @"collection": @"app.bsky.feed.post",
        @"rkey": @"applywrites-since-create",
        @"value": @{
            @"$type": @"app.bsky.feed.post",
            @"text": @"applyWrites create rev baseline",
            @"createdAt": [self iso8601String]
        }
    };

    HttpResponse *applyResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.applyWrites"
                                                           body:@{@"writes": @[createWrite], @"validate": @NO}
                                                        headers:@{@"authorization": authHeader}];
    XCTAssertEqual(applyResponse.statusCode, 200);
    NSDictionary *applyCommit = applyResponse.jsonBody[@"commit"];
    XCTAssertNotNil(applyCommit);
    XCTAssertTrue([applyCommit[@"cid"] length] > 0);
    XCTAssertTrue([applyCommit[@"rev"] length] > 0);

    PDSActorStore *store = [self.application.userDatabasePool storeForDid:self.userDid error:nil];
    XCTAssertNotNil(store);
    NSString *commitRev = [store latestMutationRevisionWithError:nil];
    XCTAssertNotNil(commitRev);
    XCTAssertTrue(commitRev.length > 0);
    XCTAssertEqualObjects(applyCommit[@"rev"], commitRev);

    NSString *query = [NSString stringWithFormat:@"did=%@&since=%@", self.userDid, commitRev];
    HttpResponse *deltaResponse = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                                                   queryString:query
                                                   queryParams:@{@"did": self.userDid, @"since": commitRev}
                                                       headers:@{}];
    XCTAssertEqual(deltaResponse.statusCode, 200);

    NSError *parseError = nil;
    CARReader *reader = [CARReader readFromData:deltaResponse.body error:&parseError];
    XCTAssertNil(parseError);
    XCTAssertNotNil(reader);
    XCTAssertEqual(reader.blocks.count, 0U);
    if (deltaResponse.bodyFilePath.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:deltaResponse.bodyFilePath error:nil];
    }
}

- (void)testApplicationSyncGetRepoSinceApplyWritesDeleteRevReturnsEmptyDelta {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    NSDictionary *createWrite = @{
        @"action": @"create",
        @"collection": @"app.bsky.feed.post",
        @"rkey": @"applywrites-since-delete",
        @"value": @{
            @"$type": @"app.bsky.feed.post",
            @"text": @"applyWrites delete rev baseline",
            @"createdAt": [self iso8601String]
        }
    };
    HttpResponse *createResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.applyWrites"
                                                            body:@{@"writes": @[createWrite], @"validate": @NO}
                                                         headers:@{@"authorization": authHeader}];
    XCTAssertEqual(createResponse.statusCode, 200);
    NSDictionary *createCommit = createResponse.jsonBody[@"commit"];
    XCTAssertNotNil(createCommit);
    XCTAssertTrue([createCommit[@"cid"] length] > 0);
    XCTAssertTrue([createCommit[@"rev"] length] > 0);

    NSDictionary *deleteWrite = @{
        @"action": @"delete",
        @"collection": @"app.bsky.feed.post",
        @"rkey": @"applywrites-since-delete"
    };
    HttpResponse *deleteResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.applyWrites"
                                                            body:@{@"writes": @[deleteWrite], @"validate": @NO}
                                                         headers:@{@"authorization": authHeader}];
    XCTAssertEqual(deleteResponse.statusCode, 200);
    NSDictionary *deleteCommit = deleteResponse.jsonBody[@"commit"];
    XCTAssertNotNil(deleteCommit);
    XCTAssertTrue([deleteCommit[@"cid"] length] > 0);
    XCTAssertTrue([deleteCommit[@"rev"] length] > 0);

    PDSActorStore *store = [self.application.userDatabasePool storeForDid:self.userDid error:nil];
    XCTAssertNotNil(store);
    NSString *deleteRev = [store latestMutationRevisionWithError:nil];
    XCTAssertNotNil(deleteRev);
    XCTAssertTrue(deleteRev.length > 0);
    XCTAssertEqualObjects(deleteCommit[@"rev"], deleteRev);

    NSString *query = [NSString stringWithFormat:@"did=%@&since=%@", self.userDid, deleteRev];
    HttpResponse *deltaResponse = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                                                   queryString:query
                                                   queryParams:@{@"did": self.userDid, @"since": deleteRev}
                                                       headers:@{}];
    XCTAssertEqual(deltaResponse.statusCode, 200);

    NSError *parseError = nil;
    CARReader *reader = [CARReader readFromData:deltaResponse.body error:&parseError];
    XCTAssertNil(parseError);
    XCTAssertNotNil(reader);
    XCTAssertEqual(reader.blocks.count, 0U);
    if (deltaResponse.bodyFilePath.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:deltaResponse.bodyFilePath error:nil];
    }
}

@end
