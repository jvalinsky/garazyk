#import <XCTest/XCTest.h>
#import "App/Explore/ExploreHandler.h"
#import "Network/HttpRequest.h"

@interface ExploreHandler (Testing)
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, copy) NSString *cacheDirectory;
@property (nonatomic, copy) NSString *plcServerURL;
@property (nonatomic, assign) NSTimeInterval didTTL;
@property (nonatomic, assign) NSTimeInterval plcTTL;
@property (nonatomic, assign) NSTimeInterval accountTTL;
- (void)parseConfig:(NSString *)content;
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

@end
