#import "AdminAuthXrpcTestBase.h"

@interface XrpcAppBskyAgeAssuranceTests : AdminAuthXrpcTestBase
@end

@implementation XrpcAppBskyAgeAssuranceTests

- (void)testBeginAgeAssuranceRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.ageassurance.begin"
                                                      body:@{
                                                          @"email": @"test@example.com",
                                                          @"language": @"en",
                                                          @"countryCode": @"US"
                                                      }
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testBeginAgeAssuranceValidatesInput {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.ageassurance.begin"
                                                      body:@{
                                                          @"email": @"test@example.com"
                                                      }
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testBeginAgeAssuranceSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.ageassurance.begin"
                                                      body:@{
                                                          @"email": @"test@example.com",
                                                          @"language": @"en",
                                                          @"countryCode": @"US"
                                                      }
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"id"]);
    XCTAssertEqualObjects(response.jsonBody[@"status"], @"pending");
    XCTAssertNotNil(response.jsonBody[@"token"]);
}

- (void)testGetAgeAssuranceConfig {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.ageassurance.getConfig"
                                              queryString:@""
                                              queryParams:@{}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"regions"]);
}

- (void)testGetAgeAssuranceStateRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.ageassurance.getState"
                                              queryString:@"countryCode=US"
                                              queryParams:@{@"countryCode": @"US"}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testGetAgeAssuranceStateSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    
    // First, begin age assurance to have a state
    [self sendJsonRequestWithPath:@"/xrpc/app.bsky.ageassurance.begin"
                             body:@{
                                 @"email": @"test@example.com",
                                 @"language": @"en",
                                 @"countryCode": @"US"
                             }
                          headers:@{@"authorization": authHeader}];
    
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.ageassurance.getState"
                                              queryString:@"countryCode=US"
                                              queryParams:@{@"countryCode": @"US"}
                                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"state"]);
    XCTAssertNotNil(response.jsonBody[@"metadata"]);
}

@end
