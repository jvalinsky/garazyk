#import <XCTest/XCTest.h>
#import "Federation/FederationClient.h"

NS_ASSUME_NONNULL_BEGIN

@interface TestDIDResolver : NSObject
@property (nonatomic, copy, nullable) NSDictionary *result;
@end

@implementation TestDIDResolver
- (NSDictionary *)resolveAtprotoDataForDID:(NSString *)did error:(NSError **)error {
    return self.result;
}
@end

@interface TestURLSessionDataTask : NSURLSessionDataTask
@property (nonatomic, copy) void (^resumeBlock)(void);
@end

@implementation TestURLSessionDataTask
- (void)resume {
    if (self.resumeBlock) {
        self.resumeBlock();
    }
}
@end

@interface TestURLSession : NSURLSession
@property (nonatomic, copy, nullable) NSData *responseData;
@property (nonatomic, strong, nullable) NSHTTPURLResponse *response;
@property (nonatomic, strong, nullable) NSError *error;
@property (nonatomic, copy, nullable) void (^onRequest)(NSURLRequest *request);
+ (instancetype)sessionForTests;
@end

@implementation TestURLSession
 + (instancetype)sessionForTests {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [[self alloc] init];
#pragma clang diagnostic pop
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))completionHandler {
    if (self.onRequest) {
        self.onRequest(request);
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    TestURLSessionDataTask *task = [[TestURLSessionDataTask alloc] init];
#pragma clang diagnostic pop
    task.resumeBlock = ^{
        completionHandler(self.responseData, self.response, self.error);
    };
    return task;
}
@end

@interface FederationClientTests : XCTestCase
@end

@implementation FederationClientTests

#ifndef GNUSTEP
- (void)testForwardXrpcRequestFailsWhenDIDResolutionFails {
    FederationClient *client = [[FederationClient alloc] init];
    TestDIDResolver *resolver = [[TestDIDResolver alloc] init];
    resolver.result = nil;
    client.didResolver = resolver;
    TestURLSession *session = [TestURLSession sessionForTests];
    client.session = session;

    XCTestExpectation *done = [self expectationWithDescription:@"completion"];
    [client forwardXrpcRequest:@"com.atproto.repo.getRecord"
                    parameters:@{@"repo": @"did:plc:missing"}
                           did:@"did:plc:missing"
                    completion:^(NSDictionary * _Nullable response, NSError * _Nullable error) {
        XCTAssertNil(response);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, FederationErrorDIDResolutionFailed);
        [done fulfill];
    }];

    [self waitForExpectations:@[done] timeout:1.0];
}
#endif

#ifndef GNUSTEP
- (void)testForwardXrpcNonSuccessStatusReturnsError {
    FederationClient *client = [[FederationClient alloc] init];
    TestDIDResolver *resolver = [[TestDIDResolver alloc] init];
    resolver.result = @{@"pds": @"https://example.com"};
    client.didResolver = resolver;
    TestURLSession *session = [TestURLSession sessionForTests];
    session.responseData = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
    session.response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://example.com"]
                                                   statusCode:500
                                                  HTTPVersion:@"HTTP/1.1"
                                                 headerFields:@{}];
    client.session = session;

    XCTestExpectation *done = [self expectationWithDescription:@"completion"];
    [client forwardXrpcRequest:@"com.atproto.repo.getRecord"
                    parameters:@{@"repo": @"did:plc:abc"}
                           did:@"did:plc:abc"
                    completion:^(NSDictionary * _Nullable response, NSError * _Nullable error) {
        XCTAssertNil(response);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, FederationErrorRemoteServerError);
        [done fulfill];
    }];

    [self waitForExpectations:@[done] timeout:1.0];
}
#endif

#ifndef GNUSTEP
- (void)testForwardXrpcGetMethodIsGET {
    FederationClient *client = [[FederationClient alloc] init];
    TestDIDResolver *resolver = [[TestDIDResolver alloc] init];
    resolver.result = @{@"pds": @"https://example.com"};
    client.didResolver = resolver;
    TestURLSession *session = [TestURLSession sessionForTests];
    session.responseData = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
    session.response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://example.com"]
                                                   statusCode:200
                                                  HTTPVersion:@"HTTP/1.1"
                                                 headerFields:@{}];
    client.session = session;

    XCTestExpectation *captured = [self expectationWithDescription:@"request"];
    session.onRequest = ^(NSURLRequest *request) {
        XCTAssertEqualObjects(request.HTTPMethod, @"GET");
        [captured fulfill];
    };

    XCTestExpectation *done = [self expectationWithDescription:@"completion"];
    [client forwardXrpcRequest:@"com.atproto.repo.listRecords"
                    parameters:@{@"repo": @"did:plc:abc"}
                           did:@"did:plc:abc"
                    completion:^(NSDictionary * _Nullable response, NSError * _Nullable error) {
        XCTAssertNil(error);
        [done fulfill];
    }];

    [self waitForExpectations:@[captured, done] timeout:1.0];
}
#endif

