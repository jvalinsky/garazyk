#import <XCTest/XCTest.h>
#import "App/Explore/ExploreHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

@interface ExploreHandler (Testing)
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, copy) NSString *cacheDirectory;
@property (nonatomic, copy) NSString *plcServerURL;
@property (nonatomic, assign) NSTimeInterval didTTL;
@property (nonatomic, assign) NSTimeInterval plcTTL;
@property (nonatomic, assign) NSTimeInterval accountTTL;
- (void)parseConfig:(NSString *)content;
- (NSDictionary *)parseQueryString:(NSString *)query;
- (NSString *)apiEndpointForPath:(NSString *)path;
- (NSDictionary *)generateOpenAPISpec;
- (void)handleApiOpenapiSpec:(NSDictionary *)params response:(HttpResponse *)response;
- (void)handleApiRequest:(HttpRequest *)request response:(HttpResponse *)response endpoint:(NSString *)endpoint;
@end

@interface ExploreHandlerTests : XCTestCase
@property (nonatomic, strong) ExploreHandler *handler;
@end

@implementation ExploreHandlerTests

- (void)setUp {
    [super setUp];
    self.handler = [[ExploreHandler alloc] init];
}

- (void)tearDown {
    self.handler = nil;
    [super tearDown];
}

- (void)testParseConfigSetsExploreValues {
    NSString *config =
    @"explore:\n"
    @"  enabled: false\n"
    @"  plc_server: https://plc.example.com\n"
    @"  cache_directory: ~/tmp/explore-cache\n"
    @"  did_ttl_seconds: 123\n"
    @"  plc_log_ttl_seconds: 456\n"
    @"  account_list_ttl_seconds: 789\n";

    [self.handler parseConfig:config];

    XCTAssertFalse(self.handler.enabled);
    XCTAssertEqualObjects(self.handler.plcServerURL, @"https://plc.example.com");
    XCTAssertEqualObjects(self.handler.cacheDirectory, [@"~/tmp/explore-cache" stringByExpandingTildeInPath]);
    XCTAssertEqualWithAccuracy(self.handler.didTTL, 123.0, 0.1);
    XCTAssertEqualWithAccuracy(self.handler.plcTTL, 456.0, 0.1);
    XCTAssertEqualWithAccuracy(self.handler.accountTTL, 789.0, 0.1);
}

- (void)testCanHandleRequestWhenDisabled {
    self.handler.enabled = NO;
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/explore"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                  remoteAddress:@"127.0.0.1"];

    XCTAssertFalse([self.handler canHandleRequest:request]);
}

- (void)testCanHandleRequestWhenEnabled {
    self.handler.enabled = YES;
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/explore/api"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                  remoteAddress:@"127.0.0.1"];

    XCTAssertTrue([self.handler canHandleRequest:request]);
}

- (void)testApiEndpointForPathExtractsFirstSegment {
    XCTAssertEqualObjects([self.handler apiEndpointForPath:@"/api/pds/records"], @"records");
    XCTAssertEqualObjects([self.handler apiEndpointForPath:@"/api/pds/records/extra/path"], @"records");
    XCTAssertEqualObjects([self.handler apiEndpointForPath:@"/not-api/pds/records"], @"");
    XCTAssertEqualObjects([self.handler apiEndpointForPath:nil], @"");
}

- (void)testParseQueryStringDecodesPercentEscapes {
    NSDictionary *params = [self.handler parseQueryString:@"did=did%3Aplc%3Aabc&limit=20&empty="];
    XCTAssertEqualObjects(params[@"did"], @"did:plc:abc");
    XCTAssertEqualObjects(params[@"limit"], @"20");
    XCTAssertEqualObjects(params[@"empty"], @"");
}

- (void)testGenerateOpenAPISpecContainsCoreFieldsAndPaths {
    NSDictionary *spec = [self.handler generateOpenAPISpec];
    XCTAssertEqualObjects(spec[@"openapi"], @"3.0.0");
    XCTAssertTrue([spec[@"info"] isKindOfClass:[NSDictionary class]]);
    XCTAssertTrue([spec[@"paths"] isKindOfClass:[NSDictionary class]]);

    NSDictionary *paths = spec[@"paths"];
    XCTAssertNotNil(paths[@"/api/pds/lookup"]);
    XCTAssertNotNil(paths[@"/api/pds/accounts"]);
    XCTAssertNotNil(paths[@"/api/pds/openapi.json"]);
}

- (void)testHandleApiOpenapiSpecReturnsJSONWhenRequested {
    HttpResponse *response = [HttpResponse response];
    [self.handler handleApiOpenapiSpec:@{@"format": @"json"} response:response];

    XCTAssertEqualObjects(response.contentType, @"application/json");
    XCTAssertNotNil(response.body);

    NSError *error = nil;
    id bodyJSON = [NSJSONSerialization JSONObjectWithData:response.body options:0 error:&error];
    XCTAssertNil(error);
    XCTAssertTrue([bodyJSON isKindOfClass:[NSDictionary class]]);
    XCTAssertEqualObjects(bodyJSON[@"openapi"], @"3.0.0");
}

- (void)testHandleApiOpenapiSpecReturnsYAMLByDefault {
    HttpResponse *response = [HttpResponse response];
    [self.handler handleApiOpenapiSpec:@{} response:response];

    XCTAssertEqualObjects(response.contentType, @"application/yaml");
    XCTAssertNotNil(response.body);

    NSString *yaml = [[NSString alloc] initWithData:response.body encoding:NSUTF8StringEncoding];
    XCTAssertNotNil(yaml);
    XCTAssertTrue([yaml containsString:@"openapi:"]);
    XCTAssertTrue([yaml containsString:@"paths:"]);
}

- (void)testHandleApiRequestUnknownEndpointReturnsNotFound {
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/api/pds/unknown"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                  remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [HttpResponse response];

    [self.handler handleApiRequest:request response:response endpoint:@"definitely-not-an-endpoint"];

    XCTAssertEqual(response.statusCode, HttpStatusNotFound);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"Unknown endpoint");
    XCTAssertEqualObjects(response.jsonBody[@"endpoint"], @"definitely-not-an-endpoint");
}

- (void)testHandleApiRequestDerivesEndpointFromPathAndValidatesParams {
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/api/pds/records"
                                                   queryString:@"did=did%3Aplc%3Aabc"
                                                   queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                  remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [HttpResponse response];

    [self.handler handleRequest:request response:response];

    XCTAssertEqual(response.statusCode, HttpStatusOK);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"Missing collection parameter");
}

- (void)testHandleApiRequestOpenapiJsonThroughPathDispatch {
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/api/pds/openapi.json"
                                                   queryString:@"format=json"
                                                   queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                  remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [HttpResponse response];

    [self.handler handleRequest:request response:response];

    XCTAssertEqual(response.statusCode, HttpStatusOK);
    XCTAssertEqualObjects(response.contentType, @"application/json");
    XCTAssertNotNil(response.body);
}

@end
