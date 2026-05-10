#import <XCTest/XCTest.h>
#import "Auth/OAuthServerMetadata.h"

@interface OAuthMetadataComplianceTests : XCTestCase
@end

@implementation OAuthMetadataComplianceTests

- (void)testMetadataFields {
    NSString *baseURL = @"http://127.0.0.1:2583";
    OAuthServerMetadata *metadata = [[OAuthServerMetadata alloc] initWithBaseURL:baseURL];
    XCTAssertNotNil(metadata);
    
    NSDictionary *dict = metadata.metadata;
    XCTAssertEqualObjects(dict[@"issuer"], baseURL);
    
    // ATProto OAuth spec requires these
    XCTAssertNotNil(dict[@"authorization_endpoint"]);
    XCTAssertNotNil(dict[@"token_endpoint"]);
    XCTAssertNotNil(dict[@"jwks_uri"]);
    XCTAssertNotNil(dict[@"pushed_authorization_request_endpoint"]);
    
    XCTAssertTrue([dict[@"require_pushed_authorization_requests"] boolValue]);
    XCTAssertTrue([dict[@"client_id_metadata_document_supported"] boolValue]);
    
    NSArray *responseTypes = dict[@"response_types_supported"];
    XCTAssertTrue([responseTypes containsObject:@"code"]);
    
    NSArray *grantTypes = dict[@"grant_types_supported"];
    XCTAssertTrue([grantTypes containsObject:@"authorization_code"]);
    XCTAssertTrue([grantTypes containsObject:@"refresh_token"]);
}

@end
