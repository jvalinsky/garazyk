#import "Auth/OAuthServerMetadata.h"
#import <XCTest/XCTest.h>

@interface OAuthServerMetadataTests : XCTestCase
@end

@implementation OAuthServerMetadataTests

- (void)testMetadataInitialization {
  NSString *baseURL = @"https://pds.example.com";
  OAuthServerMetadata *metadata =
      [[OAuthServerMetadata alloc] initWithBaseURL:baseURL];

  XCTAssertNotNil(metadata);
  NSDictionary *dict = metadata.metadata;
  XCTAssertNotNil(dict);

  XCTAssertEqualObjects(dict[@"issuer"], baseURL);
  XCTAssertEqualObjects(dict[@"authorization_endpoint"],
                        @"https://pds.example.com/oauth/authorize");
  XCTAssertEqualObjects(dict[@"token_endpoint"],
                        @"https://pds.example.com/oauth/token");
  XCTAssertEqualObjects(dict[@"jwks_uri"],
                        @"https://pds.example.com/oauth/jwks");
  XCTAssertTrue([dict[@"response_types_supported"] containsObject:@"code"]);
  XCTAssertTrue(
      [dict[@"grant_types_supported"] containsObject:@"authorization_code"]);
  XCTAssertEqualObjects(dict[@"require_pushed_authorization_requests"], @YES);
  XCTAssertTrue(
      [dict[@"code_challenge_methods_supported"] containsObject:@"S256"]);
  XCTAssertTrue(
      [dict[@"token_endpoint_auth_methods_supported"] containsObject:@"none"]);
  XCTAssertTrue([dict[@"token_endpoint_auth_methods_supported"]
      containsObject:@"private_key_jwt"]);
  XCTAssertTrue(
      [dict[@"dpop_signing_alg_values_supported"] containsObject:@"ES256"]);
  XCTAssertEqualObjects(dict[@"authorization_response_iss_parameter_supported"],
                        @YES);
  XCTAssertEqualObjects(dict[@"require_request_uri_registration"], @YES);
  XCTAssertEqualObjects(dict[@"client_id_metadata_document_supported"], @YES);
  XCTAssertTrue([dict[@"response_modes_supported"] containsObject:@"query"]);
  XCTAssertTrue([dict[@"response_modes_supported"] containsObject:@"fragment"]);
  XCTAssertTrue([dict[@"scopes_supported"] containsObject:@"atproto"]);
  XCTAssertTrue(
      [dict[@"scopes_supported"] containsObject:@"transition:generic"]);
}

- (void)testMetadataInvalidURL {
  XCTAssertNil(
      [[OAuthServerMetadata alloc] initWithBaseURL:@"http://insecure.com"]);
  XCTAssertNil([[OAuthServerMetadata alloc] initWithBaseURL:@""]);
  XCTAssertNil([[OAuthServerMetadata alloc] initWithBaseURL:nil]);
  XCTAssertNil([[OAuthServerMetadata alloc] initWithBaseURL:@"not-a-url"]);
}

@end
