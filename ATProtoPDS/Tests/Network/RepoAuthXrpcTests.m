#import <XCTest/XCTest.h>
#import "App/PDSController.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

@interface RepoAuthXrpcTests : XCTestCase
@property (nonatomic, strong) PDSController *controller;
@property (nonatomic, strong) XrpcDispatcher *dispatcher;
@property (nonatomic, strong) NSURL *tempURL;
@property (nonatomic, copy) NSString *did1;
@property (nonatomic, copy) NSString *did2;
@property (nonatomic, copy) NSString *accessJwt1;
@end

@implementation RepoAuthXrpcTests

- (void)setUp {
    [super setUp];

    self.tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    self.tempURL = [self.tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempURL withIntermediateDirectories:YES attributes:nil error:nil];

    self.controller = [[PDSController alloc] initWithDirectory:self.tempURL.path serviceMaxSize:10 userDatabaseSize:10];
    self.dispatcher = [[XrpcDispatcher alloc] init];
    [XrpcMethodRegistry registerMethodsWithDispatcher:self.dispatcher controller:self.controller];

    NSError *error = nil;
    NSDictionary *account1 = [self.controller createAccountForEmail:@"repoauth1@example.com"
                                                          password:@"password"
                                                            handle:@"repoauth1.test"
                                                               did:nil
                                                             error:&error];
    XCTAssertNil(error);
    self.did1 = account1[@"did"];

    NSDictionary *account2 = [self.controller createAccountForEmail:@"repoauth2@example.com"
                                                          password:@"password"
                                                            handle:@"repoauth2.test"
                                                               did:nil
                                                             error:&error];
    XCTAssertNil(error);
    self.did2 = account2[@"did"];

    NSDictionary *session = [self.controller loginWithHandle:@"repoauth1.test" password:@"password" error:&error];
    XCTAssertNil(error);
    self.accessJwt1 = session[@"accessJwt"];
    XCTAssertNotNil(self.accessJwt1);
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtURL:self.tempURL error:nil];
    [super tearDown];
}

- (NSString *)iso8601String {
    if (@available(macOS 10.12, iOS 10.0, *)) {
        NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
        return [formatter stringFromDate:[NSDate date]];
    }
    return [[NSDate date] description];
}

- (HttpResponse *)sendJsonRequestWithPath:(NSString *)path
                                body:(NSDictionary *)body
                              headers:(NSDictionary<NSString *, NSString *> *)headers {
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
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

- (void)testDeleteRecordRequiresAuth {
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

- (void)testPutRecordRequiresAuth {
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

- (void)testApplyWritesRequiresAuth {
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

@end