#ifndef GNUSTEP
- (void)testForwardXrpcPostMethodIsPOST {
    FederationClient *client = [[FederationClient alloc] init];
    TestDIDResolver *resolver = [[TestDIDResolver alloc] init];
    resolver.result = @{@"pds": @"https://example.com"};
    client.didResolver = resolver;
    TestURLSession *session = [TestURLSession sessionForTests];
    session.responseData = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
    session.response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://example.com"]
                                                   statusCode:200
                                                  HTTPVersion:@"HTTP/1.1"
                                                 headerFields:@{}];
    client.session = session;

    XCTestExpectation *captured = [self expectationWithDescription:@"request"];
    session.onRequest = ^(NSURLRequest *request) {
        XCTAssertEqualObjects(request.HTTPMethod, @"POST");
        [captured fulfill];
    };

    XCTestExpectation *done = [self expectationWithDescription:@"completion"];
    [client forwardXrpcRequest:@"com.atproto.repo.createRecord"
                    parameters:@{@"collection": @"app.bsky.feed.post"}
                           did:@"did:plc:abc"
                    completion:^(NSDictionary * _Nullable response, NSError * _Nullable error) {
        XCTAssertNil(error);
        [done fulfill];
    }];

    [self waitForExpectations:@[captured, done] timeout:1.0];
}
#endif

#ifndef GNUSTEP
- (void)testForwardXrpcIncludesContentTypeHeader {
    FederationClient *client = [[FederationClient alloc] init];
    TestDIDResolver *resolver = [[TestDIDResolver alloc] init];
    resolver.result = @{@"pds": @"https://example.com"};
    client.didResolver = resolver;
    TestURLSession *session = [TestURLSession sessionForTests];
    session.responseData = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
    session.response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://example.com"]
                                                   statusCode:200
                                                  HTTPVersion:@"HTTP/1.1"
                                                 headerFields:@{}];
    client.session = session;

    XCTestExpectation *captured = [self expectationWithDescription:@"request"];
    session.onRequest = ^(NSURLRequest *request) {
        XCTAssertEqualObjects(request.allHTTPHeaderFields[@"Content-Type"], @"application/json");
        [captured fulfill];
    };

    XCTestExpectation *done = [self expectationWithDescription:@"completion"];
    [client forwardXrpcRequest:@"com.atproto.repo.createRecord"
                    parameters:@{@"record": @{@"test": @"value"}}
                           did:@"did:plc:abc"
                    completion:^(NSDictionary * _Nullable response, NSError * _Nullable error) {
        XCTAssertNil(error);
        [done fulfill];
    }];

    [self waitForExpectations:@[captured, done] timeout:1.0];
}
#endif

#ifndef GNUSTEP
- (void)testForwardXrpcParsesJSONResponse {
    FederationClient *client = [[FederationClient alloc] init];
    TestDIDResolver *resolver = [[TestDIDResolver alloc] init];
    resolver.result = @{@"pds": @"https://example.com"};
    client.didResolver = resolver;
    TestURLSession *session = [TestURLSession sessionForTests];
    NSDictionary *responseBody = @{@"uri": @"at://did:plc:abc/app.bsky.feed.post/3k5d4s", @"cid": @"bafyreia"};
    session.responseData = [NSJSONSerialization dataWithJSONObject:responseBody options:0 error:nil];
    session.response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://example.com"]
                                                   statusCode:200
                                                  HTTPVersion:@"HTTP/1.1"
                                                 headerFields:@{@"Content-Type": @"application/json"}];
    client.session = session;

    XCTestExpectation *done = [self expectationWithDescription:@"completion"];
    [client forwardXrpcRequest:@"com.atproto.repo.createRecord"
                    parameters:@{@"collection": @"app.bsky.feed.post"}
                           did:@"did:plc:abc"
                    completion:^(NSDictionary * _Nullable response, NSError * _Nullable error) {
        XCTAssertNil(error);
        XCTAssertNotNil(response);
        XCTAssertEqualObjects(response[@"uri"], @"at://did:plc:abc/app.bsky.feed.post/3k5d4s");
        XCTAssertEqualObjects(response[@"cid"], @"bafyreia");
        [done fulfill];
    }];

    [self waitForExpectations:@[done] timeout:1.0];
}
#endif

