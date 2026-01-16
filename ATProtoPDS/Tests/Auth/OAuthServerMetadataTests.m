#import <XCTest/XCTest.h>
#import "Auth/OAuthServerMetadata.h"

@interface OAuthServerMetadataTests : XCTestCase
@end

@implementation OAuthServerMetadataTests

- (void)testMetadataInitialization {
    NSString *baseURL = @"https://pds.example.com";
    OAuthServerMetadata *metadata = [[OAuthServerMetadata alloc] initWithBaseURL:baseURL];
    
    XCTAssertNotNil(metadata);
    NSDictionary *dict = metadata.metadata;
    XCTAssertNotNil(dict);
    
    XCTAssertEqualObjects(dict[@"issuer"], baseURL);
    XCTAssertEqualObjects(dict[@"authorization_endpoint"], @"https://pds.example.com/oauth/authorize");
    XCTAssertEqualObjects(dict[@"token_endpoint"], @"https://pds.example.com/oauth/token");
    XCTAssertEqualObjects(dict[@"jwks_uri"], @"https://pds.example.com/oauth/jwks");
    XCTAssertTrue([dict[@"response_types_supported"] containsObject:@"code"]);
    XCTAssertTrue([dict[@"grant_types_supported"] containsObject:@"authorization_code"]);
    XCTAssertTrue([dict[@"scopes_supported"] containsObject:@"atproto"]);
}

- (void)testMetadataInvalidURL {
    XCTAssertNil([[OAuthServerMetadata alloc] initWithBaseURL:@"http://insecure.com"]);
    XCTAssertNil([[OAuthServerMetadata alloc] initWithBaseURL:@""]);
    XCTAssertNil([[OAuthServerMetadata alloc] initWithBaseURL:nil]);
    XCTAssertNil([[OAuthServerMetadata alloc] initWithBaseURL:@"not-a-url"]);
}

@end
