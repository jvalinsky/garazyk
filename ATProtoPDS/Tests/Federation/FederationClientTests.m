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

- (FederationClient *)clientWithResolver:(TestDIDResolver *)resolver session:(TestURLSession *)session {
    FederationClient *client = [[FederationClient alloc] init];
    [client setValue:resolver forKey:@"didResolver"];
    [client setValue:session forKey:@"session"];
    return client;
}

- (void)testForwardXrpcRequestFailsWhenDIDResolutionFails {
    TestDIDResolver *resolver = [[TestDIDResolver alloc] init];
    resolver.result = nil;
    TestURLSession *session = [TestURLSession sessionForTests];
    FederationClient *client = [self clientWithResolver:resolver session:session];

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

- (void)testForwardXrpcGetBuildsQueryString {
    TestDIDResolver *resolver = [[TestDIDResolver alloc] init];
    resolver.result = @{@"pds": @"https://example.com"};

    TestURLSession *session = [TestURLSession sessionForTests];
    session.responseData = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
    session.response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://example.com"]
                                                   statusCode:200
                                                  HTTPVersion:@"HTTP/1.1"
                                                 headerFields:@{}];

    XCTestExpectation *captured = [self expectationWithDescription:@"request"];
    session.onRequest = ^(NSURLRequest *request) {
        NSString *urlString = request.URL.absoluteString;
        XCTAssertTrue([urlString containsString:@"/xrpc/com.atproto.repo.getRecord"]);
        XCTAssertTrue([urlString containsString:@"repo=did%3Aplc%3Aabc"]);
        XCTAssertTrue([urlString containsString:@"rkey=test"]);
        XCTAssertEqualObjects(request.HTTPMethod, @"GET");
        [captured fulfill];
    };

    FederationClient *client = [self clientWithResolver:resolver session:session];
    XCTestExpectation *done = [self expectationWithDescription:@"completion"];
    [client forwardXrpcRequest:@"com.atproto.repo.getRecord"
                    parameters:@{@"repo": @"did:plc:abc", @"rkey": @"test"}
                           did:@"did:plc:abc"
                    completion:^(NSDictionary * _Nullable response, NSError * _Nullable error) {
        XCTAssertNotNil(response);
        XCTAssertNil(error);
        [done fulfill];
    }];

    [self waitForExpectations:@[captured, done] timeout:1.0];
}

- (void)testForwardXrpcPostIncludesBody {
    TestDIDResolver *resolver = [[TestDIDResolver alloc] init];
    resolver.result = @{@"pds": @"https://example.com"};

    TestURLSession *session = [TestURLSession sessionForTests];
    session.responseData = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
    session.response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://example.com"]
                                                   statusCode:200
                                                  HTTPVersion:@"HTTP/1.1"
                                                 headerFields:@{}];

    XCTestExpectation *captured = [self expectationWithDescription:@"request"];
    session.onRequest = ^(NSURLRequest *request) {
        XCTAssertEqualObjects(request.HTTPMethod, @"POST");
        XCTAssertNotNil(request.HTTPBody);
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:nil];
        XCTAssertEqualObjects(json[@"record"], @"value");
        [captured fulfill];
    };

    FederationClient *client = [self clientWithResolver:resolver session:session];
    XCTestExpectation *done = [self expectationWithDescription:@"completion"];
    [client forwardXrpcRequest:@"com.atproto.repo.createRecord"
                    parameters:@{@"record": @"value"}
                           did:@"did:plc:abc"
                    completion:^(NSDictionary * _Nullable response, NSError * _Nullable error) {
        XCTAssertNotNil(response);
        XCTAssertNil(error);
        [done fulfill];
    }];

    [self waitForExpectations:@[captured, done] timeout:1.0];
}

- (void)testForwardXrpcNonSuccessStatusReturnsError {
    TestDIDResolver *resolver = [[TestDIDResolver alloc] init];
    resolver.result = @{@"pds": @"https://example.com"};

    TestURLSession *session = [TestURLSession sessionForTests];
    session.responseData = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
    session.response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://example.com"]
                                                   statusCode:500
                                                  HTTPVersion:@"HTTP/1.1"
                                                 headerFields:@{}];

    FederationClient *client = [self clientWithResolver:resolver session:session];
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

@end

NS_ASSUME_NONNULL_END