#ifndef GNUSTEP
- (void)testForwardXrpcHandlesNSURLSessionError {
    FederationClient *client = [[FederationClient alloc] init];
    TestDIDResolver *resolver = [[TestDIDResolver alloc] init];
    resolver.result = @{@"pds": @"https://example.com"};
    client.didResolver = resolver;
    TestURLSession *session = [TestURLSession sessionForTests];
    session.responseData = nil;
    session.response = nil;
    session.error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil];
    client.session = session;

    XCTestExpectation *done = [self expectationWithDescription:@"completion"];
    [client forwardXrpcRequest:@"com.atproto.repo.getRecord"
                    parameters:@{@"repo": @"did:plc:abc"}
                           did:@"did:plc:abc"
                    completion:^(NSDictionary * _Nullable response, NSError * _Nullable error) {
        XCTAssertNil(response);
        XCTAssertNotNil(error);
        [done fulfill];
    }];

    [self waitForExpectations:@[done] timeout:1.0];
}
#endif

#ifndef GNUSTEP
- (void)testForwardXrpcHandlesBadJSONResponse {
    FederationClient *client = [[FederationClient alloc] init];
    TestDIDResolver *resolver = [[TestDIDResolver alloc] init];
    resolver.result = @{@"pds": @"https://example.com"};
    client.didResolver = resolver;
    TestURLSession *session = [TestURLSession sessionForTests];
    session.responseData = [@"not valid json" dataUsingEncoding:NSUTF8StringEncoding];
    session.response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://example.com"]
                                                   statusCode:200
                                                  HTTPVersion:@"HTTP/1.1"
                                                 headerFields:@{}];
    client.session = session;

    XCTestExpectation *done = [self expectationWithDescription:@"completion"];
    [client forwardXrpcRequest:@"com.atproto.repo.getRecord"
                    parameters:@{@"repo": @"did:plc:abc"}
                           did:@"did:plc:abc"
                    completion:^(NSDictionary * _Nullable response, NSError * _Nullable error) {
        XCTAssertNil(response);
        XCTAssertNotNil(error);
        [done fulfill];
    }];

    [self waitForExpectations:@[done] timeout:1.0];
}
#endif

#ifndef GNUSTEP
- (void)testForwardXrpcUnauthorizedStatusReturnsError {
    FederationClient *client = [[FederationClient alloc] init];
    TestDIDResolver *resolver = [[TestDIDResolver alloc] init];
    resolver.result = @{@"pds": @"https://example.com"};
    client.didResolver = resolver;
    TestURLSession *session = [TestURLSession sessionForTests];
    session.responseData = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
    session.response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://example.com"]
                                                   statusCode:401
                                                  HTTPVersion:@"HTTP/1.1"
                                                 headerFields:@{}];
    client.session = session;

    XCTestExpectation *done = [self expectationWithDescription:@"completion"];
    [client forwardXrpcRequest:@"com.atproto.repo.getRecord"
                    parameters:@{@"repo": @"did:plc:abc"}
                           did:@"did:plc:abc"
                    completion:^(NSDictionary * _Nullable response, NSError * _Nullable error) {
        XCTAssertNil(response);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, FederationErrorRemoteServerError);
        [done fulfill];
    }];

    [self waitForExpectations:@[done] timeout:1.0];
}
#endif

#ifndef GNUSTEP
- (void)testForwardXrpcForbiddenStatusReturnsError {
    FederationClient *client = [[FederationClient alloc] init];
    TestDIDResolver *resolver = [[TestDIDResolver alloc] init];
    resolver.result = @{@"pds": @"https://example.com"};
    client.didResolver = resolver;
    TestURLSession *session = [TestURLSession sessionForTests];
    session.responseData = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
    session.response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://example.com"]
                                                   statusCode:403
                                                  HTTPVersion:@"HTTP/1.1"
                                                 headerFields:@{}];
    client.session = session;

    XCTestExpectation *done = [self expectationWithDescription:@"completion"];
    [client forwardXrpcRequest:@"com.atproto.repo.getRecord"
                    parameters:@{@"repo": @"did:plc:abc"}
                           did:@"did:plc:abc"
                    completion:^(NSDictionary * _Nullable response, NSError * _Nullable error) {
        XCTAssertNil(response);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, FederationErrorRemoteServerError);
        [done fulfill];
    }];

    [self waitForExpectations:@[done] timeout:1.0];
}

#endif

@end

NS_ASSUME_NONNULL_END
