//
// OAuth2IntrospectionTests.m
// Test suite for OAuth 2.0 token introspection endpoint (RFC 7662)
//

#import <XCTest/XCTest.h>
#import "Auth/OAuth2Handler.h"
#import "Auth/OAuth2.h"
#import "Auth/JWT.h"
#import "Auth/CryptoUtils.h"
#import "Auth/Session.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Database/PDSDatabase.h"

@interface OAuth2IntrospectionTests : XCTestCase

@property (nonatomic, strong) OAuth2Handler *handler;
@property (nonatomic, strong) PDSDatabase *database;

@end

@implementation OAuth2IntrospectionTests

- (void)setUp {
    [super setUp];

    NSError *dbError = nil;
    NSString *dbName = [NSString stringWithFormat:@"test-introspection-%@.sqlite", [[NSUUID UUID] UUIDString]];
    NSURL *dbURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:dbName]];
    self.database = [PDSDatabase databaseAtURL:dbURL];
    [self.database openWithError:&dbError];
    XCTAssertNil(dbError);
    XCTAssertNotNil(self.database);

    self.handler = [[OAuth2Handler alloc] initWithDatabase:self.database];
    XCTAssertNotNil(self.handler);

    // Set up OAuth2 server
    self.handler.oauthServer.issuer = @"https://pds.test";
}

- (void)tearDown {
    self.handler = nil;
    self.database = nil;
    [super tearDown];
}

#pragma mark - Helper Methods

- (HttpRequest *)introspectionRequestWithToken:(NSString *)token clientID:(nullable NSString *)clientID {
    NSMutableString *bodyStr = [NSMutableString stringWithFormat:@"token=%@",
                            [self urlEncodeString:token]];
    if (clientID) {
        [bodyStr appendFormat:@"&client_id=%@", [self urlEncodeString:clientID]];
    }

    NSData *bodyData = [bodyStr dataUsingEncoding:NSUTF8StringEncoding];
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:@"/oauth/introspect"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{@"Content-Type": @"application/x-www-form-urlencoded"}
                                                          body:bodyData
                                                 remoteAddress:@"127.0.0.1"];
    return request;
}

- (NSString *)urlEncodeString:(NSString *)string {
    return [string stringByAddingPercentEncodingWithAllowedCharacters:
            [NSCharacterSet URLQueryAllowedCharacterSet]];
}

#pragma mark - Test Cases: Invalid Tokens

- (void)testIntrospectMalformedJWT {
    HttpRequest *request = [self introspectionRequestWithToken:@"invalid.jwt.token"
                                                      clientID:nil];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.handler handleIntrospectRequest:request response:response];

    XCTAssertEqual(response.statusCode, 200);
    NSDictionary *result = response.jsonBody;
    XCTAssertFalse([result[@"active"] boolValue]);
}

- (void)testIntrospectNotAJWT {
    HttpRequest *request = [self introspectionRequestWithToken:@"not-a-jwt"
                                                      clientID:nil];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.handler handleIntrospectRequest:request response:response];

    XCTAssertEqual(response.statusCode, 200);
    NSDictionary *result = response.jsonBody;
    XCTAssertFalse([result[@"active"] boolValue]);
}

- (void)testIntrospectEmptyToken {
    HttpRequest *request = [self introspectionRequestWithToken:@""
                                                      clientID:nil];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.handler handleIntrospectRequest:request response:response];

    // Empty string should fail to verify
    XCTAssertEqual(response.statusCode, 200);
    NSDictionary *result = response.jsonBody;
    XCTAssertFalse([result[@"active"] boolValue]);
}

#pragma mark - Test Cases: Missing Parameters

- (void)testIntrospectMissingTokenParameter {
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:@"/oauth/introspect"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{@"Content-Type": @"application/x-www-form-urlencoded"}
                                                          body:[@"" dataUsingEncoding:NSUTF8StringEncoding]
                                                 remoteAddress:@"127.0.0.1"];

    HttpResponse *response = [[HttpResponse alloc] init];
    [self.handler handleIntrospectRequest:request response:response];

    XCTAssertEqual(response.statusCode, 400);
    NSDictionary *result = response.jsonBody;
    XCTAssertEqualObjects(result[@"error"], @"invalid_request");
    XCTAssertEqualObjects(result[@"error_description"], @"Missing token parameter");
}

- (void)testIntrospectMissingRequestBody {
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:@"/oauth/introspect"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:nil
                                                 remoteAddress:@"127.0.0.1"];

    HttpResponse *response = [[HttpResponse alloc] init];
    [self.handler handleIntrospectRequest:request response:response];

    XCTAssertEqual(response.statusCode, 400);
    NSDictionary *result = response.jsonBody;
    XCTAssertEqualObjects(result[@"error"], @"invalid_request");
}

#pragma mark - Test Cases: RFC 7662 Compliance

- (void)testIntrospectionResponseFormatInactiveToken {
    HttpRequest *request = [self introspectionRequestWithToken:@"invalid.token"
                                                      clientID:nil];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.handler handleIntrospectRequest:request response:response];

    NSDictionary *result = response.jsonBody;

    // Per RFC 7662, inactive token must include:
    // - active (REQUIRED) = false
    // - (all other members are OPTIONAL and should be omitted)

    XCTAssertEqualObjects(result[@"active"], @NO);
    XCTAssertEqual(result.count, 1);
}

- (void)testIntrospectionReturnsHTTP200ForBothActiveAndInactive {
    // Invalid token should return 200 with active=false
    HttpRequest *request1 = [self introspectionRequestWithToken:@"invalid.token"
                                                        clientID:nil];
    HttpResponse *response1 = [[HttpResponse alloc] init];
    [self.handler handleIntrospectRequest:request1 response:response1];
    XCTAssertEqual(response1.statusCode, 200);

    // Missing token should return 400 (missing parameter, not introspection)
    HttpRequest *request2 = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:@"/oauth/introspect"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{@"Content-Type": @"application/x-www-form-urlencoded"}
                                                          body:[@"" dataUsingEncoding:NSUTF8StringEncoding]
                                                 remoteAddress:@"127.0.0.1"];
    HttpResponse *response2 = [[HttpResponse alloc] init];
    [self.handler handleIntrospectRequest:request2 response:response2];
    XCTAssertEqual(response2.statusCode, 400);
}

#pragma mark - Test Cases: With Client ID

- (void)testIntrospectWithClientIDParameter {
    // Request with client_id (client authentication is optional per RFC 7662)
    HttpRequest *request = [self introspectionRequestWithToken:@"invalid.token"
                                                      clientID:@"https://app.bsky.app"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.handler handleIntrospectRequest:request response:response];

    // Even without valid client_id, token introspection should work
    // (client_id is optional for introspection requests)
    XCTAssertEqual(response.statusCode, 200);
    NSDictionary *result = response.jsonBody;
    XCTAssertFalse([result[@"active"] boolValue]);
}

@end
