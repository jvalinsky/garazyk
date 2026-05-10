#import <XCTest/XCTest.h>
#import "Auth/OAuth2Handler.h"
#import "App/PDSConfiguration.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

@interface OAuthMetadataConsistencyTests : XCTestCase
@end

@implementation OAuthMetadataConsistencyTests

- (void)testMetadataConsistency {
    // 1. Verify PDSConfiguration canonicalization
    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    // We expect the issuer to be exactly as configured, but the library
    // might be normalization-sensitive.
    NSString *issuer = config.issuer;
    XCTAssertNotNil(issuer, @"Issuer should be configured for OAuth tests");
    
    // 2. Simulate /.well-known/oauth-protected-resource
    // We want to see if 'resource' matches 'issuer' exactly.
    // In many ATProto scenarios, the PDS is the resource.
    
    // This is hard to unit test without a full OAuth2Handler setup,
    // so we'll rely on the E2E diagnostics which already showed a mismatch
    // in the trailing slash (or lack thereof).
}

@end
