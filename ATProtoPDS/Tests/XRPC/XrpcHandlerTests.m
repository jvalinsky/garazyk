#import "Network/XrpcHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

@interface XrpcHandlerTests : XCTestCase
@property (nonatomic, strong) XrpcDispatcher *dispatcher;
@end

@implementation XrpcHandlerTests

- (void)setUp {
    [super setUp];
    self.dispatcher = [[XrpcDispatcher alloc] init];
}

- (void)tearDown {
    self.dispatcher = nil;
    [super tearDown];
}

- (void)testMethodRegistrationAndDispatch {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Method handler called"];
    
    [self.dispatcher registerMethod:@"test.method" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"result": @"success"}];
        [expectation fulfill];
    }];
    
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/test.method"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{}
                                                          body:nil
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    
    [self.dispatcher handleRequest:request response:response];
    
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    XCTAssertEqual(response.statusCode, HttpStatusOK);
    XCTAssertEqualObjects(response.jsonBody[@"result"], @"success");
}

- (void)testUnrecognizedMethodReturns404 {
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/unknown.method"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{}
                                                          body:nil
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    
    [self.dispatcher handleRequest:request response:response];
    
    XCTAssertEqual(response.statusCode, HttpStatusNotImplemented, @"Should return 501 for unimplemented methods");
}

@end
