// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminAuthXrpcTestBase.h"
#import "Database/PDSDatabase.h"
#import "Database/Service/ServiceDatabases.h"

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

- (void)testConfirmAgeAssuranceSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    
    // 1. Begin
    HttpResponse *beginResponse = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.ageassurance.begin"
                                                           body:@{
                                                               @"email": @"test@example.com",
                                                               @"language": @"en",
                                                               @"countryCode": @"US"
                                                           }
                                                        headers:@{@"authorization": authHeader}];
    XCTAssertEqual(beginResponse.statusCode, 200);
    
    // In our implementation, the token is sent via email and stored in DB.
    // Since we are using mock email provider in tests (probably), we might not easily get the token.
    // Wait, beginAgeAssurance in service returns the tokenId for now in mock mode.
    // Actually, I changed it to NOT return tokenId in output for compliance with lexicon.
    
    // I should check the DB to get the token.
    PDSDatabase *db = [self.application.serviceDatabases serviceDatabaseWithError:nil];
    NSArray *results = [db executeParameterizedQuery:@"SELECT token FROM age_assurance_states ORDER BY created_at DESC LIMIT 1" params:@[] error:nil];
    XCTAssertGreaterThan(results.count, 0u);
    NSString *token = results[0][@"token"];
    XCTAssertNotNil(token);
    
    // 2. Confirm
    HttpResponse *confirmResponse = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.unspecced.confirmAgeAssurance"
                                                             body:@{@"token": token}
                                                          headers:@{}];
    XCTAssertEqual(confirmResponse.statusCode, 200);
    
    // 3. Check State
    HttpResponse *stateResponse = [self sendGetRequestWithPath:@"/xrpc/app.bsky.ageassurance.getState"
                                                   queryString:@"countryCode=US"
                                                   queryParams:@{@"countryCode": @"US"}
                                                       headers:@{@"authorization": authHeader}];
    XCTAssertEqual(stateResponse.statusCode, 200);
    XCTAssertEqualObjects(stateResponse.jsonBody[@"state"][@"status"], @"assured");
}

- (void)testConfirmAgeAssuranceInvalidToken {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.unspecced.confirmAgeAssurance"
                                                      body:@{@"token": @"invalid-token"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidRequest");
}

@end
